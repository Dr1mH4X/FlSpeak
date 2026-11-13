// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

void main() {
  group('Surface hierarchy & dividers', () {
    testWidgets(
      'SurfaceScope and SurfaceCard shift levels down progressively',
      (tester) async {
        late SurfaceLevel outerLevel;
        late SurfaceLevel insideCardLevel;
        late SurfaceLevel raisedInCardLevel;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: Scaffold(
              body: SurfaceScope(
                level: SurfaceLevel.page,
                child: Builder(
                  builder: (context) {
                    outerLevel = SurfaceScope.of(context);
                    return SurfaceCard(
                      child: Builder(
                        builder: (cardContext) {
                          insideCardLevel = SurfaceScope.of(cardContext);
                          raisedInCardLevel = cardContext.raisedSurfaceLevel;
                          return const Text('Inside');
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        expect(outerLevel, SurfaceLevel.page);
        expect(insideCardLevel, SurfaceLevel.card);
        expect(raisedInCardLevel, SurfaceLevel.block);
        expect(SurfaceLevel.block.next, SurfaceLevel.inset);
        expect(SurfaceLevel.inset.next, SurfaceLevel.inset);
      },
    );

    testWidgets('SurfaceCard is borderless superellipse without card border', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.dark, child: child!),
          home: const Scaffold(body: SurfaceCard(child: Text('Borderless'))),
        ),
      );

      final decorated = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(SurfaceCard),
          matching: find.byType(DecoratedBox),
        ),
      );
      final shapeDecoration = decorated.decoration as ShapeDecoration;
      expect(shapeDecoration.shape, AppShape.xl);
    });

    testWidgets(
      'ElevatedSurfaceTheme lifts dark surfaces and keeps divider 14%',
      (tester) async {
        final baseTheme = buildAppTheme(Brightness.dark);
        late ColorScheme liftedScheme;
        late Color divider;

        await tester.pumpWidget(
          MaterialApp(
            theme: baseTheme,
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.dark, child: child!),
            home: ElevatedSurfaceTheme(
              child: Builder(
                builder: (context) {
                  liftedScheme = Theme.of(context).colorScheme;
                  divider = dividerColorOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(liftedScheme.surface, baseTheme.colorScheme.surfaceContainer);
        expect(
          liftedScheme.surfaceContainer,
          baseTheme.colorScheme.surfaceContainerHigh,
        );
        expect(divider.a, closeTo(0.14, 0.005));
      },
    );
  });

  group('Shapes & Typography', () {
    testWidgets('withAppShapes applies RoundedSuperellipseBorder to theme', (
      tester,
    ) async {
      final theme = buildAppTheme(Brightness.light);
      expect(theme.cardTheme.shape, isA<RoundedSuperellipseBorder>());
      expect(theme.dialogTheme.shape, isA<RoundedSuperellipseBorder>());
      expect(theme.dividerColor.a, closeTo(0.14, 0.005));
    });

    testWidgets(
      'AppTextStyle.of produces iOS Dynamic Type roles & emphasized',
      (tester) async {
        late TextStyle headline;
        late TextStyle emphasizedHeadline;
        late TextStyle body;
        late TextStyle footnote;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: Builder(
              builder: (context) {
                headline = AppTextStyle.headline.of(context);
                emphasizedHeadline = AppTextStyle.headline.of(
                  context,
                  emphasized: true,
                );
                body = AppTextStyle.body.of(context);
                footnote = AppTextStyle.footnote.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(headline.fontSize, 17);
        expect(emphasizedHeadline.fontWeight, FontWeight.w600);
        expect(body.fontSize, 17);
        expect(footnote.fontSize, 13);
      },
    );
  });

  group('TonalButton & TonalButtonGroup', () {
    testWidgets(
      'renders 36dp section TonalButton and TonalButtonGroup actions',
      (tester) async {
        var singleHits = 0;
        var groupHits = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TonalButton(
                    size: TonalButtonSize.section,
                    label: 'Add',
                    onPressed: () => singleHits++,
                  ),
                  const SizedBox(height: 12),
                  TonalButtonGroup(
                    size: TonalButtonSize.section,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          semanticLabel: 'Refresh',
                        ),
                        onPressed: () => groupHits++,
                      ),
                      FilledButton(
                        onPressed: () => groupHits++,
                        child: const Text('Export'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        final singleSize = tester.getSize(find.byType(TonalButton).first);
        expect(singleSize.height, 36);

        expect(find.byType(TonalButtonTheme), findsNWidgets(2));

        await tester.tap(find.text('Add'));
        await tester.tap(find.text('Export'));
        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await tester.pumpAndSettle();

        expect(singleHits, 1);
        expect(groupHits, 2);
      },
    );
  });
}
