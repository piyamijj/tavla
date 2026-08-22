import 'board.dart';
import 'player.dart';

/// A single checker move: one die value applied to move one checker from
/// [from] to [to].
///
/// [from] is a point index (0-23) or [kBarIndex] when entering from the
/// bar. [to] is a point index (0-23) or [kOffIndex] when bearing off.
class Move {
  final PlayerColor player;
  final int from;
  final int to;
  final int die;

  /// Whether this move hits (captures) a single opposing checker (a blot)
  /// sitting on [to]. Computed by the rules engine when the move is
  /// generated, since it depends on the board state at generation time.
  final bool isHit;

  const Move({
    required this.player,
    required this.from,
    required this.to,
    required this.die,
    this.isHit = false,
  });

  bool get isFromBar => from == kBarIndex;
  bool get isBearOff => to == kOffIndex;

  Move copyWith({bool? isHit}) => Move(
        player: player,
        from: from,
        to: to,
        die: die,
        isHit: isHit ?? this.isHit,
      );

  @override
  String toString() {
    final fromLabel = isFromBar ? 'bar' : '${from + 1}';
    final toLabel = isBearOff ? 'off' : '${to + 1}';
    final hitLabel = isHit ? '*' : '';
    return '$fromLabel/$toLabel$hitLabel(d$die)';
  }

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.player == player &&
      other.from == from &&
      other.to == to &&
      other.die == die;

  @override
  int get hashCode => Object.hash(player, from, to, die);

  /// Serializes to a JSON-safe map for the realtime server / socket
  /// protocol. The receiving peer re-derives [isHit] locally when applying
  /// the move to its own board via `TavlaRules.applyMove`, so it is not
  /// strictly required on the wire, but is included for logging/UI use.
  Map<String, dynamic> toJson() => {
        'player': player.wireValue,
        'from': from,
        'to': to,
        'die': die,
        'isHit': isHit,
      };

  factory Move.fromJson(Map<String, dynamic> json) => Move(
        player: PlayerColor.fromWire(json['player'] as String),
        from: json['from'] as int,
        to: json['to'] as int,
        die: json['die'] as int,
        isHit: json['isHit'] as bool? ?? false,
      );
}