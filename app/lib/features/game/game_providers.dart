import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/game_state.dart';
import '../../shared/moves.dart';
import '../../shared/player.dart';
import '../bot/bot_ai.dart';

/// Who the local human player is playing against in a given game screen
/// instance.
enum GameMode {
  /// Two humans sharing one device, taking turns.
  localHotseat,

  /// One human versus the tiered bot AI.
  bot,

  /// Realtime multiplayer over the Socket.io backend (handled by the
  /// `online` feature's own controller, not this one).
  online,
}

/// Immutable configuration used to start a fresh local/bot game.
class GameConfig {
  final GameMode mode;
  final PlayerColor humanColor;
  final BotDifficulty botDifficulty;
  final PlayerColor startingPlayer;

  const GameConfig({
    required this.mode,
    this.humanColor = PlayerColor.white,
    this.botDifficulty = BotDifficulty.easy,
    this.startingPlayer = PlayerColor.white,
  });
}

/// Drives a local [GameState] for hotseat or bot play.
///
/// For [GameMode.bot], whenever it becomes the bot's turn this controller
/// automatically rolls for it and plays its moves one at a time (via
/// [BotAi]), with a short delay between steps so the opponent's turn is
/// readable instead of instantaneous. Human-driven turns only change state
/// in response to explicit [rollDice] / [applyMove] calls from the UI.
class GameController extends StateNotifier<GameState> {
  final GameConfig config;
  late final BotAi _bot;
  Timer? _botTimer;
  bool _disposed = false;

  GameController(this.config)
      : super(GameState.newGame(startingPlayer: config.startingPlayer)) {
    _bot = BotAi(difficulty: config.botDifficulty);
    _maybeScheduleBotTurn();
  }

  PlayerColor get _botColor => config.humanColor.opponent;

  bool get isBotTurn =>
      config.mode == GameMode.bot && state.currentPlayer == _botColor && !state.isGameOver;

  /// Rolls the dice for the current player (must be a human-controlled
  /// turn; the bot rolls for itself automatically).
  void rollDice() {
    if (state.phase != GamePhase.awaitingRoll) return;
    state = state.rollDice();
    _maybeScheduleBotTurn();
  }

  /// Applies [move] for the current player (must be a human-controlled
  /// turn; the bot plays for itself automatically).
  void applyMove(Move move) {
    if (state.phase != GamePhase.awaitingMove) return;
    state = state.applyMove(move);
    _maybeScheduleBotTurn();
  }

  /// Starts a brand new game with the same configuration.
  void restart() {
    _botTimer?.cancel();
    state = GameState.newGame(startingPlayer: config.startingPlayer);
    _maybeScheduleBotTurn();
  }

  void _maybeScheduleBotTurn() {
    if (!isBotTurn) return;
    _botTimer?.cancel();
    _botTimer = Timer(const Duration(milliseconds: 550), _playBotStep);
  }

  void _playBotStep() {
    if (_disposed || !isBotTurn) return;

    if (state.phase == GamePhase.awaitingRoll) {
      state = state.rollDice();
      _maybeScheduleBotTurn();
      return;
    }

    if (state.phase == GamePhase.awaitingMove) {
      final move = _bot.chooseMove(state);
      if (move == null) return;
      state = state.applyMove(move);
      _maybeScheduleBotTurn();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _botTimer?.cancel();
    super.dispose();
  }
}

/// Family provider: each distinct [GameConfig] gets its own controller
/// instance. `autoDispose` tears it down (cancelling any pending bot timer)
/// once the game screen using it is popped and no longer watched.
final gameControllerProvider =
    StateNotifierProvider.autoDispose.family<GameController, GameState, GameConfig>(
  (ref, config) => GameController(config),
);