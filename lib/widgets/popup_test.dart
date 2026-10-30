// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'popup.dart';

void main() {
  testWidgets('PopupValueText updates and displays provided text', (
    tester,
  ) async {
    final textNotifier = ValueNotifier('Option A');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: textNotifier,
            builder: (context, value, _) => PopupValueText(value),
          ),
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

  testWidgets('CommonPopupBox opens CommonPopupMenu and triggers onSelected', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CommonPopupBox(
              targetBuilder: (open) => ElevatedButton(
                onPressed: open,
                child: const Text('Open Menu'),
              ),
              popupBuilder: (context) => CommonPopupMenu(
                items: [
                  CommonPopupMenuItem(
                    label: 'Choice 1',
                    checked: selected == 'Choice 1',
                    onPressed: () {
                      selected = 'Choice 1';
                    },
                  ),
                  CommonPopupMenuItem(
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
      ),
    );
    await tester.pumpAndSettle();

    // Click to open popup
    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Choice 1'), findsOneWidget);
    expect(find.text('Choice 2'), findsOneWidget);

    // Tap Choice 2
    await tester.tap(find.text('Choice 2'));
    await tester.pumpAndSettle();

    expect(selected, 'Choice 2');
    expect(find.text('Choice 2'), findsNothing);
  });
}
