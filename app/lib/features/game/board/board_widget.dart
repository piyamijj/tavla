import 'package:flutter/material.dart';

import '../../../shared/board.dart';
import '../../../shared/moves.dart';
import '../../../shared/player.dart';
import '../pieces/piece_widget.dart';
import 'board_geometry.dart';
import 'board_painter.dart';

/// A move currently animating on the board: the [move] being played plus a
/// [token] that changes identity every time a new animation should start
/// (letting the widget distinguish "still the same flight" from "a new one
/// just began"), and the callback to invoke once the flight finishes.
class AnimatingMove {
  final Move move;
  final Object token;
  final VoidCallback onCompleted;

  const AnimatingMove({
    required this.move,
    required this.token,
    required this.onCompleted,
  });
}

/// Interactive backgammon board: renders the current [board] via
/// [BoardPainter], turns taps into point/bar selections, and overlays a
/// [FlyingChecker] animation while [animatingMove] is set.
///
/// The board itself does not own game rules — it only reports taps via
/// [onPointTap] / [onBarTap] and lets the caller (the game screen /
/// controller) decide what a tap means (select, move, or ignore).
class BoardWidget extends StatefulWidget {
  final Board board;
  final int? selectedPoint;
  final bool selectedIsBar;
  final PlayerColor selectedBarPlayer;
  final Set<int> legalDestinations;
  final ValueChanged<int> onPointTap;
  final VoidCallback? onBarTap;
  final AnimatingMove? animatingMove;

  const BoardWidget({
    super.key,
    required this.board,
    required this.onPointTap,
    this.selectedPoint,
    this.selectedIsBar = false,
    this.selectedBarPlayer = PlayerColor.white,
    this.legalDestinations = const {},
    this.onBarTap,
    this.animatingMove,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> {
  Object? _activeToken;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geometry = BoardGeometry(size: size);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(details.localPosition, geometry),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: size,
                  painter: BoardPainter(
                    board: widget.board,
                    selectedPoint: widget.selectedPoint,
                    selectedIsBar: widget.selectedIsBar,
                    selectedBarPlayer: widget.selectedBarPlayer,
                    legalDestinations: widget.legalDestinations,
                    skipChecker: _skipCheckerFor(widget.animatingMove),
                  ),
                ),
                if (widget.animatingMove != null)
                  ..._buildFlyingChecker(geometry, widget.animatingMove!),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleTap(Offset position, BoardGeometry geometry) {
    if (widget.animatingMove != null) return; // ignore taps mid-animation

    if (geometry.hitTestBar(position)) {
      widget.onBarTap?.call();
      return;
    }
    final index = geometry.hitTestPoint(position);
    if (index != null) {
      widget.onPointTap(index);
    }
  }

  /// Determines which static checker to hide because it is currently being
  /// represented by the flying overlay instead. For a bar-entry move there
  /// is nothing to skip on the point grid (the bar painter already excludes
  /// counting an in-flight checker via the pre-move board state passed in
  /// by the caller), so this only applies to point-to-point and bear-off
  /// moves.
  SkipChecker? _skipCheckerFor(AnimatingMove? animating) {
    if (animating == null) return null;
    final move = animating.move;
    if (move.isFromBar) return null;
    final originPoint = widget.board.points[move.from];
    if (originPoint.isEmpty) return null;
    return SkipChecker(move.from, originPoint.count - 1);
  }

  List<Widget> _buildFlyingChecker(BoardGeometry geometry, AnimatingMove animating) {
    final move = animating.move;

    final Offset start;
    if (move.isFromBar) {
      final isWhite = move.player == PlayerColor.white;
      final ordinal = widget.board.barCount(move.player) - 1;
      start = geometry.barCheckerCenter(isWhite, ordinal < 0 ? 0 : ordinal);
    } else {
      final originPoint = widget.board.points[move.from];
      final ordinal = originPoint.count > 0 ? originPoint.count - 1 : 0;
      start = geometry.checkerCenter(move.from, ordinal);
    }

    final Offset end;
    if (move.isBearOff) {
      // No dedicated off-tray in board coordinates: animate just past the
      // board edge on the moving player's side, toward where an off-tray
      // widget conventionally sits outside the board.
      final base = geometry.pointBase(move.from);
      final bottom = geometry.isBottomRow(move.from);
      end = Offset(base.dx, bottom ? geometry.size.height + 30 : -30);
    } else {
      final destPoint = widget.board.points[move.to];
      final destOrdinal = destPoint.owner == move.player ? destPoint.count : 0;
      end = geometry.checkerCenter(move.to, destOrdinal);
    }

    return [
      FlyingChecker(
        key: ValueKey(animating.token),
        start: start,
        end: end,
        diameter: geometry.checkerDiameter,
        owner: move.player,
        onCompleted: animating.onCompleted,
      ),
    ];
  }
}