import 'board.dart';
import 'moves.dart';
import 'player.dart';

/// Core rules engine for Cyber Tavla (backgammon): home-board definitions,
/// bar re-entry, legal single-die move generation, bear-off eligibility,
/// move application (including hits) and win detection.
///
/// This engine operates one die at a time: given a board state and a single
/// die value, it produces the set of legal [Move]s for that die. The caller
/// (game_state.dart) is responsible for walking through the dice in a turn,
/// applying moves one by one and re-generating legal moves for the
/// remaining dice against the updated board after each move. This keeps the
/// engine simple and correct move-by-move; it does not attempt the advanced
/// "maximize total dice usage across orderings" optimization some strict
/// backgammon rulesets require — a reasonable simplification for this
/// project (see README for notes on future refinement).
class TavlaRules {
  const TavlaRules._();

  /// White's home board: points 1-6 (indices 0-5).
  static const List<int> homeIndicesWhite = [0, 1, 2, 3, 4, 5];

  /// Black's home board: points 19-24 (indices 18-23).
  static const List<int> homeIndicesBlack = [18, 19, 20, 21, 22, 23];

  static List<int> homeIndicesFor(PlayerColor player) =>
      player == PlayerColor.white ? homeIndicesWhite : homeIndicesBlack;

  /// The point index a checker enters the board on when coming off the bar,
  /// for a given die value (1-6).
  ///
  /// White enters into black's home board (points 24 down to 19, i.e.
  /// indices 23 down to 18): a die of 1 enters at index 23, a die of 6 at
  /// index 18. Black enters into white's home board (points 1 up to 6,
  /// indices 0 up to 5): a die of 1 enters at index 0, a die of 6 at index 5.
  static int entryIndexFor(PlayerColor player, int die) {
    assert(die >= 1 && die <= 6);
    return player == PlayerColor.white ? (24 - die) : (die - 1);
  }

  /// Whether [player] can legally occupy point [index] (empty, own
  /// checkers, or a single opposing blot to hit). Does not check range.
  static bool _canOccupy(Board board, PlayerColor player, int index) {
    final point = board.points[index];
    if (point.isEmpty) return true;
    if (point.owner == player) return true;
    // Opposing point: can only land on a blot (exactly one checker).
    return point.isBlot;
  }

  static bool _inRange(int index) => index >= 0 && index < kPointCount;

  /// Whether every one of [player]'s checkers still on the board sits in
  /// their home board (a prerequisite for bearing off). Checkers on the bar
  /// disqualify bearing off entirely.
  static bool allCheckersInHome(Board board, PlayerColor player) {
    if (board.barCount(player) > 0) return false;
    final home = homeIndicesFor(player).toSet();
    for (var i = 0; i < kPointCount; i++) {
      final point = board.points[i];
      if (point.owner == player && point.count > 0 && !home.contains(i)) {
        return false;
      }
    }
    return true;
  }

  /// The distance-to-bear-off-edge for a given point index and player,
  /// i.e. the die value that would bear this checker off exactly.
  /// White's edge is just past index 0 (point 1); black's edge is just
  /// past index 23 (point 24).
  static int _exactDieFor(PlayerColor player, int index) {
    return player == PlayerColor.white ? (index + 1) : (kPointCount - index);
  }

  /// Whether, among [player]'s home-board checkers, [index] holds the
  /// checker furthest from bearing off (i.e. no checker sits on a higher
  /// exact-die point). Used for the "overage" bear-off rule: a die larger
  /// than needed may bear off the rearmost checker if no exact match exists.
  static bool _isFurthestFromOff(Board board, PlayerColor player, int index) {
    final home = homeIndicesFor(player);
    for (final i in home) {
      final point = board.points[i];
      if (point.owner != player || point.count == 0) continue;
      if (player == PlayerColor.white && i > index) return false;
      if (player == PlayerColor.black && i < index) return false;
    }
    return true;
  }

