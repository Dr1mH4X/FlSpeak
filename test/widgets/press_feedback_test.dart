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
  Widget wrapTheme(
    Brightness brightness,
    Widget child, {
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      theme: buildAppTheme(brightness),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        PrismUiLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      builder: (context, appChild) {
        Widget rooted = PrismRootScope(
          brightness: brightness,
          child: appChild!,
        );
        if (disableAnimations) {
          rooted = MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: rooted,
          );
        }
        return rooted;
      },
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('PressSurface in prism_ui buttons', () {
    testWidgets(
      'drives press tint on TextButton and FilledButton without ScaleTransition',
      (tester) async {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          await tester.pumpWidget(
            wrapTheme(
              brightness,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () {}, child: const Text('Press')),
                  FilledButton(onPressed: () {}, child: const Text('Fill')),
                ],
              ),
            ),
          );

          expect(
            find.descendant(
              of: find.byType(TextButton),
              matching: find.byType(ScaleTransition),
            ),
            findsNothing,
          );

          final textSurfaceFinder = find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(CardSurface),
          );
          expect(
            tester.widget<CardSurface>(textSurfaceFinder).look,
            PressLook.tint,
          );
          expect(
            tester.widget<CardSurface>(textSurfaceFinder).pressed.value,
            0.0,
          );

          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(TextButton)),
          );
          await tester.pump();
          expect(
            tester.widget<CardSurface>(textSurfaceFinder).pressed.value,
            1.0,
          );

          await gesture.up();
          await tester.pumpAndSettle();
          expect(
            tester.widget<CardSurface>(textSurfaceFinder).pressed.value,
            0.0,
          );

          final filledSurfaceFinder = find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CardSurface),
          );
          expect(
            tester.widget<CardSurface>(filledSurfaceFinder).look,
            PressLook.tint,
          );
          final fillGesture = await tester.startGesture(
            tester.getCenter(find.byType(FilledButton)),
          );
          await tester.pump();
          expect(
            tester.widget<CardSurface>(filledSurfaceFinder).pressed.value,
            1.0,
          );
          await fillGesture.up();
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets(
      'delays 150ms inside scrollable and clears immediately on scroll',
      (tester) async {
        await tester.pumpWidget(
          wrapTheme(
            Brightness.light,
            SizedBox(
              height: 200,
              child: ListView(
                children: [
                  SizedBox(
                    height: 80,
                    child: Center(
                      child: TextButton(
                        onPressed: () {},
                        child: const Text('InList'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        );

        final button = find.byType(TextButton);
        final cardSurface = find.descendant(
          of: button,
          matching: find.byType(CardSurface),
        );

        final gesture = await tester.startGesture(tester.getCenter(button));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.widget<CardSurface>(cardSurface).pressed.value, 0.0);

        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.widget<CardSurface>(cardSurface).pressed.value, 1.0);

        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        expect(tester.widget<CardSurface>(cardSurface).pressed.value, 0.0);

        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  });

  group('ElasticButton', () {
    testWidgets('sets PressLook.none across button types and triggers tap', (
      tester,
    ) async {
      var hits = 0;
      await tester.pumpWidget(
        wrapTheme(
          Brightness.light,
          ElasticButton(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => hits++,
                  child: const Text('Filled'),
                ),
                OutlinedButton(
                  onPressed: () => hits++,
                  child: const Text('Outlined'),
                ),
                TextButton(onPressed: () => hits++, child: const Text('Text')),
                IconButton(
                  onPressed: () => hits++,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      );

      for (final button in [
        find.byType(FilledButton),
        find.byType(OutlinedButton),
        find.byType(TextButton),
        find.byType(IconButton),
      ]) {
        final surface = tester.widget<CardSurface>(
          find.descendant(of: button, matching: find.byType(CardSurface)),
        );
        expect(surface.look, PressLook.none);
      }

      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.byType(OutlinedButton));
      await tester.tap(find.byType(TextButton));
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(hits, 4);
    });
  });

  group('AnimatedInkWell', () {
    testWidgets('uses PressSurface superellipse without InkWell ripples', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapTheme(
          Brightness.light,
          AnimatedInkWell(
            onTap: () => tapped = true,
            borderRadius: BorderRadius.circular(16),
            child: const SizedBox(width: 120, height: 48, child: Text('Row')),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      final surface = tester.widget<CardSurface>(
        find.descendant(
          of: find.byType(AnimatedInkWell),
          matching: find.byType(CardSurface),
        ),
      );
      expect(surface.shape, AppShape.md);
      expect(surface.look, PressLook.tint);

      await tester.tap(find.byType(AnimatedInkWell));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
