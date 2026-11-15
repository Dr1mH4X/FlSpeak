// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/features/settings/widgets/appearance_picker.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        Card,
        Divider,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AppearancePicker uses borderless unselected card surface, primary selected border, and diagonal split in light mode',
    (tester) async {
      AppThemePreference selected = AppThemePreference.dark;
      final theme = buildAppTheme(Brightness.light);
      final scheme = theme.colorScheme;
      final expectedCardColor = surfaceColorFor(SurfaceLevel.card, scheme);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: AppearancePicker(
                  value: selected,
                  onChanged: (mode) => setState(() => selected = mode),
                ),
              ),
            ),
          ),
        ),
      );

      final surfaces = tester
          .widgetList<PressSurface>(find.byType(PressSurface))
          .toList();
      expect(surfaces, hasLength(3));

      // First option (dark) is selected; light and system are unselected.
      expect(surfaces[0].fill, expectedCardColor);
      expect(surfaces[0].shape, AppShape.lg);
      expect(surfaces[0].side.color, scheme.primary);
      expect(surfaces[0].side.width, 2);

      expect(surfaces[1].fill, expectedCardColor);
      expect(surfaces[1].shape, AppShape.lg);
      expect(surfaces[1].side, BorderSide.none);

      expect(surfaces[2].fill, expectedCardColor);
      expect(surfaces[2].shape, AppShape.lg);
      expect(surfaces[2].side, BorderSide.none);

      // Inner miniature previews keep a hairline divider frame.
      final pickerContext = tester.element(find.byType(AppearancePicker));
      final previewBorders = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AppearancePicker),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.position == DecorationPosition.foreground &&
                    widget.decoration is ShapeDecoration &&
                    (widget.decoration as ShapeDecoration).shape
                        is RoundedSuperellipseBorder,
              ),
            ),
          )
          .toList();
      expect(previewBorders, hasLength(3));
      for (final borderBox in previewBorders) {
        final borderShape =
            (borderBox.decoration as ShapeDecoration).shape
                as RoundedSuperellipseBorder;
        expect(borderShape.side.color, dividerColorOf(pickerContext));
      }

      // System option uses a diagonal ClipPath split.
      expect(
        find.descendant(
          of: find.byWidget(surfaces[2]),
          matching: find.byType(ClipPath),
        ),
        findsOneWidget,
      );

      // Tapping light option updates selection.
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(selected, AppThemePreference.light);
    },
  );
}
