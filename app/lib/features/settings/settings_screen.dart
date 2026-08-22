import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/glow_panel.dart';
import 'settings_providers.dart';

/// Settings screen: sound/music/vibration toggles, animation speed
/// selector, player nickname and the realtime server URL used by the
/// multiplayer feature. All changes persist immediately via
/// [SettingsController].
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _serverController;
  bool _controllersInitialized = false;

  @override
  void dispose() {
    if (_controllersInitialized) {
      _nameController.dispose();
      _serverController.dispose();
    }
    super.dispose();
  }

  void _ensureControllers(AppSettings settings) {
    if (_controllersInitialized) return;
    _nameController = TextEditingController(text: settings.playerName);
    _serverController = TextEditingController(text: settings.serverUrl);
    _controllersInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    _ensureControllers(settings);

    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text(AppStrings.settingsTitle),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlowPanel(
                        glowColor: AppColors.neonCyan,
                        child: Column(
                          children: [
                            _switchTile(
                              icon: Icons.volume_up_rounded,
                              label: AppStrings.settingSound,
                              value: settings.soundEnabled,
                              onChanged: controller.setSoundEnabled,
                            ),
                            const Divider(height: 24),
                            _switchTile(
                              icon: Icons.music_note_rounded,
                              label: AppStrings.settingMusic,
                              value: settings.musicEnabled,
                              onChanged: controller.setMusicEnabled,
                            ),
                            const Divider(height: 24),
                            _switchTile(
                              icon: Icons.vibration_rounded,
                              label: AppStrings.settingVibration,
                              value: settings.vibrationEnabled,
                              onChanged: controller.setVibrationEnabled,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      GlowPanel(
                        glowColor: AppColors.neonPurple,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.speed_rounded, color: AppColors.neonPurple, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  AppStrings.settingAnimationSpeed,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<AnimationSpeed>(
                              segments: const [
                                ButtonSegment(
                                  value: AnimationSpeed.slow,
                                  label: Text('Yavaş'),
                                ),
                                ButtonSegment(
                                  value: AnimationSpeed.normal,
                                  label: Text('Normal'),
                                ),
                                ButtonSegment(
                                  value: AnimationSpeed.fast,
                                  label: Text('Hızlı'),
                                ),
                              ],
                              selected: {settings.animationSpeed},
                              onSelectionChanged: (selection) =>
                                  controller.setAnimationSpeed(selection.first),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      GlowPanel(
                        glowColor: AppColors.neonGreen,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              AppStrings.settingPlayerName,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _nameController,
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: AppStrings.nicknameHint,
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              onSubmitted: (value) => controller.setPlayerName(value.trim()),
                              onEditingComplete: () =>
                                  controller.setPlayerName(_nameController.text.trim()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      GlowPanel(
                        glowColor: AppColors.neonMagenta,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              AppStrings.settingServerUrl,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Çok oyunculu modun bağlandığı gerçek zamanlı sunucu adresi.',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _serverController,
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: AppStrings.settingServerUrlHint,
                                prefixIcon: Icon(Icons.dns_rounded),
                              ),
                              keyboardType: TextInputType.url,
                              onSubmitted: (value) => controller.setServerUrl(value.trim()),
                              onEditingComplete: () =>
                                  controller.setServerUrl(_serverController.text.trim()),
                            ),
                          ],
                        ),
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

  Widget _switchTile({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.neonCyan, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}