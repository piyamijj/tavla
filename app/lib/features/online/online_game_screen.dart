import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/bear_off_tray.dart';
import '../../core/widgets/glow_panel.dart';
import '../../core/widgets/neon_button.dart';
import '../../shared/board.dart';
import '../../shared/game_state.dart';
import '../../shared/moves.dart';
import '../../shared/player.dart';
import '../../shared/rules.dart';
import '../game/board/board_widget.dart';
import '../game/dice/dice_widget.dart';
import 'online_providers.dart';

/// A single step queued for board animation: the board *before* [move] was
/// applied, and the move itself. Mirrors the same lag-queue technique used
/// by the local `GameScreen` so every move — ours or the opponent's — gets
/// a visible flight animation instead of popping directly into place.
class _QueuedStep {
  final Board fromBoard;
  final Move move;

  const _QueuedStep(this.fromBoard, this.move);
}

/// Online multiplayer game screen: same board/dice/bear-off UI as local
/// play, driven by [OnlineGameController] instead of the local
/// [GameController]. Adds connection-status banners (opponent
/// disconnected/reconnected) and a rematch handshake at game end.
class OnlineGameScreen extends ConsumerStatefulWidget {
  final OnlineConfig config;

  const OnlineGameScreen({super.key, required this.config});

  @override
  ConsumerState<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends ConsumerState<OnlineGameScreen> {
  int? _selectedPoint;
  bool _selectedIsBar = false;
  PlayerColor _selectedBarPlayer = PlayerColor.white;

  final List<_QueuedStep> _queue = [];
  bool _animating = false;
  int _lastSeenHistoryLen = 0;
  bool _gameOverDialogShown = false;

  OnlineConfig get _config => widget.config;

  @override
  Widget build(BuildContext context) {
    final onlineState = ref.watch(onlineGameControllerProvider(_config));
    final controller = ref.read(onlineGameControllerProvider(_config).notifier);
    final state = onlineState.game;

    ref.listen<OnlineState>(onlineGameControllerProvider(_config), (previous, next) {
      final prevGame = previous?.game;
      final nextGame = next.game;

      if (nextGame != null) {
        final prevHistoryLen = prevGame?.history.length ?? 0;
        if (nextGame.history.length > prevHistoryLen && prevGame != null) {
          var boardCursor = prevGame.board;
          for (var i = prevHistoryLen; i < nextGame.history.length; i++) {
            final move = nextGame.history[i];
            setState(() => _queue.add(_QueuedStep(boardCursor, move)));
            boardCursor = TavlaRules.applyMove(boardCursor, move);
          }
        }
        _lastSeenHistoryLen = nextGame.history.length;

        if (nextGame.phase == GamePhase.awaitingRoll) {
          setState(() {
            _selectedPoint = null;
            _selectedIsBar = false;
          });
        }

        if (nextGame.isGameOver && !_gameOverDialogShown) {
          _gameOverDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showGameOverDialog(next, controller));
        }

        // A rematch was just confirmed (previous match was over, this one
        // fresh isn't): close any lingering game-over dialog.
        if (_gameOverDialogShown &&
            prevGame != null &&
            prevGame.isGameOver &&
            !nextGame.isGameOver) {
          _gameOverDialogShown = false;
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        }
      }

      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    if (state == null) {
      return Scaffold(
        body: CyberBackground(
          child: SafeArea(
            child: Center(
              child: GlowPanel(
                glowColor: AppColors.neonCyan,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.neonCyan),
                    SizedBox(height: 14),
                    Text(AppStrings.loading, style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

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

    final myColor = onlineState.myColor;
    final isMyTurn = myColor != null && state.currentPlayer == myColor && onlineState.opponentConnected;
    final legalMoves = isMyTurn ? state.legalMoves() : const <Move>[];
    final legalDestinations = _legalDestinationsFor(legalMoves);
    final canBearOffSelected = _selectedPoint != null &&
        !_selectedIsBar &&
        legalMoves.any((m) => m.from == _selectedPoint && m.isBearOff);

    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context, onlineState, controller),
              if (!onlineState.opponentConnected) _buildDisconnectedBanner(),
              _buildOpponentRow(state, onlineState),
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
                        onBarTap: () => _handleBarTap(state, controller, isMyTurn, myColor),
                        onPointTap: (index) =>
                            _handlePointTap(index, state, controller, legalMoves, isMyTurn, myColor),
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomBar(context, state, onlineState, controller, isMyTurn, canBearOffSelected),
            ],
          ),
        ),
      ),
    );
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

  void _handleBarTap(
    GameState state,
    OnlineGameController controller,
    bool isMyTurn,
    PlayerColor? myColor,
  ) {
    if (!isMyTurn || myColor == null || state.phase != GamePhase.awaitingMove) return;
    if (state.board.barCount(myColor) == 0) return;

    final entryMoves = state.legalMoves().where((m) => m.isFromBar).toList();
    if (entryMoves.isEmpty) return;

    setState(() {
      if (_selectedIsBar) {
        _selectedIsBar = false;
      } else {
        _selectedIsBar = true;
        _selectedPoint = null;
        _selectedBarPlayer = myColor;
      }
    });
  }

  void _handlePointTap(
    int index,
    GameState state,
    OnlineGameController controller,
    List<Move> legalMoves,
    bool isMyTurn,
    PlayerColor? myColor,
  ) {
    if (!isMyTurn || myColor == null || state.phase != GamePhase.awaitingMove) return;

    if (state.board.barCount(myColor) > 0) {
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
      if (point.owner == myColor && legalMoves.any((m) => m.from == index)) {
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
    if (point.owner == myColor && legalMoves.any((m) => m.from == index)) {
      setState(() => _selectedPoint = index);
    } else {
      setState(() => _selectedPoint = null);
    }
  }

  void _handleBearOffTap(GameState state, OnlineGameController controller, List<Move> legalMoves) {
    if (_selectedPoint == null) return;
    final match = legalMoves.firstWhere(
      (m) => m.from == _selectedPoint && m.isBearOff,
      orElse: () => const Move(player: PlayerColor.white, from: -99, to: -99, die: 0),
    );
    if (match.from == _selectedPoint) {
      _commitMove(match, controller);
    }
  }

  void _commitMove(Move move, OnlineGameController controller) {
    setState(() {
      _selectedPoint = null;
      _selectedIsBar = false;
    });
    controller.playMove(move);
  }

  Widget _buildTopBar(BuildContext context, OnlineState state, OnlineGameController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _confirmForfeit(context, controller),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'CYBER TAVLA',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    fontSize: 15,
                  ),
                ),
                Text(
                  state.opponentNickname != null
                      ? '${AppStrings.multiplayerTitle} · ${state.opponentNickname}'
                      : AppStrings.multiplayerTitle,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmForfeit(context, controller),
            icon: const Icon(Icons.flag_rounded, color: AppColors.neonRed),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.neonRed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonRed.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.neonRed, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              AppStrings.opponentDisconnected,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentRow(GameState state, OnlineState onlineState) {
    final opponentColor = onlineState.myColor?.opponent;
    final isOpponentTurn = opponentColor != null && state.currentPlayer == opponentColor;
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
            GlowBadge(
              text: onlineState.opponentNickname ?? AppStrings.opponentTurn,
              color: AppColors.playerBlack,
              icon: Icons.person_rounded,
            ),
          _BarCountChip(player: PlayerColor.black, board: state.board),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    GameState state,
    OnlineState onlineState,
    OnlineGameController controller,
    bool isMyTurn,
    bool canBearOffSelected,
  ) {
    final legalMoves = isMyTurn ? state.legalMoves() : const <Move>[];
    final myColor = onlineState.myColor ?? PlayerColor.white;
    final myTurnBadgeColor =
        myColor == PlayerColor.white ? AppColors.playerWhite : AppColors.playerBlack;

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
                text: isMyTurn ? AppStrings.yourTurn : AppStrings.opponentTurn,
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
                isRolling: false,
                glowColor: myTurnBadgeColor,
              ),
              const SizedBox(width: 20),
              if (state.phase == GamePhase.awaitingRoll && isMyTurn)
                SizedBox(
                  width: 140,
                  height: 48,
                  child: NeonButton(
                    label: AppStrings.rollDice,
                    color: myTurnBadgeColor,
                    icon: Icons.casino_rounded,
                    onPressed: controller.rollDice,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmForfeit(BuildContext context, OnlineGameController controller) {
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
              controller.leaveRoom();
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text(AppStrings.forfeit, style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog(OnlineState onlineState, OnlineGameController controller) {
    final state = onlineState.game;
    if (state == null) return;
    final winner = state.winner;
    final iWon = winner != null && winner == onlineState.myColor;
    final title = iWon ? AppStrings.youWin : AppStrings.youLose;
    final color = iWon ? AppColors.neonGreen : AppColors.neonRed;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(
          builder: (dialogContext, ref, _) {
            final liveState = ref.watch(onlineGameControllerProvider(_config));
            return AlertDialog(
              title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              content: Text(
                liveState.rematchOfferedByOpponent
                    ? 'Rakibin yeniden eşleşme istiyor.'
                    : liveState.rematchRequestedByMe
                        ? AppStrings.waitingForRematch
                        : (winner == PlayerColor.white
                            ? '${AppStrings.colorWhite} kazandı.'
                            : '${AppStrings.colorBlack} kazandı.'),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    controller.leaveRoom();
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text(AppStrings.returnToMenu),
                ),
                TextButton(
                  onPressed: liveState.rematchRequestedByMe
                      ? null
                      : () {
                          setState(() {
                            _queue.clear();
                            _animating = false;
                            _lastSeenHistoryLen = 0;
                            _gameOverDialogShown = false;
                            _selectedPoint = null;
                            _selectedIsBar = false;
                          });
                          controller.requestRematch();
                        },
                  child: const Text(AppStrings.rematch),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (mounted) setState(() => _gameOverDialogShown = false);
    });
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
    return GlowBadge(
      text: '${AppStrings.barLabel}: $count',
      color: color,
      icon: Icons.pause_circle_filled_rounded,
    );
  }
}