import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/constants/app_strings.dart';
import 'core/network/pinned_dns_http_overrides.dart';
import 'features/online/online_providers.dart';
import 'features/settings/settings_providers.dart';

void main() {
  // Must be the very first call: everything below (the ProviderContainer
  // read, which eagerly constructs SettingsController and calls
  // SharedPreferences.getInstance() — a platform-channel round trip) runs
  // before `runApp()` would otherwise initialize the widgets binding.
  // Without this, that platform-channel call fires before the engine has
  // a binary messenger attached to route its response back through. In
  // debug mode Flutter's own asserts happen to catch this early and fail
  // loudly; in a release APK asserts are stripped out, so the call can
  // simply never resolve — a silent, permanent hang with no exception and
  // no visible cause, exactly the kind of "stuck forever, no error"
  // regression introduced by moving provider reads into main() for
  // eager auto-connect.
  WidgetsFlutterBinding.ensureInitialized();

  // Some devices cannot resolve the realtime server's hostname at all —
  // a Private DNS setting, an ad-block/VPN app, or a carrier/device DNS
  // filter can silently blocklist a domain (dynamic-DNS domains like
  // *.duckdns.org are a common target) before any network request is
  // even attempted, surfacing as `SocketException: Failed host lookup`.
  // This installs a last-resort fallback — see PinnedDnsHttpOverrides —
  // that only kicks in when normal DNS for this specific host fails; it
  // never overrides a working resolution and never touches any other
  // hostname.
  HttpOverrides.global = PinnedDnsHttpOverrides({
    Uri.parse(kDefaultServerUrl).host: '13.53.56.176',
  });

  // Built explicitly (instead of just wrapping the app in a bare
  // `ProviderScope`) so the multiplayer connection can be kicked off
  // right here, once, as part of app bootstrap — this is what makes the
  // socket already connecting in the background by the time the player
  // opens the multiplayer screen, instead of only starting on that
  // screen's first build. Deliberately done in `main()` rather than in
  // `CyberTavlaApp.build()`: a widget test builds its own fresh
  // `ProviderScope(child: CyberTavlaApp())` without going through this
  // `main()` at all, so real network activity never leaks into a widget
  // test that has nothing to do with multiplayer.
  final container = ProviderContainer();
  container.read(onlineGameControllerProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CyberTavlaApp(),
    ),
  );
}

/// App root: sets up the cyber/neon dark theme and the top-level router,
/// starting at the main menu (`AppRoutes.home`).
class CyberTavlaApp extends StatelessWidget {
  const CyberTavlaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      initialRoute: AppRoutes.home,
      onGenerateRoute: onGenerateRoute,
    );
  }
}