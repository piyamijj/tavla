import 'dart:math';

import 'board.dart';
import 'dice.dart';
import 'moves.dart';
import 'player.dart';
import 'rules.dart';

/// Coarse-grained phase of a game turn, useful for driving UI state
/// (enabling/disabling the dice cup, showing "your turn" banners, etc).
enum GamePhase {
  /// Waiting for the current player to roll the dice.
  awaitingRoll,

  /// Dice have been rolled and the current player still has playable dice
  /// and/or legal moves remaining.
  awaitingMove,

  /// The current player has no legal moves left for this turn (either all
  /// dice were used, or none of the remaining dice can be played) — the
  /// engine will hand the turn to the opponent.
  turnOver,

  /// One player has borne off all 15 checkers; the match is decided.
  gameOver,
}

/// Immutable snapshot of a full game in progress: board position, whose
/// turn it is, the dice rolled this turn and which of those dice remain
/// unplayed, plus the current [GamePhase] and winner (if decided).
///
/// This class is the single source of truth the Flutter layer (via
/// Riverpod) and the bot AI both read from and derive new states from —
/// every mutator returns a new [GameState] rather than mutating in place,
/// so it plays nicely with Riverpod's state notifiers and is trivial to
/// reason about, replay or undo.
class GameState {
  final Board board;
  final PlayerColor currentPlayer;
  final DiceRoll? currentRoll;

  /// Die values from [currentRoll] that have not yet been used to make a
  /// move this turn. Empty before a roll, and drained one value at a time
  /// as moves are applied.
  final List<int> remainingDice;

  final GamePhase phase;
  final PlayerColor? winner;

  /// Running log of moves played so far this match, oldest first. Useful
  /// for a move-history panel, undo tooling, or replay/debugging.
  final List<Move> history;

  const GameState({
    required this.board,
    required this.currentPlayer,
    required this.currentRoll,
    required this.remainingDice,
    required this.phase,
    required this.winner,
    required this.history,
  });

  /// A brand-new match: standard starting position, white to roll first,
  /// no dice rolled yet.
  factory GameState.newGame({PlayerColor startingPlayer = PlayerColor.white}) {
    return GameState(
      board: Board.initial(),
      currentPlayer: startingPlayer,
      currentRoll: null,
      remainingDice: const [],
      phase: GamePhase.awaitingRoll,
      winner: null,
      history: const [],
    );
  }

  GameState copyWith({
    Board? board,
    PlayerColor? currentPlayer,
    DiceRoll? currentRoll,
    bool clearRoll = false,
    List<int>? remainingDice,
    GamePhase? phase,
    PlayerColor? winner,
    List<Move>? history,
  }) {
    return GameState(
      board: board ?? this.board,
      currentPlayer: currentPlayer ?? this.currentPlayer,
      currentRoll: clearRoll ? null : (currentRoll ?? this.currentRoll),
      remainingDice: remainingDice ?? this.remainingDice,
      phase: phase ?? this.phase,
      winner: winner ?? this.winner,
      history: history ?? this.history,
    );
  }

  /// Legal moves for the current player given whichever dice remain
  /// unplayed this turn. Empty when it isn't time to move (no roll yet,
  /// game already over) or when the player is stuck with no legal play.
  List<Move> legalMoves() {
    if (phase != GamePhase.awaitingMove || remainingDice.isEmpty) {
      return const [];
    }
    return TavlaRules.legalMovesForDiceSet(board, currentPlayer, remainingDice);
  }

  bool get isGameOver => phase == GamePhase.gameOver;

  /// Rolls the dice for [currentPlayer] and transitions into the move
  /// phase. If the player turns out to have no legal moves at all with
  /// this roll, the turn is immediately handed to the opponent (a "dance").
  GameState rollDice([Random? random]) {
    return applyRoll(Dice.roll(random));
  }

  /// Applies an already-determined [roll] (e.g. one received from the
  /// realtime server, or a locally-generated one) and transitions into the
  /// move phase. Used by online play so both peers apply the exact same
  /// authoritative roll instead of each generating their own.
  GameState applyRoll(DiceRoll roll) {
    assert(phase == GamePhase.awaitingRoll, 'Dice already rolled this turn');
    var next = copyWith(
      currentRoll: roll,
      remainingDice: roll.values,
      phase: GamePhase.awaitingMove,
    );

    if (next.legalMoves().isEmpty) {
      next = next._advanceTurn();
    }

    return next;
  }

  /// Applies [move] — which must be a legal move for one of the current
  /// player's [remainingDice] — updating the board, consuming that die,
  /// and appending to [history]. Detects a win, or hands the turn to the
  /// opponent when no dice/legal moves remain.
  GameState applyMove(Move move) {
    assert(phase == GamePhase.awaitingMove, 'Not in a movable phase');
    assert(move.player == currentPlayer, 'Move belongs to the other player');

    final newBoard = TavlaRules.applyMove(board, move);
    final newHistory = List<Move>.of(history)..add(move);

    final usedDiceIndex = remainingDice.indexOf(move.die);
    final newRemaining = List<int>.of(remainingDice);
    if (usedDiceIndex != -1) newRemaining.removeAt(usedDiceIndex);

    var next = copyWith(
      board: newBoard,
      remainingDice: newRemaining,
      history: newHistory,
    );

    if (TavlaRules.isGameOver(newBoard)) {
      return next.copyWith(
        phase: GamePhase.gameOver,
        winner: TavlaRules.winner(newBoard),
        clearRoll: true,
        remainingDice: const [],
      );
    }

    if (newRemaining.isEmpty || next.legalMoves().isEmpty) {
      return next._advanceTurn();
    }

    return next;
  }

  /// Hands the turn to the opponent and resets to the roll-awaiting phase.
  GameState _advanceTurn() {
    return copyWith(
      currentPlayer: currentPlayer.opponent,
      clearRoll: true,
      remainingDice: const [],
      phase: GamePhase.awaitingRoll,
    );
  }

  /// True when the current player has an active roll but literally cannot
  /// play any of the remaining dice — useful for UI to show a "no moves,
  /// passing turn" message right before the automatic pass happens.
  bool get isStuck =>
      phase == GamePhase.awaitingMove &&
      remainingDice.isNotEmpty &&
      legalMoves().isEmpty;
}