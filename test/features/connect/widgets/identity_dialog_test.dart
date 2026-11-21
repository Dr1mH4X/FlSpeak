// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart' show TextField;
import 'package:flspeak/features/connect/widgets/identity_dialog.dart';

void main() {
  Widget buildTestWidget({
    required String nickname,
    required ValueChanged<String> onRename,
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showIdentityDialog(
              context,
              nickname: nickname,
              onRename: onRename,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  testWidgets('the identity dialog shows the current identity and rename entry', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(nickname: 'FlSpeakUser', onRename: (_) {}),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('身份'), findsOneWidget);
    expect(find.text('FlSpeakUser'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('submitting without changes closes the dialog without calling onRename', (tester) async {
    var renamed = false;
    await tester.pumpWidget(
      buildTestWidget(nickname: 'FlSpeakUser', onRename: (_) => renamed = true),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('身份'), findsNothing);
    expect(renamed, isFalse);
  });

  testWidgets('submitting in edit mode passes the input text and closes the dialog', (tester) async {
    String? updated;
    await tester.pumpWidget(
      buildTestWidget(
        nickname: 'FlSpeakUser',
        onRename: (val) => updated = val,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 点击铅笔进入编辑模式
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    expect(inputFinder, findsOneWidget);

    // 输入新昵称
    await tester.enterText(inputFinder, 'NewName');
    await tester.pumpAndSettle();

    // 点击底部的完成按钮
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(updated, equals('NewName'));
    expect(find.text('身份'), findsNothing);
  });

  testWidgets('submitting an empty string in edit mode passes the original input without client-side validation', (tester) async {
    String? updated;
    await tester.pumpWidget(
      buildTestWidget(
        nickname: 'FlSpeakUser',
        onRename: (val) => updated = val,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, '');
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(updated, equals(''));
    expect(find.text('身份'), findsNothing);
  });

  testWidgets('leaving edit mode with the inline cancel then submitting does not trigger a rename', (tester) async {
    String? updated;
    await tester.pumpWidget(
      buildTestWidget(
        nickname: 'FlSpeakUser',
        onRename: (val) => updated = val,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, 'DiscardedName');
    await tester.pumpAndSettle();

    // 点击行内取消 (close_rounded / semanticLabel: 取消)
    await tester.tap(find.bySemanticsLabel('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('FlSpeakUser'), findsOneWidget);

    // 点击完成关闭弹窗
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('身份'), findsNothing);
    expect(updated, isNull);
  });

  testWidgets('the inline save icon submits the input text and exits edit mode', (tester) async {
    String? updated;
    await tester.pumpWidget(
      buildTestWidget(
        nickname: 'FlSpeakUser',
        onRename: (val) => updated = val,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, 'SavedViaCheck');
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('保存'));
    await tester.pumpAndSettle();

    expect(updated, equals('SavedViaCheck'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('SavedViaCheck'), findsOneWidget);

    // 点击完成关闭
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('身份'), findsNothing);
  });

  testWidgets('the keyboard done or enter action submits and exits edit mode', (tester) async {
    String? updated;
    await tester.pumpWidget(
      buildTestWidget(
        nickname: 'FlSpeakUser',
        onRename: (val) => updated = val,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, 'SubmittedViaEnter');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(updated, equals('SubmittedViaEnter'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('SubmittedViaEnter'), findsOneWidget);
  });
}
