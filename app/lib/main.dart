import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/constants/app_strings.dart';

void main() {
  runApp(const ProviderScope(child: CyberTavlaApp()));
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