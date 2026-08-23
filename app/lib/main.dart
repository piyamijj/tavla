import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/constants/app_strings.dart';
import 'core/diagnostics/diagnostic_log.dart';
import 'features/online/online_providers.dart';
import 'features/settings/settings_providers.dart';

void main() {
  // Diagnostic hardening (see project history: a real device shows a
  // generic connection timeout with no server-side trace whatsoever,
  // reproducible identically on WiFi and mobile data, with no PC/adb
  // access available to investigate further). The `_lastErrorDetail`
  // shown in the connection error message only ever reflects what
  // socket_io_client's OWN `onConnectError`/`onError` callbacks report —
  // if the true underlying cause throws somewhere else entirely (a
  // Timer callback deep in a package's internals, any other spot not
  // wrapped in a local try/catch), it currently vanishes with zero
  // trace in a release build. `runZonedGuarded` + `FlutterError.onError`
  // catch both of those categories and record them in [DiagnosticLog],
  // which the connection-error UI then appends to its message — so the
  // device itself can surface a swallowed exception without adb.
  FlutterError.onError = (FlutterErrorDetails details) {
    DiagnosticLog.record(
      'flutter',
      details.exceptionAsString(),
      details.stack?.toString().split('\n').take(2).join(' / '),
    );
    FlutterError.presentError(details);
  };

  runZonedGuarded(_runApp, (Object error, StackTrace stack) {
    DiagnosticLog.record(
      'zone',
      error.toString(),
      stack.toString().split('\n').take(2).join(' / '),
    );
  });
}

void _runApp() {
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

  // NOTE: a custom HttpOverrides-based IP+SNI DNS fallback for this host
  // (PinnedDnsHttpOverrides) was tried here across several rounds to work
  // around a suspected on-device DNS block, but the exact same
  // `SocketException: Failed host lookup` kept recurring on the real
  // device even after fixing bugs found in that override — while the
  // phone's own browser resolves and reaches this same host instantly on
  // the same network at the same moment. That rules out an actual OS/ISP
  // DNS block and points at something in the app's own connection path
  // instead (quite possibly the override itself, despite the fixes).
  // Deliberately removed rather than patched again: this isolates the
  // variable so the next real-device test tells us, for the first time,
  // whether plain default DNS resolution (identical to what the browser
  // already proved works) resolves this on its own.

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