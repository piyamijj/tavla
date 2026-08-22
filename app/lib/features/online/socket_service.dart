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
  final _connectErrorController = StreamController<String>.broadcast();
  final _connectedController = StreamController<void>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();

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
  Stream<String> get onConnectError => _connectErrorController.stream;
  Stream<void> get onConnected => _connectedController.stream;
  Stream<void> get onDisconnected => _disconnectedController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Opens a connection to the realtime server at [serverUrl] (e.g.
  /// `https://tavla-server.onrender.com`). Safe to call again after
  /// [dispose] to reconnect with a possibly different URL.
  void connect(String serverUrl) {
    _socket?.dispose();

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .build(),
    );

    socket.onConnect((_) => _connectedController.add(null));
    socket.onDisconnect((_) => _disconnectedController.add(null));
    socket.onConnectError((data) => _connectErrorController.add(data?.toString() ?? 'connect_error'));
    socket.onError((data) => _connectErrorController.add(data?.toString() ?? 'error'));

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
    _connectErrorController.close();
    _connectedController.close();
    _disconnectedController.close();
  }
}