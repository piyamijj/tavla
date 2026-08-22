import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyber_tavla/core/constants/app_strings.dart';
import 'package:cyber_tavla/main.dart';

void main() {
  testWidgets('CyberTavlaApp renders the home screen with the main menu', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CyberTavlaApp()));
    await tester.pumpAndSettle();

    // The title/logo text is rendered inside a ShaderMask, so match by
    // widget text rather than requiring a single literal Text lookup.
    expect(find.textContaining(AppStrings.homeTitle), findsOneWidget);

    expect(find.text(AppStrings.menuSinglePlayer), findsOneWidget);
    expect(find.text(AppStrings.menuMultiplayer), findsOneWidget);
    expect(find.text(AppStrings.menuHowToPlay), findsOneWidget);
    expect(find.text(AppStrings.menuSettings), findsOneWidget);
  });
}