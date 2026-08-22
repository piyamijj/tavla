import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/board.dart';
import '../../../shared/player.dart';
import '../pieces/piece_widget.dart';
import 'board_geometry.dart';

/// Identifies a single checker location for the purpose of skipping it
/// during static painting (because it is currently animating as a "flying"
/// checker overlay instead).
class SkipChecker {
  final int pointIndex;
  final int ordinal;

  const SkipChecker(this.pointIndex, this.ordinal);
}

/// CustomPainter that draws the full neon backgammon board: the base panel,
/// 24 alternating glowing triangular points, the central bar, static
/// checker stacks, and selection / legal-destination highlights.
///
/// Checkers that are currently mid-flight (being animated by an overlay
/// widget) are skipped here via [skipChecker] so they aren't drawn twice.
class BoardPainter extends CustomPainter {
  final Board board;
  final int? selectedPoint;
  final bool selectedIsBar;
  final PlayerColor selectedBarPlayer;
  final Set<int> legalDestinations;
  final bool legalBarEntryHighlighted;
  final SkipChecker? skipChecker;
  final double barWidthFraction;
  final double pointHeightFraction;

  BoardPainter({
    required this.board,
    this.selectedPoint,
    this.selectedIsBar = false,
    this.selectedBarPlayer = PlayerColor.white,
    this.legalDestinations = const {},
    this.legalBarEntryHighlighted = false,
    this.skipChecker,
    this.barWidthFraction = 0.08,
    this.pointHeightFraction = 0.42,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = BoardGeometry(
      size: size,
      barWidthFraction: barWidthFraction,
      pointHeightFraction: pointHeightFraction,
    );

    _paintBasePanel(canvas, size);
    _paintBar(canvas, size, geometry);

    for (var i = 0; i < kPointCount; i++) {
      _paintPointTriangle(canvas, geometry, i);
    }

    _paintCenterDivider(canvas, size);

    for (var i = 0; i < kPointCount; i++) {
      _paintCheckerStack(canvas, geometry, i);
    }

    _paintBarCheckers(canvas, geometry);
  }

  void _paintBasePanel(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..color = AppColors.boardBase;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      paint,
    );

    final borderPaint = Paint()
      ..color = AppColors.boardBorder.withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(18)),
      borderPaint,
    );
  }

  void _paintCenterDivider(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  void _paintBar(Canvas canvas, Size size, BoardGeometry geometry) {
    final barRect = Rect.fromLTWH(
      6 * geometry.pointWidth,
      0,
      geometry.barWidth,
      size.height,
    );
    final paint = Paint()..color = AppColors.barZone;
    canvas.drawRect(barRect, paint);

    final edgePaint = Paint()
      ..color = AppColors.neonPurple.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawLine(barRect.topLeft, barRect.bottomLeft, edgePaint);
    canvas.drawLine(barRect.topRight, barRect.bottomRight, edgePaint);
  }

  void _paintPointTriangle(Canvas canvas, BoardGeometry geometry, int index) {
    final rect = geometry.pointRect(index);
    final apex = geometry.pointApex(index);
    final bottom = geometry.isBottomRow(index);

    final path = Path()
      ..moveTo(rect.left, bottom ? rect.bottom : rect.top)
      ..lineTo(rect.right, bottom ? rect.bottom : rect.top)
      ..lineTo(apex.dx, apex.dy)
      ..close();

    final col = geometry.columnOf(index);
    final isLight = col.isEven;
    final basePaint = Paint()
      ..color = isLight ? AppColors.pointLight : AppColors.pointDark;
    canvas.drawPath(path, basePaint);

    final isLegalDestination = legalDestinations.contains(index);
    if (isLegalDestination) {
      final highlightPaint = Paint()
        ..color = AppColors.neonGreen.withOpacity(0.28)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, highlightPaint);

      final glowPaint = Paint()
        ..color = AppColors.neonGreen.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(path, glowPaint);
    }

    if (selectedPoint == index && !selectedIsBar) {
      final selPaint = Paint()
        ..color = AppColors.neonYellow.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawPath(path, selPaint);
    }

    final outlinePaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, outlinePaint);
  }

  void _paintCheckerStack(Canvas canvas, BoardGeometry geometry, int index) {
    final point = board.points[index];
    if (point.isEmpty) return;

    for (var ordinal = 0; ordinal < point.count; ordinal++) {
      if (skipChecker != null &&
          skipChecker!.pointIndex == index &&
          skipChecker!.ordinal == ordinal) {
        continue;
      }
      final center = geometry.checkerCenter(index, ordinal);
      final isTopOfStack = ordinal == point.count - 1;
      final showCountBadge = isTopOfStack && point.count > 5;
      _paintChecker(
        canvas,
        center,
        geometry.checkerDiameter,
        point.owner!,
        countBadge: showCountBadge ? point.count : null,
      );
    }
  }

  void _paintBarCheckers(Canvas canvas, BoardGeometry geometry) {
    for (final player in PlayerColor.values) {
      final count = board.barCount(player);
      if (count == 0) continue;
      final isWhite = player == PlayerColor.white;
      for (var ordinal = 0; ordinal < count; ordinal++) {
        final center = geometry.barCheckerCenter(isWhite, ordinal);
        final isTopOfStack = ordinal == count - 1;
        _paintChecker(
          canvas,
          center,
          geometry.checkerDiameter * 0.9,
          player,
          countBadge: (isTopOfStack && count > 3) ? count : null,
          highlighted: selectedIsBar && selectedBarPlayer == player,
        );
      }
    }
  }

  void _paintChecker(
    Canvas canvas,
    Offset center,
    double diameter,
    PlayerColor owner, {
    int? countBadge,
    bool highlighted = false,
  }) {
    paintCheckerOnCanvas(
      canvas,
      center,
      diameter,
      owner,
      countBadge: countBadge,
      highlighted: highlighted,
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) {
    return oldDelegate.board != board ||
        oldDelegate.selectedPoint != selectedPoint ||
        oldDelegate.selectedIsBar != selectedIsBar ||
        oldDelegate.selectedBarPlayer != selectedBarPlayer ||
        oldDelegate.legalDestinations != legalDestinations ||
        oldDelegate.skipChecker != skipChecker;
  }
}