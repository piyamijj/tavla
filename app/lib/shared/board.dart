import 'player.dart';

/// Sentinel index representing the bar (captured checkers waiting to
/// re-enter) in move descriptions. Not a valid [Board.points] index.
const int kBarIndex = -1;

/// Sentinel index representing "borne off" as a move destination.
const int kOffIndex = 24;

/// Total checkers each side starts with.
const int kCheckersPerPlayer = 15;

/// Number of points on the board.
const int kPointCount = 24;

/// A single point (of 24) on the board.
///
/// A point is either empty ([owner] is null, [count] is 0), or occupied by
/// one player's checkers. Standard backgammon does not allow mixed
/// occupancy, and a point with exactly one checker of a color is a "blot"
/// that can be hit by the opponent.
class Point {
  final PlayerColor? owner;
  final int count;

  const Point({this.owner, this.count = 0});

  bool get isEmpty => count == 0;
  bool get isBlot => count == 1;
  bool get isMade => count >= 2;

  Point copyWith({PlayerColor? owner, int? count}) {
    return Point(owner: owner ?? this.owner, count: count ?? this.count);
  }

  static const Point empty = Point();

  @override
  String toString() => isEmpty ? '_' : '${owner == PlayerColor.white ? 'W' : 'B'}$count';
}

/// Immutable snapshot of the full board state: the 24 points plus each
/// player's bar (hit checkers waiting to re-enter) and off (borne-off
/// checkers) counts.
///
/// Points are indexed 0..23, representing traditional points 1..24.
/// White's home board is points 1-6 (indices 0-5) and white bears off past
/// index 0. Black's home board is points 19-24 (indices 18-23) and black
/// bears off past index 23.
class Board {
  final List<Point> points;
  final Map<PlayerColor, int> bar;
  final Map<PlayerColor, int> off;

  Board({required this.points, required this.bar, required this.off})
      : assert(points.length == kPointCount);

  /// The standard starting position of backgammon / tavla.
  factory Board.initial() {
    final pts = List<Point>.filled(kPointCount, Point.empty, growable: false);

    Point w(int count) => Point(owner: PlayerColor.white, count: count);
    Point b(int count) => Point(owner: PlayerColor.black, count: count);

    final setup = <int, Point>{
      23: w(2), // point 24
      12: w(5), // point 13
      7: w(3), // point 8
      5: w(5), // point 6
      0: b(2), // point 1
      11: b(5), // point 12
      16: b(3), // point 17
      18: b(5), // point 19
    };

    final list = List<Point>.generate(
      kPointCount,
      (i) => setup[i] ?? Point.empty,
      growable: false,
    );

    return Board(
      points: list,
      bar: {PlayerColor.white: 0, PlayerColor.black: 0},
      off: {PlayerColor.white: 0, PlayerColor.black: 0},
    );
  }

  /// An empty board (all points, bar and off at zero). Useful for tests
  /// and custom position setup.
  factory Board.empty() {
    return Board(
      points: List<Point>.filled(kPointCount, Point.empty, growable: false),
      bar: {PlayerColor.white: 0, PlayerColor.black: 0},
      off: {PlayerColor.white: 0, PlayerColor.black: 0},
    );
  }

  int barCount(PlayerColor player) => bar[player] ?? 0;
  int offCount(PlayerColor player) => off[player] ?? 0;

  int checkersOnBoard(PlayerColor player) {
    var total = 0;
    for (final p in points) {
      if (p.owner == player) total += p.count;
    }
    return total;
  }

  /// Total checkers accounted for on the board, bar and off for [player].
  /// Should always equal [kCheckersPerPlayer] for a consistent state.
  int totalCheckers(PlayerColor player) =>
      checkersOnBoard(player) + barCount(player) + offCount(player);

  Board copyWith({
    List<Point>? points,
    Map<PlayerColor, int>? bar,
    Map<PlayerColor, int>? off,
  }) {
    return Board(
      points: points ?? this.points,
      bar: bar ?? Map<PlayerColor, int>.from(this.bar),
      off: off ?? Map<PlayerColor, int>.from(this.off),
    );
  }

  /// Returns a deep copy of this board with point [index] replaced.
  Board withPoint(int index, Point value) {
    final next = List<Point>.of(points);
    next[index] = value;
    return copyWith(points: next);
  }

  /// Returns a deep copy of this board with [player]'s bar count set.
  Board withBar(PlayerColor player, int value) {
    final next = Map<PlayerColor, int>.from(bar);
    next[player] = value;
    return copyWith(bar: next);
  }

  /// Returns a deep copy of this board with [player]'s off count set.
  Board withOff(PlayerColor player, int value) {
    final next = Map<PlayerColor, int>.from(off);
    next[player] = value;
    return copyWith(off: next);
  }

  Board deepCopy() => Board(
        points: List<Point>.of(points),
        bar: Map<PlayerColor, int>.from(bar),
        off: Map<PlayerColor, int>.from(off),
      );

  @override
  String toString() {
    final buf = StringBuffer();
    buf.writeln('Bar: W=${barCount(PlayerColor.white)} B=${barCount(PlayerColor.black)}');
    for (var i = kPointCount - 1; i >= 0; i--) {
      buf.write('${i + 1}:${points[i]} ');
    }
    buf.writeln();
    buf.writeln('Off: W=${offCount(PlayerColor.white)} B=${offCount(PlayerColor.black)}');
    return buf.toString();
  }
}