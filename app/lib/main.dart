import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/constants/app_strings.dart';
import 'features/online/online_providers.dart';

void main() {
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