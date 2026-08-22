import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/game_state.dart';
import '../../shared/moves.dart';
import '../../shared/player.dart';
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
    );
  }
}

/// Identifies one online session's connection parameters. Two configs with
/// the same values are treated as the same provider instance by Riverpod's
/// family caching.
class OnlineConfig {
  final String serverUrl;
  final String nickname;

  const OnlineConfig({required this.serverUrl, required this.nickname});

  @override
  bool operator ==(Object other) =>
      other is OnlineConfig && other.serverUrl == serverUrl && other.nickname == nickname;

  @override
  int get hashCode => Object.hash(serverUrl, nickname);
}

/// Drives the multiplayer lobby + in-match experience: owns a
/// [SocketService] connection, turns raw protocol events into a local
/// [GameState] mirror (using `applyRoll` / `applyMove` so both peers derive
/// identical state from the same authoritative event stream), and exposes
/// room/rematch actions for the UI.
///
/// Move validation itself still happens locally via the shared Dart engine
/// (the mover only ever sends moves already confirmed legal by
/// `GameState.legalMoves()`); the server's job is limited to rooms,
/// matchmaking, relaying dice/move events, and replaying its authoritative
/// event log to reconnecting clients. Porting the engine to run
/// server-side for independent validation is tracked as future work (see
/// README).
class OnlineGameController extends StateNotifier<OnlineState> {
  final OnlineConfig config;
  final SocketService _socket = SocketService();
  final List<StreamSubscription<dynamic>> _subs = [];

  OnlineGameController(this.config) : super(OnlineState.initial()) {
    _connect();
  }

  void _connect() {
    state = state.copyWith(
      status: ConnectionStatus.connecting,
      clearError: true,
      clearConnectingHint: true,
    );
    _socket.connect(config.serverUrl);

    _subs.addAll([
      _socket.onConnected.listen((_) {
        if (state.roomCode == null || state.myColor == null) {
          state = state.copyWith(status: ConnectionStatus.connected, clearConnectingHint: true);
        } else {
          // Reconnected mid-match (Socket.io issues a new socket id on
          // every reconnect): ask the server to re-attach this socket to
          // our previous seat and replay its authoritative event log.
          _socket.requestSync(
            state.roomCode!,
            color: state.myColor!.wireValue,
            nickname: config.nickname,
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
      _socket.onReconnectFailed.listen((_) {
        state = state.copyWith(
          status: ConnectionStatus.error,
          errorMessage: 'Sunucuya bağlanılamadı',
        );
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
    ]);
  }

  void createRoom() => _socket.createRoom(config.nickname);

  void joinRoom(String roomCode) {
    final normalized = roomCode.trim().toUpperCase();
    if (normalized.isEmpty) return;
    _socket.joinRoom(normalized, config.nickname);
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

  void leaveRoom() {
    final room = state.roomCode;
    if (room != null) _socket.leaveRoom(room);
    state = OnlineState.initial().copyWith(status: ConnectionStatus.connected);
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

final onlineGameControllerProvider =
    StateNotifierProvider.autoDispose.family<OnlineGameController, OnlineState, OnlineConfig>(
  (ref, config) => OnlineGameController(config),
);