  /// Generates all legal moves for [player] using a single [die] value,
  /// given the current [board] state.
  ///
  /// If the player has checkers on the bar, only bar-entry moves are
  /// returned (entry must happen before any other move). Otherwise this
  /// returns ordinary point-to-point moves and, once all of the player's
  /// checkers are in their home board, legal bear-off moves.
  static List<Move> legalMovesForDie(
    Board board,
    PlayerColor player,
    int die,
  ) {
    final moves = <Move>[];

    if (board.barCount(player) > 0) {
      final entry = entryIndexFor(player, die);
      if (_canOccupy(board, player, entry)) {
        moves.add(Move(
          player: player,
          from: kBarIndex,
          to: entry,
          die: die,
          isHit: board.points[entry].isBlot &&
              board.points[entry].owner == player.opponent,
        ));
      }
      return moves;
    }

    final canBearOff = allCheckersInHome(board, player);

    for (var i = 0; i < kPointCount; i++) {
      final point = board.points[i];
      if (point.owner != player || point.count == 0) continue;

      final target = i + player.direction * die;

      if (_inRange(target)) {
        if (_canOccupy(board, player, target)) {
          moves.add(Move(
            player: player,
            from: i,
            to: target,
            die: die,
            isHit: board.points[target].isBlot &&
                board.points[target].owner == player.opponent,
          ));
        }
        continue;
      }

      // Target falls outside the board: only legal as a bear-off, and only
      // once all of this player's checkers are home.
      if (!canBearOff) continue;

      final exactDie = _exactDieFor(player, i);
      if (die == exactDie) {
        moves.add(Move(player: player, from: i, to: kOffIndex, die: die));
      } else if (die > exactDie && _isFurthestFromOff(board, player, i)) {
        // Overage rule: a die larger than needed bears off the checker
        // furthest from home when no checker needs that exact number.
        moves.add(Move(player: player, from: i, to: kOffIndex, die: die));
      }
    }

    return moves;
  }

  /// Generates the union of legal moves across each distinct value in
  /// [dice] (duplicates from a double are naturally deduplicated by value).
  /// Convenience for UI layers that want "what can I play right now" across
  /// all remaining dice at once.
  static List<Move> legalMovesForDiceSet(
    Board board,
    PlayerColor player,
    List<int> dice,
  ) {
    final seenDieValues = <int>{};
    final result = <Move>[];
    for (final die in dice) {
      if (!seenDieValues.add(die)) continue;
      result.addAll(legalMovesForDie(board, player, die));
    }
    return result;
  }

  /// Applies [move] to [board] and returns the resulting board. Handles
  /// bar entry, ordinary movement, hits (sending a lone opposing checker to
  /// the bar) and bearing off. Does not validate legality — callers should
  /// only apply moves obtained from [legalMovesForDie].
  static Board applyMove(Board board, Move move) {
    var next = board.deepCopy();
    final player = move.player;
    final opponent = player.opponent;

    // Remove the checker from its origin.
    if (move.isFromBar) {
      next = next.withBar(player, next.barCount(player) - 1);
    } else {
      final origin = next.points[move.from];
      next = next.withPoint(
        move.from,
        origin.count > 1
            ? origin.copyWith(count: origin.count - 1)
            : const Point(),
      );
    }

    // Place the checker at its destination.
    if (move.isBearOff) {
      next = next.withOff(player, next.offCount(player) + 1);
    } else {
      final dest = next.points[move.to];
      if (dest.owner == opponent && dest.isBlot) {
        // Hit: the lone opposing checker goes to the bar.
        next = next.withBar(opponent, next.barCount(opponent) + 1);
        next = next.withPoint(move.to, Point(owner: player, count: 1));
      } else {
        next = next.withPoint(
          move.to,
          Point(owner: player, count: dest.owner == player ? dest.count + 1 : 1),
        );
      }
    }

    return next;
  }

  static bool isGameOver(Board board) =>
      board.offCount(PlayerColor.white) == kCheckersPerPlayer ||
      board.offCount(PlayerColor.black) == kCheckersPerPlayer;

  static PlayerColor? winner(Board board) {
    if (board.offCount(PlayerColor.white) == kCheckersPerPlayer) {
      return PlayerColor.white;
    }
    if (board.offCount(PlayerColor.black) == kCheckersPerPlayer) {
      return PlayerColor.black;
    }
    return null;
  }

  /// Whether the losing side has borne off zero checkers and still has a
  /// checker on the bar or in the winner's home board — a "backgammon"
  /// (triple loss) in standard scoring. Provided for future scoring/UI use.
  static bool isBackgammonLoss(Board board, PlayerColor loser) {
    if (board.offCount(loser) != 0) return false;
    if (board.barCount(loser) > 0) return true;
    final winnerHome = homeIndicesFor(loser.opponent).toSet();
    for (final i in winnerHome) {
      final point = board.points[i];
      if (point.owner == loser && point.count > 0) return true;
    }
    return false;
  }

  /// Whether the losing side has borne off zero checkers (a "gammon",
  /// double loss) but does not meet the backgammon condition above.
  static bool isGammonLoss(Board board, PlayerColor loser) {
    return board.offCount(loser) == 0 && !isBackgammonLoss(board, loser);
  }
}