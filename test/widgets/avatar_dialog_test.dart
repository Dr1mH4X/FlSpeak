import 'dart:convert';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:material_ui/material_ui.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/identity/avatars.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/notices.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/member_details_pane.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/localization.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
  '/x8AAwMCAO+jS1sAAAAASUVORK5CYII=',
);

const _self = ClientView(
  id: 1,
  nickname: 'Self',
  uid: 'self-uid',
  channelId: 1,
);

class _Controller extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
    activeServerId: 'server-1',
    clients: [_self],
  );
}

class _FakeCore extends Fake implements CoreSession {
  Uint8List? avatar;
  Object? uploadError;
  int uploads = 0;
  int deletes = 0;
  Uint8List? uploadedBytes;

  @override
  Future<Uint8List?> fetchAvatar({required String uid}) async => avatar;

  @override
  Future<void> uploadAvatar({required List<int> bytes}) async {
    final error = uploadError;
    if (error != null) return Future<void>.error(error);
    uploads++;
    uploadedBytes = Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteAvatar() async {
    deletes++;
  }
}

class _FakeAvatarInput extends AvatarInput {
  const _FakeAvatarInput(this.result);

  final Future<Uint8List?> Function() result;

  @override
  Future<Uint8List?> pick() => result();
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required _FakeCore core,
  required AvatarInput input,
}) async {
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(core),
      sessionViewProvider.overrideWith(_Controller.new),
      avatarInputProvider.overrideWithValue(input),
      appLocalizationsProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('zh')),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
        home: const Scaffold(body: MemberDetailsPane(client: _self)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('管理头像'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('saving a picked image uploads it and closes the dialog', (
    tester,
  ) async {
    final core = _FakeCore();
    await _mount(tester, core: core, input: _FakeAvatarInput(() async => _png));

    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(core.uploads, 1);
    expect(core.uploadedBytes, _png);
    expect(find.text('头像'), findsNothing);
  });

  testWidgets(
    'delete removes the avatar and closes the dialog without confirmation',
    (tester) async {
      final core = _FakeCore()..avatar = _png;
      await _mount(
        tester,
        core: core,
        input: _FakeAvatarInput(() async => null),
      );

      await tester.tap(find.text('删除头像'));
      await tester.pumpAndSettle();

      expect(core.deletes, 1);
      expect(find.text('头像'), findsNothing);
    },
  );

  testWidgets('oversized picks are rejected before reading and reported', (
    tester,
  ) async {
    final core = _FakeCore();
    final container = await _mount(
      tester,
      core: core,
      input: const _FakeAvatarInput(_tooLarge),
    );

    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();

    expect(core.uploads, 0);
    expect(
      container.read(noticeCenterProvider).single.message,
      '所选图片过大，上限为 1.0 MiB。',
    );
  });

  testWidgets('avatar upload errors are localized and keep the dialog open', (
    tester,
  ) async {
    final core = _FakeCore()
      ..uploadError = const CoreError.avatarPermissionDenied();
    final container = await _mount(
      tester,
      core: core,
      input: _FakeAvatarInput(() async => _png),
    );

    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(core.uploads, 0);
    expect(find.text('头像'), findsOneWidget);
    expect(
      container.read(noticeCenterProvider).single.message,
      '你在该服务器不能更换头像。',
    );
  });
}

Future<Uint8List?> _tooLarge() async {
  throw const AvatarInputException(AvatarInputFailure.tooLarge);
}
