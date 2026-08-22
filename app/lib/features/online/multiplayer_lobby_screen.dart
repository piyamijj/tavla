import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/glow_panel.dart';
import '../../core/widgets/neon_button.dart';
import '../settings/settings_providers.dart';
import 'online_game_screen.dart';
import 'online_providers.dart';

/// Multiplayer entry point: collects a nickname, then either creates a new
/// room (sharing the resulting code with the opponent) or joins one by
/// code. Once the server reports `game_start`, this screen hands off to
/// [OnlineGameScreen].
class MultiplayerLobbyScreen extends ConsumerStatefulWidget {
  const MultiplayerLobbyScreen({super.key});

  @override
  ConsumerState<MultiplayerLobbyScreen> createState() => _MultiplayerLobbyScreenState();
}

class _MultiplayerLobbyScreenState extends ConsumerState<MultiplayerLobbyScreen> {
  final _nicknameController = TextEditingController();
  final _roomCodeController = TextEditingController();
  OnlineConfig? _activeConfig;
  bool _pushedGameScreen = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _nicknameController.text = settings.playerName.isNotEmpty
        ? settings.playerName
        : 'Oyuncu${100 + DateTime.now().millisecond % 900}';
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  String get _nickname => _nicknameController.text.trim().isEmpty
      ? 'Oyuncu'
      : _nicknameController.text.trim();

  void _ensureConnected() {
    final settings = ref.read(settingsProvider);
    final config = OnlineConfig(serverUrl: settings.serverUrl, nickname: _nickname);
    if (_activeConfig == null || _activeConfig != config) {
      setState(() {
        _activeConfig = config;
        _pushedGameScreen = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    if (_activeConfig == null) {
      return _buildEntryScaffold(settings, connecting: false);
    }

    final config = _activeConfig!;
    final onlineState = ref.watch(onlineGameControllerProvider(config));
    final controller = ref.read(onlineGameControllerProvider(config).notifier);

    ref.listen<OnlineState>(onlineGameControllerProvider(config), (previous, next) {
      if (next.status == ConnectionStatus.inMatch && !_pushedGameScreen) {
        _pushedGameScreen = true;
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => OnlineGameScreen(config: config),
              ),
            )
            .then((_) {
          _pushedGameScreen = false;
          controller.leaveRoom();
        });
      }
    });

    return _buildLobbyScaffold(context, onlineState, controller);
  }

  Widget _buildEntryScaffold(AppSettings settings, {required bool connecting}) {
    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text(AppStrings.multiplayerTitle),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: GlowPanel(
                        glowColor: AppColors.neonMagenta,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              AppStrings.yourNickname,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _nicknameController,
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: AppStrings.nicknameHint,
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              maxLength: 16,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${AppStrings.settingServerUrl}: ${settings.serverUrl}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                            ),
                            const SizedBox(height: 20),
                            NeonButton(
                              label: AppStrings.createRoom,
                              icon: Icons.add_circle_outline_rounded,
                              color: AppColors.neonCyan,
                              onPressed: _ensureConnected,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyScaffold(
    BuildContext context,
    OnlineState state,
    OnlineGameController controller,
  ) {
    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text(AppStrings.multiplayerTitle),
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () {
                    controller.leaveRoom();
                    setState(() => _activeConfig = null);
                  },
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildBodyForStatus(context, state, controller),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBodyForStatus(
    BuildContext context,
    OnlineState state,
    OnlineGameController controller,
  ) {
    switch (state.status) {
      case ConnectionStatus.disconnected:
      case ConnectionStatus.connecting:
        return GlowPanel(
          glowColor: AppColors.neonCyan,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.neonCyan),
              SizedBox(height: 14),
              Text(AppStrings.connecting, style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        );

      case ConnectionStatus.error:
        return GlowPanel(
          glowColor: AppColors.neonRed,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.neonRed, size: 32),
              const SizedBox(height: 10),
              Text(
                state.errorMessage ?? AppStrings.connectionFailed,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              NeonButton(
                label: AppStrings.retry,
                color: AppColors.neonRed,
                onPressed: () => setState(() => _activeConfig = null),
              ),
            ],
          ),
        );

      case ConnectionStatus.connected:
        return _buildRoomChoice(controller);

      case ConnectionStatus.waitingForOpponent:
        return _buildWaitingRoom(state, controller);

      case ConnectionStatus.inMatch:
        return const GlowPanel(
          glowColor: AppColors.neonGreen,
          child: Text(
            AppStrings.opponentJoined,
            style: TextStyle(color: AppColors.textPrimary),
          ),
        );
    }
  }

  Widget _buildRoomChoice(OnlineGameController controller) {
    return GlowPanel(
      glowColor: AppColors.neonMagenta,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NeonButton(
            label: AppStrings.createRoom,
            icon: Icons.add_circle_outline_rounded,
            color: AppColors.neonCyan,
            onPressed: controller.createRoom,
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 10),
          const Text(
            AppStrings.enterRoomCode,
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _roomCodeController,
            style: const TextStyle(
              color: AppColors.textPrimary,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              hintText: AppStrings.roomCodeHint,
              prefixIcon: Icon(Icons.tag_rounded),
            ),
          ),
          const SizedBox(height: 14),
          NeonButton(
            label: AppStrings.joinRoom,
            icon: Icons.login_rounded,
            color: AppColors.neonMagenta,
            onPressed: () => controller.joinRoom(_roomCodeController.text),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingRoom(OnlineState state, OnlineGameController controller) {
    return GlowPanel(
      glowColor: AppColors.neonCyan,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            AppStrings.shareRoomCode,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              if (state.roomCode == null) return;
              Clipboard.setData(ClipboardData(text: state.roomCode!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(AppStrings.copied)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.neonCyan.withOpacity(0.7), width: 1.4),
                boxShadow: AppColors.glow(AppColors.neonCyan, blur: 16, spread: 0.4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.roomCode ?? '------',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.copy_rounded, color: AppColors.neonCyan, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.neonCyan),
          ),
          const SizedBox(height: 12),
          const Text(
            AppStrings.waitingForOpponent,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () {
              controller.leaveRoom();
            },
            child: const Text(AppStrings.leaveRoom, style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }
}