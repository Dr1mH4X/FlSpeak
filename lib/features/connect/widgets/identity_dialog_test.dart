// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import 'identity_dialog.dart';

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

  testWidgets('打开身份管理弹窗展示当前身份与改名入口', (tester) async {
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

  testWidgets('未修改时点击完成直接关闭弹窗且不触发 onRename', (tester) async {
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

  testWidgets('编辑态下点击底部完成透传输入文本并关闭弹窗', (tester) async {
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

  testWidgets('编辑态下输入空字符串点击底部完成直接透传原始输入，前端不拦截报错', (tester) async {
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

  testWidgets('若先点击行内取消退出编辑态，再点击底部完成不触发提交', (tester) async {
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

  testWidgets('行内点击保存图标提交输入文本并退出编辑态', (tester) async {
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

  testWidgets('输入框软键盘完成/回车动作触发提交并退出编辑态', (tester) async {
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
