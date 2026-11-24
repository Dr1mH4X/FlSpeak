import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:material_ui/material_ui.dart' hide TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/localization.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/monogram.dart';
import 'package:flspeak/widgets/prism.dart' show TextField;
import 'package:flspeak/features/connect/widgets/identity_dialog.dart';

class _FakeCore extends Fake implements CoreSession {
  @override
  Stream<CoreEvent> events() => const Stream.empty();

  @override
  Future<Uint8List?> fetchAvatar({required String uid}) async => null;
}

class _AvatarSession extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'server-1',
    clients: [
      ClientView(id: 1, nickname: 'Self', uid: 'self-uid', channelId: 5),
    ],
  );
}

final _previewAvatar = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
]);

void main() {
  Widget buildTestWidget({
    required String nickname,
    required ValueChanged<String> onRename,
    Uint8List? avatarBytes,
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showIdentityDialog(
              context,
              nickname: nickname,
              onRename: onRename,
              avatarBytes: avatarBytes,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'the identity dialog shows the current identity and rename entry',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(nickname: 'FlSpeakUser', onRename: (_) {}),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('身份'), findsOneWidget);
      expect(find.text('FlSpeakUser'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    },
  );

  testWidgets('disconnected identity dialog shows the cached snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        nickname: 'FlSpeakUser',
        onRename: (_) {},
        avatarBytes: _previewAvatar,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final avatar = tester.widget<IdentityAvatar>(find.byType(IdentityAvatar));
    expect(avatar.image, _previewAvatar);
    expect(
      find.bySemanticsLabel(
        lookupAppLocalizations(const Locale('zh')).avatarManage,
      ),
      findsNothing,
    );
  });

  testWidgets(
    'submitting without changes closes the dialog without calling onRename',
    (tester) async {
      var renamed = false;
      await tester.pumpWidget(
        buildTestWidget(
          nickname: 'FlSpeakUser',
          onRename: (_) => renamed = true,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(find.text('身份'), findsNothing);
      expect(renamed, isFalse);
    },
  );

  testWidgets(
    'submitting in edit mode passes the input text and closes the dialog',
    (tester) async {
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
    },
  );

  testWidgets(
    'submitting an empty string in edit mode passes the original input without client-side validation',
    (tester) async {
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
    },
  );

  testWidgets(
    'leaving edit mode with the inline cancel then submitting does not trigger a rename',
    (tester) async {
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
    },
  );

  testWidgets(
    'the inline save icon submits the input text and exits edit mode',
    (tester) async {
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
    },
  );

  testWidgets('the keyboard done or enter action submits and exits edit mode', (
    tester,
  ) async {
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

  testWidgets('identity dialog avatar opens the avatar dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_AvatarSession.new),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showIdentityDialog(
                  context,
                  nickname: 'FlSpeakUser',
                  onRename: (_) {},
                  avatarUid: 'self-uid',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('管理头像'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('管理头像'));
    await tester.pumpAndSettle();

    expect(find.text('头像'), findsOneWidget);
    expect(find.text('选择图片'), findsOneWidget);
  });
}
