// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        PopupMenuItem,
        Switch,
        TextButton;
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

void main() {
  Widget wrapPopupApp(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        PrismUiLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      builder: (context, appChild) {
        Widget rooted = PrismRootScope(
          brightness: Brightness.light,
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
      home: Scaffold(body: child),
    );
  }

  testWidgets('PopupValueText updates and displays provided text', (
    tester,
  ) async {
    final textNotifier = ValueNotifier('Option A');
    await tester.pumpWidget(
      wrapPopupApp(
        ValueListenableBuilder<String>(
          valueListenable: textNotifier,
          builder: (context, value, _) => PopupValueText(value),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Option A'), findsOneWidget);

    textNotifier.value = 'Option B';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Option B'), findsOneWidget);
  });

  testWidgets('PopupAnchor opens PopupMenu and triggers onPressed', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      wrapPopupApp(
        Center(
          child: PopupAnchor(
            targetBuilder: (open) =>
                FilledButton(onPressed: open, child: const Text('Open Menu')),
            popupBuilder: (context) => PopupMenu(
              items: [
                PopupMenuItem(
                  label: 'Choice 1',
                  checked: selected == 'Choice 1',
                  onPressed: () {
                    selected = 'Choice 1';
                  },
                ),
                PopupMenuItem(
                  label: 'Choice 2',
                  checked: selected == 'Choice 2',
                  onPressed: () {
                    selected = 'Choice 2';
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Choice 1'), findsOneWidget);
    expect(find.text('Choice 2'), findsOneWidget);

    await tester.tap(find.text('Choice 2'));
    await tester.pumpAndSettle();

    expect(selected, 'Choice 2');
    expect(find.text('Choice 2'), findsNothing);
  });

  testWidgets('PopupAnchor with disableAnimations settles menu cleanly', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      wrapPopupApp(
        disableAnimations: true,
        Center(
          child: PopupAnchor(
            targetBuilder: (open) => FilledButton(
              onPressed: open,
              child: const Text('Open Reduced'),
            ),
            popupBuilder: (context) => PopupMenu(
              items: [
                PopupMenuItem(
                  label: 'Item 1',
                  checked: selected == 'Item 1',
                  onPressed: () {
                    selected = 'Item 1';
                  },
                ),
                PopupMenuItem(
                  label: 'Item 2',
                  checked: selected == 'Item 2',
                  onPressed: () {
                    selected = 'Item 2';
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Reduced'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);

    await tester.tap(find.text('Item 2'));
    await tester.pumpAndSettle();

    expect(selected, 'Item 2');
    expect(find.text('Item 2'), findsNothing);
  });
}
