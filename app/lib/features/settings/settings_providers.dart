import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default realtime server URL used until the player configures their own
/// in Settings. Points at Piyami's own AWS EC2 instance (nginx + certbot
/// TLS termination, reverse-proxied to the Node process on port 3000 —
/// see AWS_DEPLOY_GUIDE.md) by default; change this (or override it from
/// the Settings screen) for local/dev testing against
/// `http://localhost:3000`. Render (`cyber-tavla-server.onrender.com`) was
/// the original host and is left running as a fallback but is no longer
/// the default.
const String kDefaultServerUrl = 'https://cytavla.duckdns.org';

const String _kKeySound = 'settings.sound';
const String _kKeyMusic = 'settings.music';
const String _kKeyVibration = 'settings.vibration';
const String _kKeyAnimationSpeed = 'settings.animationSpeed';
const String _kKeyPlayerName = 'settings.playerName';
const String _kKeyServerUrl = 'settings.serverUrl';

/// Relative animation speed multiplier for dice/checker animations.
/// 0.5 = slow, 1.0 = normal, 1.5 = fast.
enum AnimationSpeed {
  slow(0.6),
  normal(1.0),
  fast(1.6);

  final double multiplier;
  const AnimationSpeed(this.multiplier);

  static AnimationSpeed fromMultiplier(double value) {
    return AnimationSpeed.values.firstWhere(
      (s) => s.multiplier == value,
      orElse: () => AnimationSpeed.normal,
    );
  }
}

/// Immutable snapshot of all user-configurable app settings.
class AppSettings {
  final bool soundEnabled;
  final bool musicEnabled;
  final bool vibrationEnabled;
  final AnimationSpeed animationSpeed;
  final String playerName;
  final String serverUrl;

  const AppSettings({
    this.soundEnabled = true,
    this.musicEnabled = true,
    this.vibrationEnabled = true,
    this.animationSpeed = AnimationSpeed.normal,
    this.playerName = '',
    this.serverUrl = kDefaultServerUrl,
  });

  AppSettings copyWith({
    bool? soundEnabled,
    bool? musicEnabled,
    bool? vibrationEnabled,
    AnimationSpeed? animationSpeed,
    String? playerName,
    String? serverUrl,
  }) {
    return AppSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      playerName: playerName ?? this.playerName,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }
}

/// Loads, holds and persists [AppSettings] via `shared_preferences`. Every
/// mutator writes through to disk immediately so settings survive an app
/// restart without an explicit "save" step.
class SettingsController extends StateNotifier<AppSettings> {
  SettingsController() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      soundEnabled: prefs.getBool(_kKeySound) ?? true,
      musicEnabled: prefs.getBool(_kKeyMusic) ?? true,
      vibrationEnabled: prefs.getBool(_kKeyVibration) ?? true,
      animationSpeed: AnimationSpeed.fromMultiplier(
        prefs.getDouble(_kKeyAnimationSpeed) ?? AnimationSpeed.normal.multiplier,
      ),
      playerName: prefs.getString(_kKeyPlayerName) ?? '',
      serverUrl: prefs.getString(_kKeyServerUrl) ?? kDefaultServerUrl,
    );
  }

  Future<void> setSoundEnabled(bool value) async {
    state = state.copyWith(soundEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeySound, value);
  }

  Future<void> setMusicEnabled(bool value) async {
    state = state.copyWith(musicEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyMusic, value);
  }

  Future<void> setVibrationEnabled(bool value) async {
    state = state.copyWith(vibrationEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyVibration, value);
  }

  Future<void> setAnimationSpeed(AnimationSpeed value) async {
    state = state.copyWith(animationSpeed: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kKeyAnimationSpeed, value.multiplier);
  }

  Future<void> setPlayerName(String value) async {
    state = state.copyWith(playerName: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKeyPlayerName, value);
  }

  Future<void> setServerUrl(String value) async {
    state = state.copyWith(serverUrl: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKeyServerUrl, value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(),
);