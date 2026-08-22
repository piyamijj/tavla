import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/bear_off_tray.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/neon_button.dart';
import '../../../shared/board.dart';
import '../../../shared/game_state.dart';
import '../../../shared/moves.dart';
import '../../../shared/player.dart';
import '../../../shared/rules.dart';
import '../board/board_widget.dart';
import '../dice/dice_widget.dart';
import '../game_providers.dart';

/// A single step queued for board animation: the board *before* [move] was
/// applied, and the move itself. The board rendered on screen lags behind
/// the authoritative `GameState` by whatever steps are still queued here,
/// so every move — human or bot — gets a visible flight animation instead
/// of popping directly to its resolved position.
class _QueuedStep {
  final Board fromBoard;
  final Move move;

  const _QueuedStep(this.fromBoard, this.move);
}

/// The main game screen: board, dice, bear-off trays and turn/status
/// chrome, wired to a [GameController] for local hotseat or bot play.
class GameScreen extends ConsumerStatefulWidget {
  final GameConfig config;
  final String subtitle;

  const GameScreen({super.key, required this.config, required this.subtitle});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  int? _selectedPoint;
  bool _selectedIsBar = false;
  PlayerColor _selectedBarPlayer = PlayerColor.white;

  final List<_QueuedStep> _queue = [];
  bool _animating = false;
  int _lastSeenHistoryLen = 0;
  bool _isRollingVisual = false;
  bool _gameOverDialogShown = false;

