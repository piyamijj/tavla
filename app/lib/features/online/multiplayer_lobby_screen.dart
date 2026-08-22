import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/glow_panel.dart';
import '../../core/widgets/neon_button.dart';
import '../settings/settings_providers.dart';
import 'online_game_screen.dart';
import 'online_models.dart';
import 'online_providers.dart';

/// Multiplayer lobby: shows who else is currently idle and challengeable
/// (tap a name to start an instant match), or falls back to the manual
/// create-a-room/share-the-code/join-by-code flow. The underlying
/// connection (see [onlineGameControllerProvider]) is opened in the
/// background as soon as the app launches — by the time this screen
/// opens it should already be connected, so this screen's only job is to
/// mark the player idle/challengeable ([OnlineGameController.enterLobby])
/// and render whatever [ConnectionStatus] it finds. Once the server
/// reports `game_start`, this screen hands off to [OnlineGameScreen].
class MultiplayerLobbyScreen extends ConsumerStatefulWidget {
  const MultiplayerLobbyScreen({super.key});

  @override
  ConsumerState<MultiplayerLobbyScreen> createState() => _MultiplayerLobbyScreenState();
}

class _MultiplayerLobbyScreenState extends ConsumerState<MultiplayerLobbyScreen> {
  final _nicknameController = TextEditingController();
  final _roomCodeController = TextEditingController();
  bool _pushedGameScreen = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _nicknameController.text = settings.playerName.isNotEmpty
        ? settings.playerName
        : 'Oyuncu${100 + DateTime.now().millisecond % 900}';

    final controller = ref.read(onlineGameControllerProvider.notifier);
    controller.setNickname(_nicknameController.text);
    controller.enterLobby();
  }

  @override
  void dispose() {
    // Only reachable when the player actually navigates away from the
    // multiplayer feature entirely (pushing OnlineGameScreen on top of
    // this one keeps it mounted underneath, so this does NOT fire just
    // from starting a match) — stop showing up in others' challenge
    // lists.
    ref.read(onlineGameControllerProvider.notifier).leaveLobby();
    _nicknameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  String get _nickname => _nicknameController.text.trim().isEmpty
      ? 'Oyuncu'
      : _nicknameController.text.trim();

  void _applyNickname() {
    ref.read(onlineGameControllerProvider.notifier)
      ..setNickname(_nickname)
      ..enterLobby();
  }

  @override
  Widget build(BuildContext context) {
    final onlineState = ref.watch(onlineGameControllerProvider);
    final controller = ref.read(onlineGameControllerProvider.notifier);

    ref.listen<OnlineState>(onlineGameControllerProvider, (previous, next) {
      if (next.status == ConnectionStatus.inMatch && !_pushedGameScreen) {
        _pushedGameScreen = true;
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => const OnlineGameScreen(),
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
                    if (state.status == ConnectionStatus.waitingForOpponent) {
                      controller.leaveRoom();
                    }
                    Navigator.of(context).pop();
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.neonCyan),
              const SizedBox(height: 14),
              Text(
                state.connectingHint ?? AppStrings.connecting,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
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
                onPressed: controller.retryConnect,
              ),
            ],
          ),
        );

      case ConnectionStatus.connected:
        return _buildRoomChoice(state, controller);

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

  Widget _buildRoomChoice(OnlineState state, OnlineGameController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlowPanel(
          glowColor: AppColors.neonCyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                AppStrings.yourNickname,
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
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
                onSubmitted: (_) => _applyNickname(),
                onEditingComplete: _applyNickname,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlowPanel(
          glowColor: AppColors.neonMagenta,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.waitingRooms != null) ...[
                _WaitingPlayersBadge(waitingRooms: state.waitingRooms!),
                const SizedBox(height: 14),
              ],
              Text(
                AppStrings.idlePlayersTitle,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _IdlePlayersList(
                players: state.idlePlayers,
                onChallenge: controller.challengePlayer,
              ),
              const SizedBox(height: 18),
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
        ),
      ],
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

/// Small pill showing how many rooms are currently open and waiting for a
/// second player, server-wide — gives the lobby screen real visibility
/// into current activity instead of a silent connect-then-match flow.
class _WaitingPlayersBadge extends StatelessWidget {
  const _WaitingPlayersBadge({required this.waitingRooms});

  final int waitingRooms;

  @override
  Widget build(BuildContext context) {
    final label = waitingRooms > 0
        ? '$waitingRooms ${AppStrings.playersWaitingSuffix}'
        : AppStrings.noOneWaiting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.neonCyan.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.neonCyan.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            waitingRooms > 0 ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
            color: AppColors.neonCyan,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.neonCyan, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The actual list of other idle players the user can tap to challenge
/// directly, instead of the manual create/share-code/join dance — each
/// row is a nickname plus a one-tap "Meydan Oku" (Challenge) action.
class _IdlePlayersList extends StatelessWidget {
  const _IdlePlayersList({required this.players, required this.onChallenge});

  final List<LobbyPlayer> players;
  final void Function(LobbyPlayer player) onChallenge;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          AppStrings.noIdlePlayers,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
      );
    }

    return Column(
      children: [
        for (final player in players) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neonGreen.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, color: AppColors.neonGreen, size: 9),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    player.nickname,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => onChallenge(player),
                  child: const Text(
                    AppStrings.challengeButton,
                    style: TextStyle(color: AppColors.neonMagenta, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}