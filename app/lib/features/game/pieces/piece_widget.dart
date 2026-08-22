import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/player.dart';

/// Paints a single checker (piece) onto [canvas] at [center] with the given
/// [diameter]. Shared by [BoardPainter] (for static stacks) and
/// [FlyingChecker] (for the mid-move animated overlay) so both render
/// pieces identically.
///
/// [countBadge], when provided, draws a small numeric label on top of the
/// checker (used for stacks taller than the visual cap). [highlighted]
/// draws an extra glowing selection ring (used for the checker currently
/// selected on the bar or on a point).
void paintCheckerOnCanvas(
  Canvas canvas,
  Offset center,
  double diameter,
  PlayerColor owner, {
  int? countBadge,
  bool highlighted = false,
}) {
  final radius = diameter / 2;
  final color = owner == PlayerColor.white ? AppColors.playerWhite : AppColors.playerBlack;

  final glowPaint = Paint()
    ..color = color.withOpacity(highlighted ? 0.95 : 0.55)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, highlighted ? 10 : 6);
  canvas.drawCircle(center, radius * 0.96, glowPaint);

  final bodyGradient = RadialGradient(
    colors: [
      Color.lerp(color, Colors.white, 0.35)!,
      color,
      Color.lerp(color, Colors.black, 0.45)!,
    ],
    stops: const [0.0, 0.55, 1.0],
  );
  final bodyPaint = Paint()
    ..shader = bodyGradient.createShader(
      Rect.fromCircle(center: center, radius: radius),
    );
  canvas.drawCircle(center, radius * 0.86, bodyPaint);

  final ringPaint = Paint()
    ..color = Colors.black.withOpacity(0.55)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  canvas.drawCircle(center, radius * 0.86, ringPaint);

  if (highlighted) {
    final selRing = Paint()
      ..color = AppColors.neonYellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center, radius * 0.95, selRing);
  }

  if (countBadge != null) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$countBadge',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }
}

/// A standalone widget rendering a single checker at a fixed size, useful
/// for legends, difficulty/color pickers and other UI chrome outside the
/// board itself.
class CheckerGlyph extends StatelessWidget {
  final PlayerColor owner;
  final double diameter;
  final bool highlighted;

  const CheckerGlyph({
    super.key,
    required this.owner,
    this.diameter = 28,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _SingleCheckerPainter(owner: owner, highlighted: highlighted),
      ),
    );
  }
}

class _SingleCheckerPainter extends CustomPainter {
  final PlayerColor owner;
  final bool highlighted;

  _SingleCheckerPainter({required this.owner, required this.highlighted});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    paintCheckerOnCanvas(canvas, center, size.shortestSide, owner, highlighted: highlighted);
  }

  @override
  bool shouldRepaint(covariant _SingleCheckerPainter oldDelegate) =>
      oldDelegate.owner != owner || oldDelegate.highlighted != highlighted;
}

/// An animated overlay checker that flies from [start] to [end] over
/// [duration], with a small parabolic "hop" arc for a lively feel. Used by
/// [BoardWidget] to visualize a move while the underlying board painter
/// skips drawing the corresponding static checker.
///
/// Calls [onCompleted] exactly once when the flight animation finishes.
class FlyingChecker extends StatefulWidget {
  final Offset start;
  final Offset end;
  final double diameter;
  final PlayerColor owner;
  final Duration duration;
  final VoidCallback onCompleted;

  const FlyingChecker({
    super.key,
    required this.start,
    required this.end,
    required this.diameter,
    required this.owner,
    required this.onCompleted,
    this.duration = const Duration(milliseconds: 260),
  });

  @override
  State<FlyingChecker> createState() => _FlyingCheckerState();
}

class _FlyingCheckerState extends State<FlyingChecker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _completedFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_handleStatus)
      ..forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_completedFired) {
      _completedFired = true;
      widget.onCompleted();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final base = Offset.lerp(widget.start, widget.end, t)!;
        final hop = math.sin(math.pi * t) * (widget.diameter * 0.9);
        final center = Offset(base.dx, base.dy - hop);
        final r = widget.diameter / 2;
        return Positioned(
          left: center.dx - r,
          top: center.dy - r,
          width: widget.diameter,
          height: widget.diameter,
          child: IgnorePointer(
            child: CustomPaint(
              size: Size.square(widget.diameter),
              painter: _SingleCheckerPainter(owner: widget.owner, highlighted: true),
            ),
          ),
        );
      },
    );
  }
}