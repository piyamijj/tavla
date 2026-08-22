import 'dart:math';

/// A single dice roll: two six-sided dice, with backgammon's doubles rule
/// (rolling a double grants four moves of that value instead of two).
class DiceRoll {
  final int die1;
  final int die2;

  const DiceRoll(this.die1, this.die2)
      : assert(die1 >= 1 && die1 <= 6),
        assert(die2 >= 1 && die2 <= 6);

  bool get isDouble => die1 == die2;

  /// The playable die values for this roll: two values normally, or the
  /// same value four times when doubles are rolled.
  List<int> get values => isDouble ? [die1, die1, die1, die1] : [die1, die2];

  @override
  String toString() => 'DiceRoll($die1, $die2)';

  @override
  bool operator ==(Object other) =>
      other is DiceRoll && other.die1 == die1 && other.die2 == die2;

  @override
  int get hashCode => Object.hash(die1, die2);

  /// Serializes to a JSON-safe map for the realtime server / socket
  /// protocol (e.g. the server broadcasting an authoritative roll).
  Map<String, dynamic> toJson() => {'die1': die1, 'die2': die2};

  factory DiceRoll.fromJson(Map<String, dynamic> json) =>
      DiceRoll(json['die1'] as int, json['die2'] as int);
}

/// Utility for producing dice rolls. Accepts an injectable [Random] so
/// gameplay and tests can use a seeded, deterministic source when needed.
class Dice {
  const Dice._();

  static DiceRoll roll([Random? random]) {
    final rng = random ?? Random();
    return DiceRoll(rng.nextInt(6) + 1, rng.nextInt(6) + 1);
  }

  /// Rolls a single die face (1-6). Used for the opening roll-off and for
  /// any place a lone die value is needed.
  static int rollSingle([Random? random]) {
    final rng = random ?? Random();
    return rng.nextInt(6) + 1;
  }
}