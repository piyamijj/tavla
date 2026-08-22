import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/glow_panel.dart';

/// Explains the rules of tavla (backgammon) in Turkish, laid out as a
/// series of glowing info cards over the cyber background.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text(AppStrings.howToPlayTitle),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoCard(
                        icon: Icons.grid_view_rounded,
                        color: AppColors.neonCyan,
                        title: 'Tahta ve Pullar',
                        body: AppStrings.howToPlayIntro,
                      ),
                      const SizedBox(height: 16),
                      _infoCard(
                        icon: Icons.casino_rounded,
                        color: AppColors.neonPurple,
                        title: 'Zar Atma',
                        body: AppStrings.howToPlayDice,
                      ),
                      const SizedBox(height: 16),
                      _infoCard(
                        icon: Icons.flash_on_rounded,
                        color: AppColors.neonMagenta,
                        title: 'Vurma ve Bar',
                        body: AppStrings.howToPlayHit,
                      ),
                      const SizedBox(height: 16),
                      _infoCard(
                        icon: Icons.stacked_bar_chart_rounded,
                        color: AppColors.neonGreen,
                        title: 'Toplama (Bear-off)',
                        body: AppStrings.howToPlayBearOff,
                      ),
                      const SizedBox(height: 16),
                      _infoCard(
                        icon: Icons.emoji_events_rounded,
                        color: AppColors.neonYellow,
                        title: 'Kazanma',
                        body:
                            'İlk olarak tüm 15 pulunu tahtadan çıkaran oyuncu oyunu kazanır. '
                            'Rakip hiç pul çıkaramadıysa bu bir GAMMON, üstelik rakibin bar\'da '
                            'veya senin ev bölgende pulu kaldıysa bir MARS (backgammon) sayılır.',
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return GlowPanel(
      glowColor: color,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}