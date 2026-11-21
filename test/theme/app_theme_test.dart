// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;

import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart' show SurfaceLevel;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppTheme icon and button colors', () {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      testWidgets(
        'iconTheme and iconButtonTheme in $brightness are properly tinted',
        (tester) async {
          final theme = buildAppTheme(brightness);
          final scheme = theme.colorScheme;

          expect(theme.iconTheme.size, IconSizes.toolbar);
          expect(theme.iconTheme.color, scheme.onSurface);
          expect(
            theme.inputDecorationTheme.prefixIconColor,
            scheme.onSurfaceVariant,
          );
          expect(
            theme.inputDecorationTheme.suffixIconColor,
            scheme.onSurfaceVariant,
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Column(
                  children: [
                    const Icon(Icons.star_rounded),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.call_end_rounded),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.chat_bubble_rounded),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    const IconButton(
                      onPressed: null,
                      icon: Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          );

          final starColor = IconTheme.of(
            tester.element(find.byIcon(Icons.star_rounded)),
          ).color;
          final callColor = IconTheme.of(
            tester.element(find.byIcon(Icons.call_end_rounded)),
          ).color;
          final scopeColor = IconTheme.of(
            tester.element(find.byIcon(Icons.chat_bubble_rounded)),
          ).color;
          final mediaColor = IconTheme.of(
            tester.element(find.byIcon(Icons.add_photo_alternate_outlined)),
          ).color;
          final disabledColor = IconTheme.of(
            tester.element(find.byIcon(Icons.send_rounded)),
          ).color;

          expect(starColor, scheme.onSurface);
          expect(callColor, scheme.onSurfaceVariant);
          expect(scopeColor, scheme.onSurfaceVariant);
          expect(mediaColor, scheme.onSurfaceVariant);
          expect(disabledColor, scheme.onSurface.withValues(alpha: 0.38));

          // Ensure none of the icons in dark mode erroneously collapsed to solid black.
          if (brightness == Brightness.dark) {
            expect(starColor, isNot(Colors.black));
            expect(callColor, isNot(Colors.black));
            expect(scopeColor, isNot(Colors.black));
            expect(mediaColor, isNot(Colors.black));
          }
        },
      );
    }

    for (final brightness in [Brightness.dark, Brightness.light]) {
      test(
        'outline border tokens meet >= 3:1 UI boundary contrast in $brightness',
        () {
          final theme = buildAppTheme(brightness);
          final scheme = theme.colorScheme;
          final pageColor = surfaceColorFor(SurfaceLevel.page, scheme);
          final cardColor = surfaceColorFor(SurfaceLevel.card, scheme);

          expect(
            _contrastRatio(scheme.outline, pageColor),
            greaterThanOrEqualTo(3.0),
          );
          expect(
            _contrastRatio(scheme.outline, cardColor),
            greaterThanOrEqualTo(3.0),
          );

          final inputBorder =
              theme.inputDecorationTheme.border as AppInputBorder;
          final enabledInputBorder =
              theme.inputDecorationTheme.enabledBorder as AppInputBorder;
          expect(inputBorder.borderSide.color, scheme.outline);
          expect(enabledInputBorder.borderSide.color, scheme.outline);

          final outlinedSide = theme.outlinedButtonTheme.style?.side?.resolve(
            const {},
          );
          expect(outlinedSide?.color, scheme.outline);
        },
      );
    }
  });
}
