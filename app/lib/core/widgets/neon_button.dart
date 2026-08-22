import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Visual style variant for [NeonButton].
enum NeonButtonVariant {
  /// Solid fill with a glowing halo — used for primary/confirming actions.
  filled,

  /// Transparent background with a glowing border — used for secondary
  /// actions.
  outlined,
}

/// A cyber/neon styled button with a glowing halo, used across the main
/// menu, dialogs and in-game action bars.
///
/// The [label] is plain display text supplied by the caller (all
/// user-facing copy lives in `AppStrings` and is passed in from there).
class NeonButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final NeonButtonVariant variant;
  final IconData? icon;
  final double width;
  final double height;
  final bool loading;

  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.neonCyan,
    this.variant = NeonButtonVariant.filled,
    this.icon,
    this.width = double.infinity,
    this.height = 56,
    this.loading = false,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final isFilled = widget.variant == NeonButtonVariant.filled;

    final background = isFilled
        ? color.withOpacity(_enabled ? (_pressed ? 0.35 : 0.22) : 0.08)
        : Colors.transparent;

    final borderColor = _enabled ? color : color.withOpacity(0.3);
    final textColor = _enabled ? Colors.white : Colors.white38;

    return GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: _enabled ? widget.onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.6),
          boxShadow: _enabled
              ? AppColors.glow(color, blur: _pressed ? 10 : 16, spread: _pressed ? 0.4 : 1)
              : null,
        ),
        alignment: Alignment.center,
        child: widget.loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: textColor, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}