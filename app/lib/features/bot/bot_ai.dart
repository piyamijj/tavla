import 'dart:math';

import '../../shared/board.dart';
import '../../shared/game_state.dart';
import '../../shared/moves.dart';
import '../../shared/player.dart';
import '../../shared/rules.dart';

/// Difficulty tiers for the single-player bot opponent.
///
/// - [easy]: picks uniformly at random among legal moves. No board
///   awareness at all.
/// - [medium]: scores every legal move by simulating it and evaluating the
///   resulting board with [BotHeuristics.evaluate] (pip count, blot
///   exposure, made points, bear-off progress), then plays the
///   highest-scoring move.
/// - [hard]: same heuristic, but adds a shallow (1-ply) look-ahead that
///   estimates the opponent's best reply to each candidate move before
///   scoring it — a cheap approximation of minimax's "assume the opponent
///   plays well" idea without the cost of a full recursive search.
///
/// A true minimax / expectiminimax search (recursing through dice
/// probabilities several plies deep) is intentionally left as future work
/// per the project plan; [hard] is a stronger heuristic, not a solver.
enum BotDifficulty { easy, medium, hard }

/// Tiered bot AI: given the current [GameState] (whose turn it is doesn't
/// matter to this class — callers only invoke it when it's the bot's turn),
/// chooses which single-die move to play next.
///
/// The bot plays one die at a time, exactly like a human would: the caller
/// should call [chooseMove] repeatedly (applying each returned move via
/// `GameState.applyMove`) until the engine itself advances the turn
/// (`GameState.currentPlayer` changes), since remaining dice and legal
/// moves are recomputed fresh from the updated state each time.
class BotAi {
  final BotDifficulty difficulty;
  final Random _random;

  BotAi({required this.difficulty, Random? random}) : _random = random ?? Random();

  /// Chooses the next move to play for [state.currentPlayer], given the
  /// legal moves derived from [state.legalMoves()]. Returns `null` if there
  /// are no legal moves (caller should not normally hit this, since
  /// `GameState` auto-advances the turn when a player is stuck).
  Move? chooseMove(GameState state) {
    final legal = state.legalMoves();
    if (legal.isEmpty) return null;
    if (legal.length == 1) return legal.first;

    switch (difficulty) {
      case BotDifficulty.easy:
        return _chooseRandom(legal);
      case BotDifficulty.medium:
        return _chooseHeuristic(state, legal, withOpponentLookahead: false);
      case BotDifficulty.hard:
        return _chooseHeuristic(state, legal, withOpponentLookahead: true);
    }
  }

  Move _chooseRandom(List<Move> legal) {
    return legal[_random.nextInt(legal.length)];
  }

  Move _chooseHeuristic(
    GameState state,
    List<Move> legal, {
    required bool withOpponentLookahead,
  }) {
    final bot = state.currentPlayer;
    final opponent = bot.opponent;

    // Bearing off is (almost) always at least as good as any alternative
    // once it's available: it can never be hit and it strictly progresses
    // toward winning. Prioritize it outright rather than risk a close
    // heuristic score picking something else.
    final bearOffMoves = legal.where((m) => m.isBearOff).toList();
    final candidates = bearOffMoves.isNotEmpty ? bearOffMoves : legal;

    Move? best;
    double bestScore = double.negativeInfinity;

    for (final move in candidates) {
      final resultingBoard = TavlaRules.applyMove(state.board, move);
      var score = BotHeuristics.evaluate(resultingBoard, bot);

      if (withOpponentLookahead) {
        score -= _bestOpponentReplyValue(resultingBoard, opponent, bot) * 0.5;
      }

      // Small deterministic jitter so ties don't always resolve to
      // whichever move happened to be generated first (keeps the bot from
      // looking robotic across repeated similar positions), without
      // meaningfully overriding real score differences.
      score += _random.nextDouble() * 0.01;

      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
    }

    return best ?? candidates.first;
  }

  /// Rough 1-ply estimate of how much the opponent's *best available reply*
  /// would swing the evaluation in their favor, averaged over the 21
  /// distinct dice-roll outcomes. This is deliberately cheap: it only
  /// considers the opponent's first die of each roll (not full two-die
  /// combinations), which is enough to notice "did I leave a juicy blot"
  /// without the cost of a full expectiminimax ply.
  double _bestOpponentReplyValue(Board board, PlayerColor opponent, PlayerColor bot) {
    double total = 0;
    var samples = 0;

    for (var die = 1; die <= 6; die++) {
      final replies = TavlaRules.legalMovesForDie(board, opponent, die);
      if (replies.isEmpty) continue;

      double bestReply = double.negativeInfinity;
      for (final reply in replies) {
        final afterReply = TavlaRules.applyMove(board, reply);
        final value = BotHeuristics.evaluate(afterReply, opponent);
        if (value > bestReply) bestReply = value;
      }
      total += bestReply;
      samples++;
    }

    if (samples == 0) return 0;
    return total / samples;
  }
}

