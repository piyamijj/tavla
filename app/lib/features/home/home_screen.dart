import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/glow_panel.dart';
import '../../core/widgets/neon_button.dart';
import '../bot/bot_setup_screen.dart';
import '../online/multiplayer_lobby_screen.dart';
import '../settings/settings_screen.dart';
import 'how_to_play_screen.dart';

/// The app's main menu: title/logo, and navigation into single player
/// (bot), multiplayer (online), settings and the how-to-play guide.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    _buildLogo(),
                    const SizedBox(height: 10),
                    const Text(
                      AppStrings.homeSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                    GlowPanel(
                      glowColor: AppColors.neonPurple,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          NeonButton(
                            label: AppStrings.menuSinglePlayer,
                            icon: Icons.person_rounded,
                            color: AppColors.neonCyan,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const BotSetupScreen()),
                            ),
                          ),
                          const SizedBox(height: 14),
                          NeonButton(
                            label: AppStrings.menuMultiplayer,
                            icon: Icons.public_rounded,
                            color: AppColors.neonMagenta,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const MultiplayerLobbyScreen()),
                            ),
                          ),
                          const SizedBox(height: 14),
                          NeonButton(
                            label: AppStrings.menuHowToPlay,
                            icon: Icons.help_outline_rounded,
                            color: AppColors.neonPurple,
                            variant: NeonButtonVariant.outlined,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const HowToPlayScreen()),
                            ),
                          ),
                          const SizedBox(height: 14),
                          NeonButton(
                            label: AppStrings.menuSettings,
                            icon: Icons.settings_rounded,
                            color: AppColors.neonGreen,
                            variant: NeonButtonVariant.outlined,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      '${AppStrings.versionLabel} 1.0.0',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return ShaderMask(
      shaderCallback: (bounds) => AppColors.cyanMagentaGradient.createShader(bounds),
      child: const Text(
        AppStrings.homeTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          shadows: [
            Shadow(color: AppColors.neonCyan, blurRadius: 22),
            Shadow(color: AppColors.neonMagenta, blurRadius: 30),
          ],
        ),
      ),
    );
  }
}