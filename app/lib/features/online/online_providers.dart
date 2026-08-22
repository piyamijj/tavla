import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/game_state.dart';
import '../../shared/moves.dart';
import '../../shared/player.dart';
import '../settings/settings_providers.dart';
import 'online_models.dart';
import 'socket_service.dart';

/// Coarse-grained connection/room lifecycle for the multiplayer feature.
enum ConnectionStatus {
  /// Socket not yet connected.
  disconnected,

  /// Socket connection attempt in flight.
  connecting,

  /// Socket connected, but not yet in a room (lobby screen).
  connected,

  /// Socket connected and a room exists, waiting for the opponent seat to
  /// fill.
  waitingForOpponent,

  /// Both seats filled — a match is starting or in progress.
  inMatch,

  /// A connection or room-join attempt failed; [OnlineState.errorMessage]
  /// carries a human-readable (Turkish) reason.
  error,
}

/// Immutable snapshot of everything the multiplayer UI needs: connection
/// status, room/opponent info, the local mirror of the shared engine's
/// [GameState], and rematch handshake flags.
class OnlineState {
  final ConnectionStatus status;
  final String? roomCode;
  final PlayerColor? myColor;
  final String? opponentNickname;
  final bool opponentConnected;
  final GameState? game;
  final String? errorMessage;
  final bool rematchRequestedByMe;
  final bool rematchOfferedByOpponent;

  /// Only meaningful while [status] is [ConnectionStatus.connecting]:
  /// overrides the generic "connecting..." spinner text once the first
  /// attempt has failed and the client has moved on to an automatic
  /// retry — this is what tells the player a Render free-tier cold start
  /// is likely in progress instead of leaving them staring at a spinner
  /// with no explanation for up to ~90 seconds.
  final String? connectingHint;

  /// How many rooms are currently open server-wide, waiting for a second
  /// player — `null` until the first `lobby_stats` event arrives just
  /// after connecting. Purely informational (see [SocketService.onLobbyStats]).
  final int? waitingRooms;

  /// Other players currently idle in the lobby and available to
  /// [OnlineGameController.challengePlayer] directly — empty until the
  /// first `lobby_players` event arrives, which only happens once this
  /// socket has itself called [OnlineGameController.enterLobby].
  final List<LobbyPlayer> idlePlayers;

  const OnlineState({
    required this.status,
    this.roomCode,
    this.myColor,
    this.opponentNickname,
    this.opponentConnected = true,
    this.game,
    this.errorMessage,
    this.rematchRequestedByMe = false,
    this.rematchOfferedByOpponent = false,
    this.connectingHint,
    this.waitingRooms,
    this.idlePlayers = const [],
  });

  factory OnlineState.initial() => const OnlineState(status: ConnectionStatus.disconnected);

  OnlineState copyWith({
    ConnectionStatus? status,
    String? roomCode,
    PlayerColor? myColor,
    String? opponentNickname,
    bool? opponentConnected,
    GameState? game,
    String? errorMessage,
    bool clearError = false,
    bool? rematchRequestedByMe,
    bool? rematchOfferedByOpponent,
    String? connectingHint,
    bool clearConnectingHint = false,
    int? waitingRooms,
    List<LobbyPlayer>? idlePlayers,
  }) {
    return OnlineState(
      status: status ?? this.status,
      roomCode: roomCode ?? this.roomCode,
      myColor: myColor ?? this.myColor,
      opponentNickname: opponentNickname ?? this.opponentNickname,
      opponentConnected: opponentConnected ?? this.opponentConnected,
      game: game ?? this.game,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      rematchRequestedByMe: rematchRequestedByMe ?? this.rematchRequestedByMe,
      rematchOfferedByOpponent: rematchOfferedByOpponent ?? this.rematchOfferedByOpponent,
      connectingHint: clearConnectingHint ? null : (connectingHint ?? this.connectingHint),
      waitingRooms: waitingRooms ?? this.waitingRooms,
      idlePlayers: idlePlayers ?? this.idlePlayers,
    );
  }
}