/// Board evaluation heuristic shared by the medium/hard bot tiers.
///
/// Scores a board from [player]'s point of view: higher is better for
/// [player]. Combines pip count (race progress), borne-off / bar counts,
/// blot exposure (chance a lone checker gets hit) and made points (safe,
/// two-or-more-checker stacks) into a single scalar. This is a hand-tuned
/// heuristic, not a solved equity table — good enough to give the medium
/// and hard bots sensible, human-legible priorities (don't leave blots,
/// make points, race home) without the cost of a full search.
class BotHeuristics {
  const BotHeuristics._();

  /// Approximate probability (out of 36 dice-roll combinations) that a
  /// blot sitting exactly [distance] pips ahead of a single opposing
  /// checker gets hit this turn. Covers direct shots (1-6) and the most
  /// common indirect combo shots (7-12); rarer double-only combo shots
  /// beyond 12 pips are treated as zero, a reasonable heuristic-level
  /// simplification.
  static const Map<int, double> _hitChanceByDistance = {
    1: 11 / 36,
    2: 12 / 36,
    3: 14 / 36,
    4: 15 / 36,
    5: 15 / 36,
    6: 17 / 36,
    7: 6 / 36,
    8: 6 / 36,
    9: 5 / 36,
    10: 3 / 36,
    11: 2 / 36,
    12: 3 / 36,
  };

  static int _pipDistanceToOff(PlayerColor player, int index) {
    return player == PlayerColor.white ? index + 1 : (kPointCount - index);
  }

  /// Total pips [player] must travel to bear off every checker (lower is
  /// better — this is a race, not a score to maximize).
  static int pipCount(Board board, PlayerColor player) {
    var pips = 0;
    for (var i = 0; i < kPointCount; i++) {
      final point = board.points[i];
      if (point.owner == player) {
        pips += point.count * _pipDistanceToOff(player, i);
      }
    }
    // A checker on the bar is treated as needing a full traverse (25 pips),
    // the standard backgammon convention.
    pips += board.barCount(player) * 25;
    return pips;
  }

  /// Sum of hit-chance-weighted exposure across every blot [player] has on
  /// the board, considering every opposing checker that could reach it.
  /// Multiple potential shooters at the same blot are summed (capped at a
  /// near-certain 0.95) rather than combined with proper joint probability
  /// — a deliberate, cheap approximation.
  static double blotExposure(Board board, PlayerColor player) {
    final opponent = player.opponent;
    double exposure = 0;

    for (var i = 0; i < kPointCount; i++) {
      final point = board.points[i];
      if (point.owner != player || !point.isBlot) continue;

      double blotChance = 0;
      for (var j = 0; j < kPointCount; j++) {
        final shooterPoint = board.points[j];
        if (shooterPoint.owner != opponent || shooterPoint.count == 0) continue;

        final delta = (i - j) * opponent.direction;
        if (delta <= 0) continue; // not moving toward the blot

        final chance = _hitChanceByDistance[delta];
        if (chance != null) blotChance += chance;
      }

      // A checker on the bar re-entering directly onto the blot's entry
      // point is an additional, common source of exposure — approximate
      // it as a flat direct-entry chance when the blot sits in the
      // opponent's entry range (the player's own home board).
      if (board.barCount(opponent) > 0) {
        final homeIndices = player == PlayerColor.white
            ? const [0, 1, 2, 3, 4, 5]
            : const [18, 19, 20, 21, 22, 23];
        if (homeIndices.contains(i)) {
          blotChance += 11 / 36;
        }
      }

      exposure += blotChance.clamp(0.0, 0.95);
    }

    return exposure;
  }

  /// Number of points [player] has "made" (2+ checkers) — safe, stable
  /// structure that also denies the opponent a landing spot. Home-board
  /// points are weighted slightly higher since they matter most for both
  /// containing an opponent on the bar and for a smooth bear-off later.
  static double madePointsScore(Board board, PlayerColor player) {
    final homeIndices = player == PlayerColor.white
        ? const [0, 1, 2, 3, 4, 5]
        : const [18, 19, 20, 21, 22, 23];

    double score = 0;
    for (var i = 0; i < kPointCount; i++) {
      final point = board.points[i];
      if (point.owner == player && point.isMade) {
        score += homeIndices.contains(i) ? 1.5 : 1.0;
      }
    }
    return score;
  }

  /// Combines all signals into a single scalar score from [player]'s
  /// perspective. Higher is always better for [player].
  static double evaluate(Board board, PlayerColor player) {
    final opponent = player.opponent;

    if (TavlaRules.isGameOver(board)) {
      final winner = TavlaRules.winner(board);
      return winner == player ? 100000 : -100000;
    }

    final pipDiff = pipCount(board, opponent) - pipCount(board, player);

    var score = 0.0;
    score += pipDiff * 1.0;
    score += board.offCount(player) * 9.0;
    score -= board.offCount(opponent) * 9.0;
    score -= board.barCount(player) * 14.0;
    score += board.barCount(opponent) * 12.0;
    score -= blotExposure(board, player) * 10.0;
    score += blotExposure(board, opponent) * 4.0;
    score += madePointsScore(board, player) * 2.0;
    score -= madePointsScore(board, opponent) * 1.0;

    return score;
  }
}