// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'theme_cross_fade.dart';

void main() {
  testWidgets(
    'ThemeCrossFade renders child and updates smoothly on theme change',
    (tester) async {
      final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, mode, child) {
            return MaterialApp(
              themeMode: mode,
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              home: ThemeCrossFade(
                child: Scaffold(
                  body: Center(
                    child: Text(
                      mode == ThemeMode.light ? 'Light Mode' : 'Dark Mode',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Light Mode'), findsOneWidget);

      themeModeNotifier.value = ThemeMode.dark;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Dark Mode'), findsOneWidget);
    },
  );
}
