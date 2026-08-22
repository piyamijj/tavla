import '../../shared/dice.dart';
import '../../shared/moves.dart';
import '../../shared/player.dart';

/// The two kinds of authoritative events the realtime server logs for a
/// room: a dice roll or an applied move. Replaying an ordered list of
/// these on top of `GameState.newGame(startingPlayer: ...)` deterministically
/// reconstructs the exact game state — this is what makes reconnection
/// possible without the server itself running the rules engine.
enum GameEventType { roll, move }

/// A single authoritative event in a room's history, as sent by the
/// server inside a `sync_state` payload.
class GameEvent {
  final GameEventType type;
  final DiceRoll? roll;
  final Move? move;

  const GameEvent.roll(DiceRoll roll)
      : type = GameEventType.roll,
        roll = roll,
        move = null;

  const GameEvent.move(Move move)
      : type = GameEventType.move,
        roll = null,
        move = move;

  factory GameEvent.fromJson(Map<String, dynamic> json) {
    final typeValue = json['type'] as String;
    if (typeValue == 'roll') {
      return GameEvent.roll(DiceRoll.fromJson(json['roll'] as Map<String, dynamic>));
    }
    if (typeValue == 'move') {
      return GameEvent.move(Move.fromJson(json['move'] as Map<String, dynamic>));
    }
    throw ArgumentError.value(typeValue, 'type', 'Unknown GameEventType wire value');
  }

  Map<String, dynamic> toJson() => {
        'type': type == GameEventType.roll ? 'roll' : 'move',
        if (roll != null) 'roll': roll!.toJson(),
        if (move != null) 'move': move!.toJson(),
      };
}

/// Result of successfully creating a room: the server-assigned room code
/// and which color the creator will play (always white, the first player).
class RoomCreatedPayload {
  final String roomCode;
  final PlayerColor color;

  const RoomCreatedPayload({required this.roomCode, required this.color});

  factory RoomCreatedPayload.fromJson(Map<String, dynamic> json) => RoomCreatedPayload(
        roomCode: json['roomCode'] as String,
        color: PlayerColor.fromWire(json['color'] as String),
      );
}

/// Result of successfully joining an existing room: which color the
/// joiner was assigned (always black, the second player) and the other
/// player's nickname, if known.
class JoinedRoomPayload {
  final String roomCode;
  final PlayerColor color;
  final String? opponentNickname;

  const JoinedRoomPayload({
    required this.roomCode,
    required this.color,
    this.opponentNickname,
  });

  factory JoinedRoomPayload.fromJson(Map<String, dynamic> json) => JoinedRoomPayload(
        roomCode: json['roomCode'] as String,
        color: PlayerColor.fromWire(json['color'] as String),
        opponentNickname: json['opponentNickname'] as String?,
      );
}

/// A rejected `join_room` / `create_room` attempt, with a human-readable
/// (Turkish) reason suitable for direct display.
class RoomErrorPayload {
  final String message;

  const RoomErrorPayload({required this.message});

  factory RoomErrorPayload.fromJson(Map<String, dynamic> json) =>
      RoomErrorPayload(message: json['message'] as String? ?? 'Bilinmeyen hata');
}

/// Broadcast once both seats in a room are filled: tells both clients the
/// match may begin and who rolls/moves first.
class GameStartPayload {
  final PlayerColor startingPlayer;

  const GameStartPayload({required this.startingPlayer});

  factory GameStartPayload.fromJson(Map<String, dynamic> json) => GameStartPayload(
        startingPlayer: PlayerColor.fromWire(json['startingPlayer'] as String),
      );
}

/// An authoritative dice roll broadcast by the server after the
/// current-turn player requests one.
class DiceRolledPayload {
  final DiceRoll roll;

  const DiceRolledPayload({required this.roll});

  factory DiceRolledPayload.fromJson(Map<String, dynamic> json) =>
      DiceRolledPayload(roll: DiceRoll.fromJson(json));
}

/// A move relayed from the peer who played it.
class MoveMadePayload {
  final Move move;

  const MoveMadePayload({required this.move});

  factory MoveMadePayload.fromJson(Map<String, dynamic> json) =>
      MoveMadePayload(move: Move.fromJson(json['move'] as Map<String, dynamic>));
}

/// Full authoritative history for a room, sent to a (re)connecting client
/// so it can rebuild the exact `GameState` locally by replaying
/// [events] on top of a fresh game started by [startingPlayer].
class SyncStatePayload {
  final PlayerColor startingPlayer;
  final List<GameEvent> events;
  final String? opponentNickname;
  final bool opponentConnected;

  const SyncStatePayload({
    required this.startingPlayer,
    required this.events,
    this.opponentNickname,
    this.opponentConnected = true,
  });

  factory SyncStatePayload.fromJson(Map<String, dynamic> json) {
    final rawEvents = (json['events'] as List<dynamic>? ?? const [])
        .map((e) => GameEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    return SyncStatePayload(
      startingPlayer: PlayerColor.fromWire(json['startingPlayer'] as String),
      events: rawEvents,
      opponentNickname: json['opponentNickname'] as String?,
      opponentConnected: json['opponentConnected'] as bool? ?? true,
    );
  }
}

/// Broadcast once both players have requested a rematch: the new match's
/// starting player (colors are swapped each rematch by convention).
class RematchConfirmedPayload {
  final PlayerColor startingPlayer;

  const RematchConfirmedPayload({required this.startingPlayer});

  factory RematchConfirmedPayload.fromJson(Map<String, dynamic> json) => RematchConfirmedPayload(
        startingPlayer: PlayerColor.fromWire(json['startingPlayer'] as String),
      );
}