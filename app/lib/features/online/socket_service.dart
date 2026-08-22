import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'online_models.dart';

/// Thin wrapper around a `socket_io_client` connection implementing the
/// Cyber Tavla realtime protocol: room creation/joining, dice-roll and
/// move relay, sync-state for reconnection, and rematch handshake.
///
/// This class owns exactly one socket connection at a time. It does not
/// hold any game state itself — it only translates raw socket events into
/// typed payload streams (see `online_models.dart`) for
/// `OnlineGameController` to consume, and exposes typed emit methods for
/// the outgoing half of the protocol.
///
/// Wire protocol (client -> server events):
///   create_room    { nickname }
///   join_room      { roomCode, nickname }
///   roll_dice      { roomCode }
///   make_move      { roomCode, move: Move.toJson() }
///   request_rematch{ roomCode }
///   leave_room     { roomCode }
///
/// Wire protocol (server -> client events):
///   room_created     RoomCreatedPayload
///   joined_room      JoinedRoomPayload
///   room_error       RoomErrorPayload
///   opponent_joined  { nickname }
///   opponent_left    {}
///   opponent_disconnected {}
///   opponent_reconnected  {}
///   game_start       GameStartPayload
///   dice_rolled      DiceRolledPayload
///   move_made        MoveMadePayload
///   sync_state       SyncStatePayload
///   rematch_requested {}
///   rematch_confirmed RematchConfirmedPayload
class SocketService {
  io.Socket? _socket;

  final _roomCreatedController = StreamController<RoomCreatedPayload>.broadcast();
  final _joinedRoomController = StreamController<JoinedRoomPayload>.broadcast();
  final _roomErrorController = StreamController<RoomErrorPayload>.broadcast();
  final _opponentJoinedController = StreamController<String?>.broadcast();
  final _opponentLeftController = StreamController<void>.broadcast();
  final _opponentDisconnectedController = StreamController<void>.broadcast();
  final _opponentReconnectedController = StreamController<void>.broadcast();
  final _gameStartController = StreamController<GameStartPayload>.broadcast();
  final _diceRolledController = StreamController<DiceRolledPayload>.broadcast();
  final _moveMadeController = StreamController<MoveMadePayload>.broadcast();
  final _syncStateController = StreamController<SyncStatePayload>.broadcast();
  final _rematchRequestedController = StreamController<void>.broadcast();
  final _rematchConfirmedController = StreamController<RematchConfirmedPayload>.broadcast();
  final _lobbyStatsController = StreamController<int>.broadcast();
  final _lobbyPlayersController = StreamController<List<LobbyPlayer>>.broadcast();
  final _connectErrorController = StreamController<String>.broadcast();
  final _connectedController = StreamController<void>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();
  final _reconnectFailedController = StreamController<String?>.broadcast();
  final _reconnectAttemptController = StreamController<int>.broadcast();

  /// The most recent raw error text seen from `connect_error`/`error`
  /// (whatever the underlying Dart exception's `toString()` produced —
  /// e.g. a `SocketException: Failed host lookup: ...` for DNS failures,
  /// `HandshakeException` for TLS problems, `Connection refused`/`timeout`
  /// for network-level issues). Kept around so [onReconnectFailed] can
  /// hand the UI something more diagnostic than "could not connect" once
  /// every retry has been exhausted — this is the only real diagnostic
  /// signal available for a failure that can't be reproduced from a
  /// server-side or curl-based check (see AWS_DEPLOY_GUIDE.md /
  /// project history: a passing server-side check does not rule out a
  /// device/network/carrier-level failure that never reaches the server
  /// at all).
  String? _lastErrorDetail;

  Stream<RoomCreatedPayload> get onRoomCreated => _roomCreatedController.stream;
  Stream<JoinedRoomPayload> get onJoinedRoom => _joinedRoomController.stream;
  Stream<RoomErrorPayload> get onRoomError => _roomErrorController.stream;
  Stream<String?> get onOpponentJoined => _opponentJoinedController.stream;
  Stream<void> get onOpponentLeft => _opponentLeftController.stream;
  Stream<void> get onOpponentDisconnected => _opponentDisconnectedController.stream;
  Stream<void> get onOpponentReconnected => _opponentReconnectedController.stream;
  Stream<GameStartPayload> get onGameStart => _gameStartController.stream;
  Stream<DiceRolledPayload> get onDiceRolled => _diceRolledController.stream;
  Stream<MoveMadePayload> get onMoveMade => _moveMadeController.stream;
  Stream<SyncStatePayload> get onSyncState => _syncStateController.stream;
  Stream<void> get onRematchRequested => _rematchRequestedController.stream;
  Stream<RematchConfirmedPayload> get onRematchConfirmed => _rematchConfirmedController.stream;

  /// How many rooms are currently open and waiting for a second player,
  /// server-wide. Sent once right after connecting and re-broadcast
  /// whenever it changes — purely informational for a lobby-screen
  /// indicator, not tied to this client's own room state.
  Stream<int> get onLobbyStats => _lobbyStatsController.stream;

