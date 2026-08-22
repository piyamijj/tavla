import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Animated cyber backdrop: a dark gradient base with a slowly drifting
/// neon grid and soft glow blobs. Meant to sit behind every screen via
/// `Stack` so widgets keep a consistent "cyber" atmosphere without each
/// screen re-implementing it.
class CyberBackground extends StatefulWidget {
  final Widget? child;

  const CyberBackground({super.key, this.child});

  @override
  State<CyberBackground> createState() => _CyberBackgroundState();
}

class _CyberBackgroundState extends State<CyberBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _CyberGridPainter(progress: _controller.value),
              size: Size.infinite,
            );
          },
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _CyberGridPainter extends CustomPainter {
  final double progress;

  _CyberGridPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.neonPurple.withOpacity(0.06)
      ..strokeWidth = 1;

    const spacing = 42.0;
    final shift = progress * spacing;

    for (double x = -spacing + (shift % spacing); x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = -spacing + (shift % spacing); y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final blob1Center = Offset(
      size.width * (0.2 + 0.06 * math.sin(progress * 2 * math.pi)),
      size.height * 0.18,
    );
    final blob2Center = Offset(
      size.width * (0.82 + 0.05 * math.cos(progress * 2 * math.pi)),
      size.height * 0.78,
    );

    final blobPaint1 = Paint()
      ..color = AppColors.neonCyan.withOpacity(0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120);
    final blobPaint2 = Paint()
      ..color = AppColors.neonMagenta.withOpacity(0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 130);

    canvas.drawCircle(blob1Center, 160, blobPaint1);
    canvas.drawCircle(blob2Center, 180, blobPaint2);
  }

  @override
  bool shouldRepaint(covariant _CyberGridPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// A translucent "glass" panel with a glowing neon border, used for cards,
/// dialogs and grouped content throughout the app.
class GlowPanel extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double borderWidth;

  const GlowPanel({
    super.key,
    required this.child,
    this.glowColor = AppColors.neonPurple,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 20,
    this.borderWidth = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.panel.withOpacity(0.72),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: glowColor.withOpacity(0.6), width: borderWidth),
        boxShadow: AppColors.glow(glowColor, blur: 22, spread: 0.5),
      ),
      child: child,
    );
  }
}

/// A small glowing status pill (e.g. "Sıra sende", connection status).
class GlowBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const GlowBadge({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.8)),
        boxShadow: AppColors.glow(color, blur: 12, spread: 0.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}