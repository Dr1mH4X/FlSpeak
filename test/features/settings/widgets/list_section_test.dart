// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        Checkbox,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/features/settings/widgets/setting_text_card.dart';
import 'package:flspeak/features/settings/widgets/settings_section.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

void main() {
  Widget wrapApp(Brightness brightness, Widget child) {
    return MaterialApp(
      theme: buildAppTheme(brightness),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        PrismUiLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      builder: (context, appChild) =>
          PrismRootScope(brightness: brightness, child: appChild!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('ListItem & generateSection / generateGroup', () {
    testWidgets(
      'generateSection renders ListHeader 36dp actions, dividers, and ListFooter',
      (tester) async {
        var actionHits = 0;
        var toggleValue = false;
        var checkValue = false;

        await tester.pumpWidget(
          wrapApp(
            Brightness.light,
            StatefulBuilder(
              builder: (context, setState) {
                return generateSection(
                  title: 'Section Title',
                  actions: [
                    TonalButton(label: 'Action', onPressed: () => actionHits++),
                  ],
                  footer: 'Helper footer copy',
                  items: [
                    ListItem.open(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('About item'),
                      onTap: () {},
                    ),
                    ListItem.toggle(
                      leading: const Icon(Icons.notifications_none_rounded),
                      title: const Text('Toggle item'),
                      value: toggleValue,
                      onChanged: (next) => setState(() => toggleValue = next),
                    ),
                    ListItem.checkbox(
                      title: const Text('Checkbox item'),
                      value: checkValue,
                      onChanged: (next) =>
                          setState(() => checkValue = next ?? false),
                    ),
                  ],
                );
              },
            ),
          ),
        );

        expect(find.byType(ListHeader), findsOneWidget);
        expect(find.byType(ListFooter), findsOneWidget);
        expect(find.text('Section Title'), findsOneWidget);
        expect(find.text('Helper footer copy'), findsOneWidget);

        expect(tester.getSize(find.byType(TonalButton)).height, 36);

        // Every ListRow has at least 48dp height.
        for (final box in tester.renderObjectList<RenderBox>(
          find.byType(ListRow),
        )) {
          expect(box.size.height, greaterThanOrEqualTo(48));
        }

        await tester.tap(find.text('Action'));
        await tester.tap(find.byType(Switch));
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();

        expect(actionHits, 1);
        expect(toggleValue, isTrue);
        expect(checkValue, isTrue);
      },
    );

    testWidgets(
      'invalid DecorationListItem skips adjacent dividers and uses errorContainer',
      (tester) async {
        final theme = buildAppTheme(Brightness.light);

        await tester.pumpWidget(
          wrapApp(
            Brightness.light,
            generateSection(
              items: const [
                DecorationListItem(title: Text('Valid above')),
                DecorationListItem(
                  invalid: true,
                  title: Text('Invalid middle'),
                ),
                DecorationListItem(title: Text('Valid below')),
              ],
            ),
          ),
        );

        final invalidSurface = tester.widget<CardSurface>(
          find
              .descendant(
                of: find.byType(DecorationListItem).at(1),
                matching: find.byType(CardSurface),
              )
              .first,
        );
        expect(invalidSurface.fill, theme.colorScheme.errorContainer);
      },
    );

    testWidgets('ListItem.options displays OptionsValueButton popup', (
      tester,
    ) async {
      var selected = 'a';

      await tester.pumpWidget(
        wrapApp(
          Brightness.light,
          StatefulBuilder(
            builder: (context, setState) {
              return generateSection(
                items: [
                  ListItem<String>.options(
                    title: const Text('Mode'),
                    options: const ['a', 'b'],
                    value: selected,
                    textBuilder: (v) => 'Option $v',
                    onChanged: (v) => setState(() => selected = v),
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(find.byType(OptionsValueButton), findsOneWidget);
      expect(find.text('Option a'), findsOneWidget);
    });
  });

  group('SettingsTile & SettingTextCard', () {
    testWidgets(
      'SettingsTile renders bare 24dp icon without secondaryContainer well',
      (tester) async {
        final theme = buildAppTheme(Brightness.dark);

        await tester.pumpWidget(
          wrapApp(
            Brightness.dark,
            generateSection(
              items: [
                SettingsTile(
                  icon: Icons.tune_rounded,
                  title: 'Tune',
                  onTap: () {},
                ),
              ],
            ),
          ),
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.tune_rounded));
        expect(icon.size, 24);
        expect(find.byType(PressSurface), findsOneWidget);

        final secondaryContainers = find.descendant(
          of: find.byType(SettingsTile),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    theme.colorScheme.secondaryContainer,
          ),
        );
        expect(secondaryContainers, findsNothing);
      },
    );

    testWidgets(
      'SettingTextCard highlights selected state with primary color',
      (tester) async {
        final theme = buildAppTheme(Brightness.light);
        var tapped = false;

        await tester.pumpWidget(
          wrapApp(
            Brightness.light,
            Row(
              children: [
                SettingTextCard(
                  'Selected',
                  isSelected: true,
                  onPressed: () => tapped = true,
                ),
                SettingTextCard('Idle', isSelected: false, onPressed: () {}),
              ],
            ),
          ),
        );

        final selectedMaterial = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SettingTextCard).first,
                matching: find.byType(Material),
              )
              .first,
        );
        expect(selectedMaterial.color, theme.colorScheme.primary);

        final selectedText = tester.widget<Text>(find.text('Selected'));
        expect(selectedText.style?.color, theme.colorScheme.onPrimary);

        await tester.tap(find.text('Selected'));
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
      },
    );

    testWidgets(
      'single-line SettingsTile, SettingsOptionsTile and Switch rows share equal height',
      (tester) async {
        await tester.pumpWidget(
          wrapApp(
            Brightness.light,
            SizedBox(
              width: 480,
              child: generateSection(
                items: [
                  SettingsTile(
                    icon: Icons.tune_rounded,
                    title: 'Plain Action',
                    onTap: () {},
                  ),
                  SettingsOptionsTile<String>(
                    icon: Icons.translate_rounded,
                    title: 'Popup Option',
                    options: const ['A', 'B'],
                    value: 'A',
                    textBuilder: (v) => v,
                    onChanged: (_) {},
                  ),
                  SettingsTile(
                    icon: Icons.update_rounded,
                    title: 'Switch Row',
                    trailing: Switch(value: true, onChanged: (_) {}),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );

        final heights = tester
            .renderObjectList<RenderBox>(find.byType(ListRow))
            .map((box) => box.size.height)
            .toList();
        expect(heights, hasLength(3));
        expect(heights[0], greaterThanOrEqualTo(48.0));
        expect(heights[1], heights[0]);
        expect(heights[2], heights[0]);
      },
    );

    testWidgets(
      'AnimatedInkWell uses PressSurface and Switch supports horizontal drag and LiquidGlass lens',
      (tester) async {
        var value = false;
        await tester.pumpWidget(
          wrapApp(
            Brightness.light,
            StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  AnimatedInkWell(
                    onTap: () {},
                    child: const SizedBox(width: 80, height: 48),
                  ),
                  Switch(
                    value: value,
                    onChanged: (next) => setState(() => value = next),
                  ),
                ],
              ),
            ),
          ),
        );

        final inkSurface = tester.widget<PressSurface>(
          find.byType(PressSurface),
        );
        expect(inkSurface.look, PressLook.tint);
        expect(find.byType(InkWell), findsNothing);

        expect(
          tester.getSize(find.byType(Switch)),
          const Size(Switch.trackWidth + 8, 48.0),
        );

        final switchFinder = find.byType(Switch);
        await tester.timedDrag(
          switchFinder,
          const Offset(36, 0),
          const Duration(milliseconds: 120),
        );
        await tester.pumpAndSettle();
        expect(value, isTrue);

        await tester.timedDrag(
          switchFinder,
          const Offset(-36, 0),
          const Duration(milliseconds: 120),
        );
        await tester.pumpAndSettle();
        expect(value, isFalse);
      },
    );

    testWidgets(
      'generateSection keeps grouped rows at SurfaceLevel.card with 24dp superellipse ends',
      (tester) async {
        for (final brightness in Brightness.values) {
          final theme = buildAppTheme(brightness);
          final pageColor = surfaceColorFor(
            SurfaceLevel.page,
            theme.colorScheme,
          );
          final cardColor = surfaceColorFor(
            SurfaceLevel.card,
            theme.colorScheme,
          );
          expect(cardColor, isNot(pageColor));

          await tester.pumpWidget(
            wrapApp(
              brightness,
              SurfaceScope(
                level: SurfaceLevel.page,
                child: generateSection(
                  items: [
                    SettingsTile(title: 'First', onTap: () {}),
                    SettingsTile(title: 'Last', onTap: () {}),
                  ],
                ),
              ),
            ),
          );

          expect(find.byType(SurfaceCard), findsNothing);
          final surfaces = tester
              .widgetList<CardSurface>(find.byType(CardSurface))
              .toList();
          expect(surfaces, hasLength(2));
          expect(surfaces[0].fill, cardColor);
          expect(surfaces[1].fill, cardColor);
          expect(
            surfaces[0].shape,
            AppShape.vertical(top: AppCorner.xl, bottom: AppCorner.none),
          );
          expect(
            surfaces[1].shape,
            AppShape.vertical(top: AppCorner.none, bottom: AppCorner.xl),
          );
        }
      },
    );
  });
}