  GameConfig get _config => widget.config;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameControllerProvider(_config));
    final controller = ref.read(gameControllerProvider(_config).notifier);

    ref.listen<GameState>(gameControllerProvider(_config), (previous, next) {
      if (next.history.length > _lastSeenHistoryLen && previous != null) {
        var boardCursor = previous.board;
        for (var i = _lastSeenHistoryLen; i < next.history.length; i++) {
          final move = next.history[i];
          setState(() => _queue.add(_QueuedStep(boardCursor, move)));
          boardCursor = _applyForPreview(boardCursor, move);
        }
      }
      _lastSeenHistoryLen = next.history.length;

      if (next.currentRoll != null &&
          (previous == null || previous.currentRoll != next.currentRoll)) {
        setState(() => _isRollingVisual = false);
      }

      if (next.phase == GamePhase.awaitingRoll) {
        setState(() {
          _selectedPoint = null;
          _selectedIsBar = false;
        });
      }

      if (next.isGameOver && !_gameOverDialogShown) {
        _gameOverDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showGameOverDialog(next));
      }
    });

    final displayedBoard = _queue.isNotEmpty ? _queue.first.fromBoard : state.board;
    final animatingMove = _queue.isNotEmpty
        ? AnimatingMove(
            move: _queue.first.move,
            token: _queue.first,
            onCompleted: () {
              if (!mounted) return;
              setState(() {
                _queue.removeAt(0);
                _animating = _queue.isNotEmpty;
              });
            },
          )
        : null;

    if (_queue.isNotEmpty && !_animating) {
      _animating = true;
    }

    final isHumanTurn = _isHumanTurn(state);
    final legalMoves = isHumanTurn ? state.legalMoves() : const <Move>[];
    final legalDestinations = _legalDestinationsFor(legalMoves);
    final canBearOffSelected = _selectedPoint != null &&
        !_selectedIsBar &&
        legalMoves.any((m) => m.from == _selectedPoint && m.isBearOff);

    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context, state),
              _buildOpponentRow(state),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: GlowPanel(
                      glowColor: AppColors.neonPurple,
                      padding: const EdgeInsets.all(10),
                      child: BoardWidget(
                        board: displayedBoard,
                        selectedPoint: _selectedPoint,
                        selectedIsBar: _selectedIsBar,
                        selectedBarPlayer: _selectedBarPlayer,
                        legalDestinations: legalDestinations,
                        animatingMove: animatingMove,
                        onBarTap: () => _handleBarTap(state, controller),
                        onPointTap: (index) =>
                            _handlePointTap(index, state, controller, legalMoves),
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomBar(context, state, controller, canBearOffSelected),
            ],
          ),
        ),
      ),
    );
  }

  bool _isHumanTurn(GameState state) {
    if (_config.mode == GameMode.bot) {
      return state.currentPlayer == _config.humanColor;
    }
    return true; // hotseat: both sides are "human"
  }

  Set<int> _legalDestinationsFor(List<Move> legalMoves) {
    if (_selectedIsBar) {
      return legalMoves
          .where((m) => m.isFromBar && m.player == _selectedBarPlayer)
          .map((m) => m.to)
          .where((to) => to != kOffIndex)
          .toSet();
    }
    if (_selectedPoint == null) return {};
    return legalMoves
        .where((m) => m.from == _selectedPoint)
        .map((m) => m.to)
        .where((to) => to != kOffIndex)
        .toSet();
  }

  Board _applyForPreview(Board board, Move move) {
    // Used only to seed the *next* queued step's "before" board on the
    // rare occasion several moves land between two listener callbacks;
    // the authoritative result always comes from the engine itself.
    return TavlaRules.applyMove(board, move);
  }

  void _handleBarTap(GameState state, GameController controller) {
    if (!_isHumanTurn(state) || state.phase != GamePhase.awaitingMove) return;
    final player = state.currentPlayer;
    if (state.board.barCount(player) == 0) return;

    final entryMoves = state.legalMoves().where((m) => m.isFromBar).toList();
    if (entryMoves.isEmpty) return;

    setState(() {
      if (_selectedIsBar) {
        _selectedIsBar = false;
      } else {
        _selectedIsBar = true;
        _selectedPoint = null;
        _selectedBarPlayer = player;
      }
    });
  }

  void _handlePointTap(
    int index,
    GameState state,
    GameController controller,
    List<Move> legalMoves,
  ) {
    if (!_isHumanTurn(state) || state.phase != GamePhase.awaitingMove) return;

    final player = state.currentPlayer;

    if (state.board.barCount(player) > 0) {
      final hasBarMoves = legalMoves.any((m) => m.isFromBar);
      if (hasBarMoves) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.mustEnterFromBar)),
        );
        return;
      }
    }

    if (_selectedIsBar) {
      final match = legalMoves.firstWhere(
        (m) => m.isFromBar && m.to == index,
        orElse: () => const Move(player: PlayerColor.white, from: -99, to: -99, die: 0),
      );
      if (match.from == kBarIndex) {
        _commitMove(match, controller);
      } else {
        setState(() => _selectedIsBar = false);
      }
      return;
    }

    if (_selectedPoint == null) {
      final point = state.board.points[index];
      if (point.owner == player && legalMoves.any((m) => m.from == index)) {
        setState(() => _selectedPoint = index);
      }
      return;
    }

    if (_selectedPoint == index) {
      setState(() => _selectedPoint = null);
      return;
    }

    final match = legalMoves.firstWhere(
      (m) => m.from == _selectedPoint && m.to == index,
      orElse: () => const Move(player: PlayerColor.white, from: -99, to: -99, die: 0),
    );

    if (match.from == _selectedPoint) {
      _commitMove(match, controller);
      return;
    }

    final point = state.board.points[index];
    if (point.owner == player && legalMoves.any((m) => m.from == index)) {
      setState(() => _selectedPoint = index);
    } else {
      setState(() => _selectedPoint = null);
    }
  }

  void _handleBearOffTap(GameState state, GameController controller, List<Move> legalMoves) {
    if (_selectedPoint == null) return;
    final match = legalMoves.firstWhere(
      (m) => m.from == _selectedPoint && m.isBearOff,
      orElse: () => const Move(player: PlayerColor.white, from: -99, to: -99, die: 0),
    );
    if (match.from == _selectedPoint) {
      _commitMove(match, controller);
    }
  }

  void _commitMove(Move move, GameController controller) {
    setState(() {
      _selectedPoint = null;
      _selectedIsBar = false;
    });
    controller.applyMove(move);
  }

  void _rollDice(GameController controller) {
    setState(() => _isRollingVisual = true);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      controller.rollDice();
    });
  }

  Widget _buildTopBar(BuildContext context, GameState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _confirmForfeit(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  AppStrings.appName.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    fontSize: 15,
                  ),
                ),
                Text(
                  widget.subtitle,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmForfeit(context),
            icon: const Icon(Icons.flag_rounded, color: AppColors.neonRed),
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentRow(GameState state) {
    final opponent = _config.mode == GameMode.bot ? _config.humanColor.opponent : null;
    final isOpponentTurn = opponent != null && state.currentPlayer == opponent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          BearOffTray(
            owner: PlayerColor.black,
            count: state.board.offCount(PlayerColor.black),
          ),
          if (isOpponentTurn)
            const GlowBadge(
              text: AppStrings.opponentTurn,
              color: AppColors.playerBlack,
              icon: Icons.smart_toy_rounded,
            ),
          _BarCountChip(player: PlayerColor.black, board: state.board),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    GameState state,
    GameController controller,
    bool canBearOffSelected,
  ) {
    final legalMoves = _isHumanTurn(state) ? state.legalMoves() : const <Move>[];
    final isHumanTurn = _isHumanTurn(state);
    final myTurnBadgeColor =
        state.currentPlayer == PlayerColor.white ? AppColors.playerWhite : AppColors.playerBlack;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BearOffTray(
                owner: PlayerColor.white,
                count: state.board.offCount(PlayerColor.white),
                active: canBearOffSelected,
                onTap: () => _handleBearOffTap(state, controller, legalMoves),
              ),
              GlowBadge(
                text: isHumanTurn ? AppStrings.yourTurn : AppStrings.opponentTurn,
                color: myTurnBadgeColor,
                icon: Icons.bolt_rounded,
              ),
              _BarCountChip(player: PlayerColor.white, board: state.board),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DiceTray(
                values: state.currentRoll?.values ?? const [],
                remainingDice: state.remainingDice,
                isRolling: _isRollingVisual,
                glowColor: myTurnBadgeColor,
              ),
              const SizedBox(width: 20),
              if (state.phase == GamePhase.awaitingRoll && isHumanTurn)
                SizedBox(
                  width: 140,
                  height: 48,
                  child: NeonButton(
                    label: AppStrings.rollDice,
                    color: myTurnBadgeColor,
                    icon: Icons.casino_rounded,
                    onPressed: () => _rollDice(controller),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmForfeit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.confirmForfeitTitle),
        content: const Text(AppStrings.confirmForfeitMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text(AppStrings.forfeit, style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog(GameState state) {
    final winner = state.winner;
    final humanWon = _config.mode != GameMode.bot || winner == _config.humanColor;
    final title = humanWon ? AppStrings.youWin : AppStrings.youLose;
    final color = humanWon ? AppColors.neonGreen : AppColors.neonRed;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        content: Text(
          winner == PlayerColor.white
              ? '${AppStrings.colorWhite} kazandı.'
              : '${AppStrings.colorBlack} kazandı.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text(AppStrings.returnToMenu),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _queue.clear();
                _animating = false;
                _lastSeenHistoryLen = 0;
                _gameOverDialogShown = false;
                _selectedPoint = null;
                _selectedIsBar = false;
              });
              ref.read(gameControllerProvider(_config).notifier).restart();
            },
            child: const Text(AppStrings.playAgain),
          ),
        ],
      ),
    );
  }
}

class _BarCountChip extends StatelessWidget {
  final PlayerColor player;
  final Board board;

  const _BarCountChip({required this.player, required this.board});

  @override
  Widget build(BuildContext context) {
    final count = board.barCount(player);
    if (count == 0) return const SizedBox(width: 64);
    final color = player == PlayerColor.white ? AppColors.playerWhite : AppColors.playerBlack;
    return GlowBadge(text: '${AppStrings.barLabel}: $count', color: color, icon: Icons.pause_circle_filled_rounded);
  }
}