  /// The other players currently idle in the lobby (self excluded) that
  /// this socket can [challengePlayer]. Only populated for sockets that
  /// have called [enterLobby]; sent again every time the idle set changes.
  Stream<List<LobbyPlayer>> get onLobbyPlayers => _lobbyPlayersController.stream;
  Stream<String> get onConnectError => _connectErrorController.stream;
  Stream<void> get onConnected => _connectedController.stream;
  Stream<void> get onDisconnected => _disconnectedController.stream;

  /// Fires only after the client has exhausted every automatic
  /// reconnection attempt (see [connect]'s `setReconnectionAttempts`) —
  /// the signal the UI should actually treat as "give up and show an
  /// error", as opposed to the transient `onConnectError` events fired on
  /// each individual failed attempt while retries are still in flight.
  /// Carries the last raw error text seen (see [_lastErrorDetail]), or
  /// `null` if somehow none was ever captured.
  Stream<String?> get onReconnectFailed => _reconnectFailedController.stream;

  /// Fires before each automatic retry (attempt number, 1-based) — used by
  /// the UI to swap the generic "connecting..." spinner text for a
  /// "server is waking up" hint once it's clear the first attempt(s)
  /// didn't land instantly (see [OnlineGameController]).
  Stream<int> get onReconnectAttempt => _reconnectAttemptController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Opens a connection to the realtime server at [serverUrl] (e.g.
  /// `https://tavla-server.onrender.com`). Safe to call again after
  /// [dispose] to reconnect with a possibly different URL.
  ///
  /// Transport list is `['polling']` — WebSocket upgrade TEMPORARILY
  /// disabled entirely as a diagnostic (see project history: Piyami sees
  /// a real 'Sunucuya bağlanılamadı (detay: timeout)' on his mobile
  /// carrier network even though (a) a direct browser hit to the plain
  /// polling handshake endpoint succeeds instantly on that exact network,
  /// and (b) a manual curl WebSocket-upgrade handshake against the nginx
  /// proxy from an unconstrained network confirms nginx's WS proxying
  /// itself is configured correctly. That leaves the WS upgrade probe
  /// specifically hanging on his carrier path as the leading remaining
  /// suspect, since it's the one connection step a bare browser GET never
  /// exercises. This build removes it entirely so we can isolate whether
  /// pure long-polling connects reliably on that network — restore
  /// `['polling', 'websocket']` once that's confirmed one way or another.
  ///
  /// Previously (kept for context): the list order is the priority order
  /// the client opens its *initial* transport with, not just a fallback
  /// pool — putting `websocket` first (an earlier version of this code
  /// did) made every single connection AND every retry attempt a raw
  /// WebSocket handshake, which needs a full HTTP Upgrade to succeed
  /// through every proxy in front of the server; on Render's free tier
  /// (fronted by Cloudflare) that upgrade could hang indefinitely instead
  /// of failing fast, which is what made the app get stuck forever on the
  /// connecting screen back then. Polling-first (when websocket is
  /// present in the list at all) means the initial handshake is a plain
  /// HTTP request that always gets through, and the socket transparently
  /// upgrades to WebSocket in the background afterwards.
  ///
  /// Timeout/retry values below assume an always-on server that responds
  /// in well under a second when healthy (the current deployment target,
  /// Piyami's own AWS instance) — NOT the cold-starting Render free tier
  /// this was originally tuned for (that old tuning allowed up to ~90s+
  /// of retrying to cover a documented ~60s wake time, which is no
  /// longer a real scenario and only made every real failure take
  /// minutes to surface). Each attempt waits up to 10s for a response
  /// before being abandoned, and up to 5 attempts are made — comfortably
  /// enough to ride out a brief blip or restart, while still reaching
  /// [onReconnectFailed] in well under a minute for a genuine outage
  /// instead of leaving the player staring at a spinner.
  void connect(String serverUrl) {
    _socket?.dispose();

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['polling']) // diagnostic: WS upgrade disabled, see class doc above
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1500)
          .setReconnectionDelayMax(5000)
          .setTimeout(10000)
          .build(),
    );

    socket.onConnect((_) {
      _lastErrorDetail = null;
      _connectedController.add(null);
    });
    socket.onDisconnect((_) => _disconnectedController.add(null));
    socket.onConnectError((data) {
      _lastErrorDetail = data?.toString() ?? 'connect_error';
      // ignore: avoid_print
      print('[SocketService] connect_error: $_lastErrorDetail');
      _connectErrorController.add(_lastErrorDetail!);
    });
    socket.onError((data) {
      _lastErrorDetail = data?.toString() ?? 'error';
      // ignore: avoid_print
      print('[SocketService] socket error: $_lastErrorDetail');
      _connectErrorController.add(_lastErrorDetail!);
    });
    socket.onReconnectFailed((_) => _reconnectFailedController.add(_lastErrorDetail));
    socket.onReconnectAttempt((data) {
      final attempt = data is int ? data : int.tryParse(data?.toString() ?? '') ?? 0;
      _reconnectAttemptController.add(attempt);
    });

    socket.on('room_created', (data) {
      _roomCreatedController.add(RoomCreatedPayload.fromJson(_asMap(data)));
    });
    socket.on('joined_room', (data) {
      _joinedRoomController.add(JoinedRoomPayload.fromJson(_asMap(data)));
    });
    socket.on('room_error', (data) {
      _roomErrorController.add(RoomErrorPayload.fromJson(_asMap(data)));
    });
    socket.on('opponent_joined', (data) {
      final map = _asMap(data);
      _opponentJoinedController.add(map['nickname'] as String?);
    });
    socket.on('opponent_left', (_) => _opponentLeftController.add(null));
    socket.on('opponent_disconnected', (_) => _opponentDisconnectedController.add(null));
    socket.on('opponent_reconnected', (_) => _opponentReconnectedController.add(null));
    socket.on('game_start', (data) {
      _gameStartController.add(GameStartPayload.fromJson(_asMap(data)));
    });
    socket.on('dice_rolled', (data) {
      _diceRolledController.add(DiceRolledPayload.fromJson(_asMap(data)));
    });
    socket.on('move_made', (data) {
      _moveMadeController.add(MoveMadePayload.fromJson(_asMap(data)));
    });
    socket.on('sync_state', (data) {
      _syncStateController.add(SyncStatePayload.fromJson(_asMap(data)));
    });
    socket.on('rematch_requested', (_) => _rematchRequestedController.add(null));
    socket.on('rematch_confirmed', (data) {
      _rematchConfirmedController.add(RematchConfirmedPayload.fromJson(_asMap(data)));
    });
    socket.on('lobby_stats', (data) {
      final map = _asMap(data);
      final count = map['waitingRooms'];
      _lobbyStatsController.add(count is int ? count : int.tryParse(count?.toString() ?? '') ?? 0);
    });
    socket.on('lobby_players', (data) {
      final map = _asMap(data);
      final rawList = map['players'];
      final players = (rawList is List)
          ? rawList.map((e) => LobbyPlayer.fromJson(_asMap(e))).toList()
          : <LobbyPlayer>[];
      _lobbyPlayersController.add(players);
    });

    _socket = socket;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  void createRoom(String nickname) {
    _socket?.emit('create_room', {'nickname': nickname});
  }

  /// Marks this socket idle/challengeable in the lobby under [nickname].
  /// Safe to call before the socket has actually connected — Socket.io
  /// buffers emits made while disconnected and flushes them on connect.
  void enterLobby(String nickname) {
    _socket?.emit('enter_lobby', {'nickname': nickname});
  }

  /// Opposite of [enterLobby] — leaves the lobby screen without starting
  /// a match, so this socket stops showing up in others' challenge lists.
  void leaveLobby() {
    _socket?.emit('leave_lobby', {});
  }

  /// Directly starts a match against another idle player by socket id
  /// (see [LobbyPlayer.id]), skipping the manual create/share-code/join
  /// flow. Fails with a `room_error` if [targetId] is no longer idle.
  void challengePlayer(String targetId) {
    _socket?.emit('challenge_player', {'targetId': targetId});
  }

  void joinRoom(String roomCode, String nickname) {
    _socket?.emit('join_room', {'roomCode': roomCode, 'nickname': nickname});
  }

  void rollDice(String roomCode) {
    _socket?.emit('roll_dice', {'roomCode': roomCode});
  }

  void makeMove(String roomCode, Map<String, dynamic> moveJson) {
    _socket?.emit('make_move', {'roomCode': roomCode, 'move': moveJson});
  }

  void requestRematch(String roomCode) {
    _socket?.emit('request_rematch', {'roomCode': roomCode});
  }

  void leaveRoom(String roomCode) {
    _socket?.emit('leave_room', {'roomCode': roomCode});
  }

  /// Requests a fresh `sync_state` for [roomCode] — used right after a
  /// reconnection to rebuild local game state from the authoritative log.
  /// [color] and [nickname] let the server re-attach this (new) socket id
  /// to the seat it previously held, since Socket.io issues a new socket
  /// id on every reconnect.
  void requestSync(String roomCode, {required String color, String? nickname}) {
    _socket?.emit('request_sync', {
      'roomCode': roomCode,
      'color': color,
      if (nickname != null) 'nickname': nickname,
    });
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _roomCreatedController.close();
    _joinedRoomController.close();
    _roomErrorController.close();
    _opponentJoinedController.close();
    _opponentLeftController.close();
    _opponentDisconnectedController.close();
    _opponentReconnectedController.close();
    _gameStartController.close();
    _diceRolledController.close();
    _moveMadeController.close();
    _syncStateController.close();
    _rematchRequestedController.close();
    _rematchConfirmedController.close();
    _lobbyStatsController.close();
    _lobbyPlayersController.close();
    _connectErrorController.close();
    _connectedController.close();
    _disconnectedController.close();
    _reconnectFailedController.close();
    _reconnectAttemptController.close();
  }
}