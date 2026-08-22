import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Paints a single die face (rounded square) with neon pips for [value]
/// (1-6). Used by [DiceTray] for both the settled result and the shuffling
/// animation frames.
class DiceFacePainter extends CustomPainter {
  final int value;
  final Color glowColor;
  final bool dimmed;

  DiceFacePainter({
    required this.value,
    required this.glowColor,
    this.dimmed = false,
  }) : assert(value >= 1 && value <= 6);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.22));

    final opacity = dimmed ? 0.35 : 1.0;

    final glowPaint = Paint()
      ..color = glowColor.withOpacity(0.55 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(rrect.inflate(1), glowPaint);

    final facePaint = Paint()
      ..color = AppColors.surfaceVariant.withOpacity(opacity)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, facePaint);

    final borderPaint = Paint()
      ..color = glowColor.withOpacity(0.9 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045;
    canvas.drawRRect(rrect.deflate(borderPaint.strokeWidth / 2), borderPaint);

    final pipPaint = Paint()..color = glowColor.withOpacity(opacity);
    final pipRadius = size.width * 0.09;

    final left = size.width * 0.26;
    final center = size.width * 0.5;
    final right = size.width * 0.74;
    final top = size.height * 0.26;
    final middle = size.height * 0.5;
    final bottom = size.height * 0.74;

    final positions = <Offset>[];
    switch (value) {
      case 1:
        positions.add(Offset(center, middle));
        break;
      case 2:
        positions.add(Offset(left, top));
        positions.add(Offset(right, bottom));
        break;
      case 3:
        positions.add(Offset(left, top));
        positions.add(Offset(center, middle));
        positions.add(Offset(right, bottom));
        break;
      case 4:
        positions.add(Offset(left, top));
        positions.add(Offset(right, top));
        positions.add(Offset(left, bottom));
        positions.add(Offset(right, bottom));
        break;
      case 5:
        positions.add(Offset(left, top));
        positions.add(Offset(right, top));
        positions.add(Offset(center, middle));
        positions.add(Offset(left, bottom));
        positions.add(Offset(right, bottom));
        break;
      case 6:
        positions.add(Offset(left, top));
        positions.add(Offset(right, top));
        positions.add(Offset(left, middle));
        positions.add(Offset(right, middle));
        positions.add(Offset(left, bottom));
        positions.add(Offset(right, bottom));
        break;
    }

    for (final p in positions) {
      canvas.drawCircle(p, pipRadius, pipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DiceFacePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.glowColor != glowColor ||
      oldDelegate.dimmed != dimmed;
}

/// A single die widget wrapping [DiceFacePainter] at a fixed size, with a
/// gentle rotation applied while [isShuffling] to sell the "rolling" feel.
class _DieFace extends StatelessWidget {
  final int value;
  final Color glowColor;
  final bool dimmed;
  final double angle;
  final double size;

  const _DieFace({
    required this.value,
    required this.glowColor,
    required this.dimmed,
    required this.angle,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: DiceFacePainter(value: value, glowColor: glowColor, dimmed: dimmed),
        ),
      ),
    );
  }
}

/// Displays the dice for the current turn: 2 dice normally, or 4 identical
/// dice when a double was rolled. Dice whose value is no longer present in
/// [remainingDice] (already played this turn) are rendered dimmed.
///
/// While [isRolling] is true, the tray ignores [values] and instead plays a
/// short self-contained shuffle animation (random faces, slight wobble)
/// before the caller flips [isRolling] back to false and supplies the real
/// [values] to reveal the settled result.
class DiceTray extends StatefulWidget {
  final List<int> values;
  final List<int> remainingDice;
  final bool isRolling;
  final Color glowColor;
  final double dieSize;

  const DiceTray({
    super.key,
    required this.values,
    required this.remainingDice,
    required this.isRolling,
    this.glowColor = AppColors.neonCyan,
    this.dieSize = 48,
  });

  @override
  State<DiceTray> createState() => _DiceTrayState();
}

class _DiceTrayState extends State<DiceTray> with SingleTickerProviderStateMixin {
  late final AnimationController _shuffleController;
  final _random = Random();
  List<int> _shuffleFaces = [1, 2];
  Timer? _faceTimer;

  @override
  void initState() {
    super.initState();
    _shuffleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.isRolling) _startShuffle();
  }

  @override
  void didUpdateWidget(covariant DiceTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRolling && !oldWidget.isRolling) {
      _startShuffle();
    } else if (!widget.isRolling && oldWidget.isRolling) {
      _stopShuffle();
    }
  }

  void _startShuffle() {
    _shuffleController
      ..reset()
      ..repeat();
    _faceTimer?.cancel();
    _faceTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) return;
      setState(() {
        _shuffleFaces = List.generate(4, (_) => _random.nextInt(6) + 1);
      });
    });
  }

  void _stopShuffle() {
    _faceTimer?.cancel();
    _faceTimer = null;
    _shuffleController.stop();
  }

  @override
  void dispose() {
    _faceTimer?.cancel();
    _shuffleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isRolling) {
      return AnimatedBuilder(
        animation: _shuffleController,
        builder: (context, _) {
          final wobble = sin(_shuffleController.value * 2 * pi) * 0.12;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DieFace(
                value: _shuffleFaces[0],
                glowColor: widget.glowColor,
                dimmed: false,
                angle: wobble,
                size: widget.dieSize,
              ),
              const SizedBox(width: 10),
              _DieFace(
                value: _shuffleFaces[1],
                glowColor: widget.glowColor,
                dimmed: false,
                angle: -wobble,
                size: widget.dieSize,
              ),
            ],
          );
        },
      );
    }

    if (widget.values.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DieFace(value: 1, glowColor: widget.glowColor.withOpacity(0.25), dimmed: true, angle: 0, size: widget.dieSize),
          const SizedBox(width: 10),
          _DieFace(value: 1, glowColor: widget.glowColor.withOpacity(0.25), dimmed: true, angle: 0, size: widget.dieSize),
        ],
      );
    }

    // Track how many of each die value remain playable, so with doubles
    // (e.g. four 5s, two already used) exactly the right count is dimmed.
    final remainingPool = List<int>.of(widget.remainingDice);
    final dice = <Widget>[];
    for (var i = 0; i < widget.values.length; i++) {
      final value = widget.values[i];
      final idx = remainingPool.indexOf(value);
      final isUsed = idx == -1;
      if (!isUsed) remainingPool.removeAt(idx);

      dice.add(_DieFace(
        value: value,
        glowColor: widget.glowColor,
        dimmed: isUsed,
        angle: 0,
        size: widget.dieSize,
      ));
      if (i != widget.values.length - 1) dice.add(const SizedBox(width: 10));
    }

    return Wrap(spacing: 0, runSpacing: 10, children: dice);
  }
}