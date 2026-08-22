import 'package:flutter_test/flutter_test.dart';

import 'package:cyber_tavla/shared/board.dart';
import 'package:cyber_tavla/shared/dice.dart';
import 'package:cyber_tavla/shared/game_state.dart';
import 'package:cyber_tavla/shared/moves.dart';
import 'package:cyber_tavla/shared/player.dart';
import 'package:cyber_tavla/shared/rules.dart';

void main() {
  group('Board.initial', () {
    test('sets up the standard starting position', () {
      final board = Board.initial();

      expect(board.points[23].owner, PlayerColor.white);
      expect(board.points[23].count, 2);
      expect(board.points[12].owner, PlayerColor.white);
      expect(board.points[12].count, 5);
      expect(board.points[7].owner, PlayerColor.white);
      expect(board.points[7].count, 3);
      expect(board.points[5].owner, PlayerColor.white);
      expect(board.points[5].count, 5);

      expect(board.points[0].owner, PlayerColor.black);
      expect(board.points[0].count, 2);
      expect(board.points[11].owner, PlayerColor.black);
      expect(board.points[11].count, 5);
      expect(board.points[16].owner, PlayerColor.black);
      expect(board.points[16].count, 3);
      expect(board.points[18].owner, PlayerColor.black);
      expect(board.points[18].count, 5);

      expect(board.totalCheckers(PlayerColor.white), kCheckersPerPlayer);
      expect(board.totalCheckers(PlayerColor.black), kCheckersPerPlayer);
      expect(board.barCount(PlayerColor.white), 0);
      expect(board.barCount(PlayerColor.black), 0);
      expect(board.offCount(PlayerColor.white), 0);
      expect(board.offCount(PlayerColor.black), 0);
    });
  });

  group('TavlaRules.legalMovesForDie', () {
    test('white can move from point 24 (index 23) with a die of 1', () {
      final board = Board.initial();
      final moves = TavlaRules.legalMovesForDie(board, PlayerColor.white, 1);

      expect(
        moves.any((m) => m.from == 23 && m.to == 22 && m.die == 1),
        isTrue,
      );
    });

    test('black cannot land on a point white owns with 2+ checkers', () {
      final board = Board.initial();
      // White owns point 6 (index 5) with 5 checkers, and point 8 (index 7)
      // with 3 checkers - both fully blocked for black.
      final moves = TavlaRules.legalMovesForDie(board, PlayerColor.black, 6);
      expect(moves.any((m) => m.to == 5), isFalse);
    });

    test('a player with checkers on the bar may only enter, not move', () {
      var board = Board.empty();
      board = board.withPoint(23, const Point(owner: PlayerColor.white, count: 1));
      board = board.withBar(PlayerColor.white, 1);

      final moves = TavlaRules.legalMovesForDie(board, PlayerColor.white, 3);

      expect(moves, hasLength(1));
      expect(moves.first.isFromBar, isTrue);
      // White entering with a die of 3 lands on index 24-3=21.
      expect(moves.first.to, 21);
    });

    test('bar entry is blocked if the entry point is made by the opponent', () {
      var board = Board.empty();
      board = board.withBar(PlayerColor.white, 1);
      // Black makes white's die-3 entry point (index 21) with 2 checkers.
      board = board.withPoint(21, const Point(owner: PlayerColor.black, count: 2));

      final moves = TavlaRules.legalMovesForDie(board, PlayerColor.white, 3);
      expect(moves, isEmpty);
    });
  });

  group('TavlaRules.applyMove - hitting', () {
    test('landing on a lone opposing checker sends it to the bar', () {
      var board = Board.empty();
      board = board.withPoint(10, const Point(owner: PlayerColor.white, count: 1));
      board = board.withPoint(8, const Point(owner: PlayerColor.black, count: 1));

      final move = Move(player: PlayerColor.white, from: 10, to: 8, die: 2);
      final result = TavlaRules.applyMove(board, move);

      expect(result.points[8].owner, PlayerColor.white);
      expect(result.points[8].count, 1);
      expect(result.points[10].isEmpty, isTrue);
      expect(result.barCount(PlayerColor.black), 1);
    });

    test('cannot land on a point made (2+) by the opponent', () {
      final board = Board.initial();
      // Black's point 12 (index 11) has 5 checkers - fully blocked.
      final moves = TavlaRules.legalMovesForDie(board, PlayerColor.white, 1);
      expect(moves.any((m) => m.to == 11), isFalse);
    });
  });

  group('Bear-off rules', () {
    test('allCheckersInHome is false while any checker is outside home', () {
      final board = Board.initial();
      expect(TavlaRules.allCheckersInHome(board, PlayerColor.white), isFalse);
    });

    test('white can bear off exactly with a matching die', () {
      var board = Board.empty();
      board = board.withPoint(2, const Point(owner: PlayerColor.white, count: 1));

      expect(TavlaRules.allCheckersInHome(board, PlayerColor.white), isTrue);

      final moves = TavlaRules.legalMovesForDie(board, PlayerColor.white, 3);
      expect(moves.any((m) => m.isBearOff && m.from == 2), isTrue);
    });

    test('an overage die bears off the checker furthest from home', () {
      var board = Board.empty();
      // Furthest white checker from bearing off sits on point 4 (index 3).
      board = board.withPoint(3, const Point(owner: PlayerColor.white, count: 1));
      board = board.withPoint(1, const Point(owner: PlayerColor.white, count: 1));

      final movesForRearChecker = TavlaRules.legalMovesForDie(board, PlayerColor.white, 6);
      expect(movesForRearChecker.any((m) => m.isBearOff && m.from == 3), isTrue);
      // The closer checker (index 1) should not bear off with a 6 while a
      // checker further back (index 3) still exists.
      expect(movesForRearChecker.any((m) => m.isBearOff && m.from == 1), isFalse);
    });

    test('bearing off the last checker wins the game', () {
      var board = Board.empty();
      board = board.withPoint(0, const Point(owner: PlayerColor.white, count: 1));
      board = board.withOff(PlayerColor.white, kCheckersPerPlayer - 1);
      board = board.withOff(PlayerColor.black, 0);

      final move = Move(player: PlayerColor.white, from: 0, to: kOffIndex, die: 1);
      final result = TavlaRules.applyMove(board, move);

      expect(TavlaRules.isGameOver(result), isTrue);
      expect(TavlaRules.winner(result), PlayerColor.white);
    });
  });

  group('GameState turn flow', () {
    test('newGame starts white to roll with an empty history', () {
      final state = GameState.newGame();
      expect(state.currentPlayer, PlayerColor.white);
      expect(state.phase, GamePhase.awaitingRoll);
      expect(state.history, isEmpty);
    });

    test('applyRoll with a fixed roll transitions into the move phase', () {
      final state = GameState.newGame().applyRoll(const DiceRoll(3, 5));
      expect(state.phase, GamePhase.awaitingMove);
      expect(state.remainingDice, containsAll([3, 5]));
    });

    test('applying every die hands the turn to the opponent', () {
      var state = GameState.newGame().applyRoll(const DiceRoll(3, 5));
      final firstMove = state.legalMoves().firstWhere((m) => m.die == 3);
      state = state.applyMove(firstMove);
      final secondMove = state.legalMoves().firstWhere((m) => m.die == 5);
      state = state.applyMove(secondMove);

      expect(state.currentPlayer, PlayerColor.black);
      expect(state.phase, GamePhase.awaitingRoll);
      expect(state.history, hasLength(2));
    });
  });
}