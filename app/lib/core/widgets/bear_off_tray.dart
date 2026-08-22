import 'package:flutter/material.dart';

import '../../shared/player.dart';
import '../constants/app_colors.dart';

/// Small tray widget showing how many of [owner]'s checkers have been
/// borne off so far. When [active] is true (the currently selected checker
/// has a legal bear-off move), the tray pulses with a brighter glow and
/// becomes tappable via [onTap] to complete the move.
class BearOffTray extends StatefulWidget {
  final PlayerColor owner;
  final int count;
  final bool active;
  final VoidCallback? onTap;

  const BearOffTray({
    super.key,
    required this.owner,
    required this.count,
    this.active = false,
    this.onTap,
  });

  @override
  State<BearOffTray> createState() => _BearOffTrayState();
}

class _BearOffTrayState extends State<BearOffTray> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _color =>
      widget.owner == PlayerColor.white ? AppColors.playerWhite : AppColors.playerBlack;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.active ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = widget.active ? _pulseController.value : 0.0;
          final blur = 8.0 + pulse * 10.0;
          final borderOpacity = widget.active ? 0.65 + pulse * 0.35 : 0.35;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.panel.withOpacity(0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _color.withOpacity(borderOpacity),
                width: widget.active ? 1.8 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _color.withOpacity(widget.active ? 0.55 : 0.2),
                  blurRadius: blur,
                  spreadRadius: widget.active ? 0.6 : 0.1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stacked_bar_chart_rounded, size: 16, color: _color),
                const SizedBox(width: 6),
                Text(
                  '${widget.count}/15',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}