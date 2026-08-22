import 'dart:ui';

import 'package:flutter/material.dart' show Rect;

import '../../../shared/board.dart';

/// Pure layout math mapping backgammon point indices (0-23), the bar, and
/// the off (bear-off) zone to screen positions for a given board size.
///
/// Visual layout follows the standard physical board convention:
///   Bottom row, left to right on screen: points 12,11,10,9,8,7 | BAR | 6,5,4,3,2,1
///   Top row, left to right on screen:    points 13,14,15,16,17,18 | BAR | 19,20,21,22,23,24
///
/// Indices are point numbers minus one (so point 1 is index 0, point 24 is
/// index 23). Points 0-11 sit on the bottom row, 12-23 on the top row.
class BoardGeometry {
  final Size size;

  /// Fraction of the board width reserved for the central bar gap.
  final double barWidthFraction;

  /// Fraction of the board height each point's triangle occupies.
  final double pointHeightFraction;

  /// Visual diameter of a single checker, derived from point width.
  late final double checkerDiameter;

  late final double pointWidth;
  late final double barWidth;
  late final double pointHeight;

  BoardGeometry({
    required this.size,
    this.barWidthFraction = 0.08,
    this.pointHeightFraction = 0.42,
  }) {
    barWidth = size.width * barWidthFraction;
    pointWidth = (size.width - barWidth) / 12;
    pointHeight = size.height * pointHeightFraction;
    checkerDiameter = pointWidth * 0.86;
  }

  /// Whether point [index] (0-23) sits on the bottom row.
  bool isBottomRow(int index) => index >= 0 && index <= 11;

  /// The screen column (0-11) a point index occupies, left to right,
  /// ignoring the bar gap (the gap is added back in [columnX]).
  int columnOf(int index) {
    if (index >= 0 && index <= 11) return 11 - index;
    if (index >= 12 && index <= 23) return index - 12;
    throw RangeError.value(index, 'index', 'Must be 0-23');
  }

  /// The x-coordinate of the left edge of column [col] (0-11), accounting
  /// for the central bar gap between columns 5 and 6.
  double columnX(int col) {
    if (col < 6) return col * pointWidth;
    return 6 * pointWidth + barWidth + (col - 6) * pointWidth;
  }

  /// The triangle (point) rectangle for point [index] on the board.
  Rect pointRect(int index) {
    final col = columnOf(index);
    final x = columnX(col);
    final bottom = isBottomRow(index);
    final top = bottom ? size.height - pointHeight : 0.0;
    return Rect.fromLTWH(x, top, pointWidth, pointHeight);
  }

  /// The apex point of the triangle for point [index] (used for painting).
  Offset pointApex(int index) {
    final rect = pointRect(index);
    final bottom = isBottomRow(index);
    return Offset(rect.left + rect.width / 2, bottom ? rect.top : rect.bottom);
  }

  /// The base midpoint of the triangle for point [index] (board edge side).
  Offset pointBase(int index) {
    final rect = pointRect(index);
    final bottom = isBottomRow(index);
    return Offset(rect.left + rect.width / 2, bottom ? rect.bottom : rect.top);
  }

  /// Center of the [ordinal]-th checker (0-based, stacking from the board
  /// edge toward the center) on point [index].
  Offset checkerCenter(int index, int ordinal) {
    final base = pointBase(index);
    final bottom = isBottomRow(index);
    final direction = bottom ? -1 : 1;

    // Visually cap dense stacks so they don't overflow past the middle of
    // the board; checkers beyond the cap overlap slightly (a small count
    // badge on the UI layer communicates the exact number).
    const visualCap = 5;
    final visualOrdinal = ordinal >= visualCap ? visualCap - 1 : ordinal;
    final overlapBoost = ordinal >= visualCap ? 0.0 : 1.0;

    final spacing = checkerDiameter * 0.92 * overlapBoost + checkerDiameter * 0.0;
    final offset = (checkerDiameter / 2) + visualOrdinal * (checkerDiameter * 0.92);

    return Offset(base.dx, base.dy + direction * (offset == 0 ? spacing : offset));
  }

  /// Center of the bar zone for [player]'s stacked checkers waiting to
  /// re-enter. White stacks toward the bottom half of the bar, black
  /// toward the top half.
  Offset barCheckerCenter(bool isWhite, int ordinal) {
    final barCenterX = 6 * pointWidth + barWidth / 2;
    final halfHeight = size.height / 2;
    final baseY = isWhite ? size.height - halfHeight * 0.28 : halfHeight * 0.28;
    final direction = isWhite ? -1 : 1;
    final offset = ordinal * (checkerDiameter * 0.8);
    return Offset(barCenterX, baseY + direction * offset);
  }

  /// Hit-tests a tap [position] against the 24 points, returning the point
  /// index (0-23), or `null` if the tap missed every point (e.g. landed on
  /// the bar gap or outside the board).
  int? hitTestPoint(Offset position) {
    for (var i = 0; i < kPointCount; i++) {
      if (pointRect(i).contains(position)) return i;
    }
    return null;
  }

  /// Whether [position] falls within the central bar zone.
  bool hitTestBar(Offset position) {
    final barRect = Rect.fromLTWH(6 * pointWidth, 0, barWidth, size.height);
    return barRect.contains(position);
  }
}