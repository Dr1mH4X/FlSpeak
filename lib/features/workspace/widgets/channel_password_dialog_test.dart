// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../workspace_state.dart';
import 'channel_pane.dart';

class _Controller extends SessionController {
  bool bypass = false;
  final passwords = <String?>[];
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
    activeServerId: 'server',
    channels: [
      ChannelView(id: 1, parentId: 0, name: 'Home', description: ''),
      ChannelView(
        id: 2,
        parentId: 0,
        name: 'Locked',
        description: '',
        passwordProtected: true,
      ),
    ],
  );
  @override
  Future<bool> joinChannel(int channelId, {String? password}) async {
    passwords.add(password);
    if (!bypass && password != 'secret') {
      throw const CoreError.channelPasswordRequired(
        message: 'password required',
      );
    }
    state = state.copyWith(
      state: CoreSessionState.connected(clientId: 1, channelId: channelId),
    );
    return true;
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Controller controller,
) async {
  final container = ProviderContainer(
    overrides: [sessionViewProvider.overrideWith(() => controller)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChannelPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Locked'));
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tap(find.text('Locked'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'password prompt appears only after server refusal and supports correction',
    (tester) async {
      final controller = _Controller();
      final container = await _mount(tester, controller);
      expect(find.text('频道需要密码'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, '加入频道'));
      await tester.pumpAndSettle();
      expect(find.text('密码不正确，请重试'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'wrong',
      );
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, '加入频道'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(controller.passwords, [null, 'wrong', 'secret']);
      expect(container.read(activeChannelIdProvider), 2);
    },
  );
  testWidgets('authorized password bypass does not open the prompt', (
    tester,
  ) async {
    final controller = _Controller()..bypass = true;
    final container = await _mount(tester, controller);
    expect(controller.passwords, [null]);
    expect(find.text('频道需要密码'), findsNothing);
    expect(container.read(activeChannelIdProvider), 2);
  });
  testWidgets('cancelling password entry restores previous channel selection', (
    tester,
  ) async {
    final container = await _mount(tester, _Controller());
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(container.read(activeChannelIdProvider), 1);
  });
}