/// Drives the multiplayer lobby + in-match experience for the WHOLE app
/// lifetime: owns a single [SocketService] connection that is opened as
/// soon as this provider is first read (see `main.dart`, which reads it
/// eagerly at startup so the connection is already warm by the time the
/// player opens the multiplayer screen — no more connect-and-wait cycle
/// on entry), turns raw protocol events into a local [GameState] mirror
/// (using `applyRoll` / `applyMove` so both peers derive identical state
/// from the same authoritative event stream), and exposes room/rematch/
/// lobby actions for the UI.
///
/// Deliberately NOT a `family` keyed by server URL + nickname (an earlier
/// version was): nickname is just UI text the player can retype at any
/// time, and keying a provider family by it would spin up a brand new
/// socket connection — and silently orphan the old one, since this
/// provider is not `autoDispose` — every time they edited the field.
/// Nickname is tracked as a plain mutable field instead ([_nickname],
/// set via [setNickname]) and the connection itself only depends on
/// [AppSettings.serverUrl], which this controller watches and reconnects
/// to if it ever changes (see the `ref.listen` in the constructor).
///
/// Move validation itself still happens locally via the shared Dart engine
/// (the mover only ever sends moves already confirmed legal by
/// `GameState.legalMoves()`); the server's job is limited to rooms,
/// matchmaking, relaying dice/move events, and replaying its authoritative
/// event log to reconnecting clients. Porting the engine to run
/// server-side for independent validation is tracked as future work (see
/// README).
class OnlineGameController extends StateNotifier<OnlineState> {
  final Ref _ref;
  final SocketService _socket = SocketService();
  final List<StreamSubscription<dynamic>> _subs = [];

  String _nickname = 'Oyuncu';
  String? _connectedServerUrl;

  /// Whether the player has called [enterLobby] and not yet [leaveLobby]
  /// (or started a match) — tracked so a reconnect (new socket id, so the
  /// server's idle registry no longer has us) can transparently resend
  /// `enter_lobby` instead of the player just silently vanishing from
  /// everyone else's challenge list.
  bool _wantsLobbyPresence = false;

