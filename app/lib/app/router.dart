import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';

/// Top-level named route identifiers.
///
/// Only routes with no constructor arguments (or ones that can be safely
/// defaulted) are registered by name here. Feature screens that need rich,
/// typed configuration — the local game screen (`GameConfig`), the bot
/// setup flow, etc. — are pushed directly via `MaterialPageRoute` from
/// within the screen that creates their configuration, so that
/// configuration stays strongly typed instead of
/// being packed into a loosely-typed route arguments map.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
}

/// Generates routes for [AppRoutes]'s named destinations. Passed straight
/// into `MaterialApp.onGenerateRoute`.
Route<dynamic> onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.home:
    default:
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const HomeScreen(),
      );
  }
}