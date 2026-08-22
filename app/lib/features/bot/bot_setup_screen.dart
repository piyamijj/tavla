import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/glow_panel.dart';
import '../../core/widgets/neon_button.dart';
import '../../shared/player.dart';
import '../game/game_providers.dart';
import '../game/screens/game_screen.dart';
import '../game/pieces/piece_widget.dart';
import 'bot_ai.dart';

/// Lets the player pick a bot [BotDifficulty] and which color they'll play
/// before starting a single-player match against the tiered bot AI.
class BotSetupScreen extends StatefulWidget {
  const BotSetupScreen({super.key});

  @override
  State<BotSetupScreen> createState() => _BotSetupScreenState();
}

class _BotSetupScreenState extends State<BotSetupScreen> {
  BotDifficulty _difficulty = BotDifficulty.easy;
  PlayerColor _humanColor = PlayerColor.white;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text(AppStrings.singlePlayerTitle),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(AppStrings.chooseDifficulty),
                      const SizedBox(height: 12),
                      _difficultyCard(
                        BotDifficulty.easy,
                        AppStrings.difficultyEasy,
                        AppStrings.difficultyEasyDesc,
                        AppColors.neonGreen,
                        Icons.sentiment_satisfied_alt_rounded,
                      ),
                      const SizedBox(height: 12),
                      _difficultyCard(
                        BotDifficulty.medium,
                        AppStrings.difficultyMedium,
                        AppStrings.difficultyMediumDesc,
                        AppColors.neonYellow,
                        Icons.psychology_alt_rounded,
                      ),
                      const SizedBox(height: 12),
                      _difficultyCard(
                        BotDifficulty.hard,
                        AppStrings.difficultyHard,
                        AppStrings.difficultyHardDesc,
                        AppColors.neonRed,
                        Icons.local_fire_department_rounded,
                      ),
                      const SizedBox(height: 28),
                      _sectionTitle(AppStrings.chooseYourColor),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _colorCard(PlayerColor.white, AppStrings.colorWhite),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _colorCard(PlayerColor.black, AppStrings.colorBlack),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: NeonButton(
                  label: AppStrings.startGame,
                  icon: Icons.play_arrow_rounded,
                  color: AppColors.neonCyan,
                  onPressed: _startGame,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _difficultyCard(
    BotDifficulty difficulty,
    String title,
    String description,
    Color color,
    IconData icon,
  ) {
    final selected = _difficulty == difficulty;
    return GestureDetector(
      onTap: () => setState(() => _difficulty = difficulty),
      child: GlowPanel(
        glowColor: selected ? color : AppColors.neonPurple.withOpacity(0.3),
        borderWidth: selected ? 1.8 : 1.0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _colorCard(PlayerColor color, String label) {
    final selected = _humanColor == color;
    final accent = color == PlayerColor.white ? AppColors.playerWhite : AppColors.playerBlack;
    return GestureDetector(
      onTap: () => setState(() => _humanColor = color),
      child: GlowPanel(
        glowColor: selected ? accent : AppColors.neonPurple.withOpacity(0.3),
        borderWidth: selected ? 1.8 : 1.0,
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            CheckerGlyph(owner: color, diameter: 40, highlighted: selected),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startGame() {
    final config = GameConfig(
      mode: GameMode.bot,
      humanColor: _humanColor,
      botDifficulty: _difficulty,
      startingPlayer: PlayerColor.white,
    );

    final difficultyLabel = switch (_difficulty) {
      BotDifficulty.easy => AppStrings.difficultyEasy,
      BotDifficulty.medium => AppStrings.difficultyMedium,
      BotDifficulty.hard => AppStrings.difficultyHard,
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          config: config,
          subtitle: '${AppStrings.menuSinglePlayer} · $difficultyLabel',
        ),
      ),
    );
  }
}