  OnlineGameController(this._ref) : super(OnlineState.initial()) {
    _connect(_ref.read(settingsProvider).serverUrl);

    _ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (next.serverUrl != _connectedServerUrl) {
        _connect(next.serverUrl);
      }
    });
  }

  void _connect(String serverUrl) {
    _connectedServerUrl = serverUrl;
    state = state.copyWith(
      status: ConnectionStatus.connecting,
      clearError: true,
      clearConnectingHint: true,
    );
    _socket.connect(serverUrl);

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();

    _subs.addAll([
      _socket.onConnected.listen((_) {
        if (state.roomCode == null || state.myColor == null) {
          state = state.copyWith(status: ConnectionStatus.connected, clearConnectingHint: true);
          if (_wantsLobbyPresence) _socket.enterLobby(_nickname);
        } else {
          // Reconnected mid-match (Socket.io issues a new socket id on
          // every reconnect): ask the server to re-attach this socket to
          // our previous seat and replay its authoritative event log.
          _socket.requestSync(
            state.roomCode!,
            color: state.myColor!.wireValue,
            nickname: _nickname,
          );
        }
      }),
      _socket.onConnectError.listen((_) {
        // A single failed attempt is not fatal — automatic reconnection
        // (see SocketService.connect) keeps retrying underneath, which
        // matters most right after a Render free-tier instance wakes up
        // from sleep (the first few attempts routinely fail while it
        // boots). Only flip to the error screen once retries are fully
        // exhausted, via onReconnectFailed below; until then just stay on
        // the connecting spinner.
      }),
      _socket.onReconnectFailed.listen((detail) {
        // Append the raw underlying error (DNS failure, TLS/handshake
        // error, connection refused, timeout, etc.) so a failure that
        // can't be reproduced from a server-side/curl check — e.g. a
        // carrier or device-network issue that never reaches the server
        // at all — is at least visible to whoever is looking at the
        // screen, instead of a single generic message that could mean
        // anything.
        final message = (detail == null || detail.isEmpty)
            ? 'Sunucuya bağlanılamadı'
            : 'Sunucuya bağlanılamadı\n(detay: $detail)';
        state = state.copyWith(status: ConnectionStatus.error, errorMessage: message);
      }),
      _socket.onReconnectAttempt.listen((_) {
        // The first attempt never got a callback here — this only fires
        // once a retry is scheduled, i.e. the previous attempt already
        // failed or timed out. That's exactly the moment to stop showing
        // a generic spinner and tell the player what's actually likely
        // happening (their Render instance waking up from sleep).
        if (state.status == ConnectionStatus.connecting) {
          state = state.copyWith(
            connectingHint: 'Sunucu uyandırılıyor, lütfen bekleyin...',
          );
        }
      }),
      _socket.onDisconnected.listen((_) {
        if (state.roomCode != null) {
          state = state.copyWith(opponentConnected: state.opponentConnected);
        }
      }),
      _socket.onRoomCreated.listen((p) {
        state = state.copyWith(
          roomCode: p.roomCode,
          myColor: p.color,
          status: ConnectionStatus.waitingForOpponent,
          clearError: true,
        );
      }),
      _socket.onJoinedRoom.listen((p) {
        state = state.copyWith(
          roomCode: p.roomCode,
          myColor: p.color,
          opponentNickname: p.opponentNickname,
          status: ConnectionStatus.waitingForOpponent,
          clearError: true,
        );
      }),
      _socket.onRoomError.listen((e) {
        state = state.copyWith(status: ConnectionStatus.error, errorMessage: e.message);
      }),
      _socket.onOpponentJoined.listen((nickname) {
        state = state.copyWith(opponentNickname: nickname, opponentConnected: true);
      }),
      _socket.onOpponentLeft.listen((_) {
        state = state.copyWith(opponentConnected: false, errorMessage: 'Rakip odadan ayrıldı');
      }),
      _socket.onOpponentDisconnected.listen((_) {
        state = state.copyWith(opponentConnected: false);
      }),
      _socket.onOpponentReconnected.listen((_) {
        state = state.copyWith(opponentConnected: true, clearError: true);
      }),
      _socket.onGameStart.listen((p) {
        state = state.copyWith(
          game: GameState.newGame(startingPlayer: p.startingPlayer),
          status: ConnectionStatus.inMatch,
        );
      }),
      _socket.onDiceRolled.listen((p) {
        final g = state.game;
        if (g == null || g.phase != GamePhase.awaitingRoll) return;
        state = state.copyWith(game: g.applyRoll(p.roll));
      }),
      _socket.onMoveMade.listen((p) {
        final g = state.game;
        if (g == null) return;
        state = state.copyWith(game: g.applyMove(p.move));
      }),
      _socket.onSyncState.listen((p) {
        var replayed = GameState.newGame(startingPlayer: p.startingPlayer);
        for (final event in p.events) {
          replayed = event.type == GameEventType.roll
              ? replayed.applyRoll(event.roll!)
              : replayed.applyMove(event.move!);
        }
        state = state.copyWith(
          game: replayed,
          status: ConnectionStatus.inMatch,
          opponentNickname: p.opponentNickname ?? state.opponentNickname,
          opponentConnected: p.opponentConnected,
          clearError: true,
        );
      }),
      _socket.onRematchRequested.listen((_) {
        state = state.copyWith(rematchOfferedByOpponent: true);
      }),
      _socket.onRematchConfirmed.listen((p) {
        state = state.copyWith(
          game: GameState.newGame(startingPlayer: p.startingPlayer),
          status: ConnectionStatus.inMatch,
          rematchRequestedByMe: false,
          rematchOfferedByOpponent: false,
        );
      }),
      _socket.onLobbyStats.listen((count) {
        state = state.copyWith(waitingRooms: count);
      }),
      _socket.onLobbyPlayers.listen((players) {
        state = state.copyWith(idlePlayers: players);
      }),
    ]);
  }

  /// Updates the nickname used for every subsequent lobby/room action
  /// (create/join/challenge/enterLobby). Does not by itself notify the
  /// server — call [enterLobby] again if already idle and the visible
  /// name should update immediately.
  void setNickname(String nickname) {
    final trimmed = nickname.trim();
    _nickname = trimmed.isEmpty ? 'Oyuncu' : trimmed;
  }

  /// Marks the player idle/challengeable in the lobby under the current
  /// nickname (see [setNickname]) — called when the multiplayer lobby
  /// screen opens. Safe to call before the socket has connected.
  void enterLobby() {
    _wantsLobbyPresence = true;
    _socket.enterLobby(_nickname);
  }

  /// Opposite of [enterLobby] — called when the lobby screen closes
  /// without starting a match.
  void leaveLobby() {
    _wantsLobbyPresence = false;
    _socket.leaveLobby();
    state = state.copyWith(idlePlayers: const []);
  }

  /// Directly challenges [player] to a match, skipping the manual
  /// create/share-code/join flow. If they're no longer idle by the time
  /// this arrives, the server replies with a `room_error`, handled the
  /// same way any other room error is (see the `onRoomError` listener
  /// above).
  void challengePlayer(LobbyPlayer player) {
    _wantsLobbyPresence = false;
    _socket.challengePlayer(player.id);
  }

  /// Forces a fresh connection attempt against the current server URL —
  /// used by the error screen's retry button. A no-op guard isn't needed
  /// here since [_connect] already cancels and replaces every previous
  /// subscription itself.
  void retryConnect() => _connect(_ref.read(settingsProvider).serverUrl);

  void createRoom() {
    _wantsLobbyPresence = false;
    _socket.createRoom(_nickname);
  }

  void joinRoom(String roomCode) {
    final normalized = roomCode.trim().toUpperCase();
    if (normalized.isEmpty) return;
    _wantsLobbyPresence = false;
    _socket.joinRoom(normalized, _nickname);
  }

  /// Requests the server roll the dice for the current turn. Both peers —
  /// including this one — receive the authoritative result via
  /// `dice_rolled` and apply it identically; this method does not apply
  /// anything locally itself.
  void rollDice() {
    final g = state.game;
    final room = state.roomCode;
    if (g == null || room == null) return;
    if (g.phase != GamePhase.awaitingRoll || g.currentPlayer != state.myColor) return;
    _socket.rollDice(room);
  }

  /// Applies [move] — already validated locally via `GameState.legalMoves()`
  /// — optimistically to the local mirror, then relays it to the opponent.
  void playMove(Move move) {
    final g = state.game;
    final room = state.roomCode;
    if (g == null || room == null) return;
    if (g.phase != GamePhase.awaitingMove || move.player != state.myColor) return;
    state = state.copyWith(game: g.applyMove(move));
    _socket.makeMove(room, move.toJson());
  }

  void requestRematch() {
    final room = state.roomCode;
    if (room == null) return;
    _socket.requestRematch(room);
    state = state.copyWith(rematchRequestedByMe: true);
  }

  /// Leaves the current room and returns to the lobby, immediately
  /// re-entering it as idle/challengeable — matches the natural
  /// expectation that finishing or abandoning a match puts you back
  /// among the players others can challenge, not into limbo.
  void leaveRoom() {
    final room = state.roomCode;
    if (room != null) _socket.leaveRoom(room);
    state = OnlineState.initial().copyWith(status: ConnectionStatus.connected);
    enterLobby();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _socket.dispose();
    super.dispose();
  }
}

/// Single app-wide multiplayer connection — deliberately not a `family`
/// and not `autoDispose` (see the class doc on [OnlineGameController]):
/// created once, lives for the app's whole lifetime, and is read eagerly
/// in `main.dart` so the socket is already connecting in the background
/// before the player ever opens the multiplayer screen.
final onlineGameControllerProvider = StateNotifierProvider<OnlineGameController, OnlineState>(
  (ref) => OnlineGameController(ref),
);