// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        PopupMenuItem,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/features/workspace/widgets/client_actions.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

const _peer = ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 5);

class _Controller extends SessionController {
  final calls =
      <
        ({
          String uid,
          int id,
          int channel,
          KickTarget target,
          String reason,
          int epoch,
        })
      >[];
  Completer<bool>? pending;
  @override
  SessionView build() => const SessionView(
    activeServerId: 'server',
    connectionEpoch: 3,
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    clients: [_peer],
  );
  @override
  Future<bool> kickClient(
    ClientView client,
    KickTarget target,
    String reason,
    int connectionEpoch,
  ) {
    calls.add((
      uid: client.uid,
      id: client.id,
      channel: client.channelId,
      target: target,
      reason: reason,
      epoch: connectionEpoch,
    ));
    pending = Completer<bool>();
    return pending!.future;
  }

  void replacePeerConnection() => state = state.copyWith(
    clients: [
      const ClientView(id: 3, nickname: 'Peer', uid: 'peer', channelId: 5),
    ],
  );

  void reconnect() => state = state.copyWith(connectionEpoch: 4);
  void movePeer() => state = state.copyWith(
    clients: [
      const ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 9),
    ],
  );
}

class _Access {
  _Access(this.channel, this.server);
  int channel;
  int server;
}

Future<void> _openActionsMenu(WidgetTester tester) async {
  final more = find.byWidgetPredicate(
    (w) => w is GlyphIcon && w.glyph == Glyphs.more,
  );
  if (more.evaluate().isNotEmpty) {
    await tester.tap(more);
  } else {
    await tester.tap(
      find.byType(ClientActionsButton),
      buttons: kSecondaryButton,
    );
  }
  await tester.pumpAndSettle();
}

Future<({ProviderContainer container, _Controller controller, _Access access})>
_mount(
  WidgetTester tester, {
  int channel = 50,
  int server = 50,
  Locale locale = const Locale('zh'),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final controller = _Controller();
  final access = _Access(channel, server);
  final container = ProviderContainer(
    overrides: [
      sessionViewProvider.overrideWith(() => controller),
      sessionAccessProvider.overrideWith(
        (ref) async => AccessView(
          kickChannelPower: access.channel,
          kickServerPower: access.server,
          connectionEpoch: 42,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: PrismRootScope(brightness: Brightness.light, child: child!),
        ),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          PrismUiLocalizationsDelegate(),
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ClientActionsButton(
            client: _peer,
            child: SizedBox(width: 120, height: 40),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _openActionsMenu(tester);
  return (container: container, controller: controller, access: access);
}

void main() {
  testWidgets('kick confirmation fits a small screen with large English text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
      tester,
      locale: const Locale('en'),
      textScaler: const TextScaler.linear(2),
    );
    await tester.tap(find.text('Kick from server'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Confirm kick'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary users have both kick actions disabled; channel permission does not grant server kicks',
    (tester) async {
      final context = await _mount(tester, channel: 0, server: 0);
      PopupMenuItem menu(String label) => tester
          .widget<PopupMenu>(find.byType(PopupMenu))
          .items
          .firstWhere((item) => item.label == label);
      expect(menu('踢出频道').onPressed, isNull);
      expect(menu('踢出服务器').onPressed, isNull);
      context.access.channel = 50;
      context.container.invalidate(sessionAccessProvider);
      await tester.pumpAndSettle();
      // 菜单弹窗已按旧权限快照打开；关闭并重开以验证最新权限生效。
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await _openActionsMenu(tester);
      await tester.tap(find.text('踢出频道'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '确认踢出'), findsOneWidget);
    },
  );

  testWidgets(
    'server kick requires confirmation, prevents duplicates and retains reason after refusal',
    (tester) async {
      final context = await _mount(tester);
      await tester.tap(find.text('踢出服务器'));
      await tester.pumpAndSettle();
      expect(context.controller.calls, isEmpty);
      await tester.enterText(find.byType(TextField), 'reason | 测试');
      await tester.tap(find.widgetWithText(FilledButton, '确认踢出'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认踢出'))
            .onPressed,
        isNull,
      );
      expect(context.controller.calls.single, (
        uid: 'peer',
        id: 2,
        channel: 5,
        target: KickTarget.server,
        reason: 'reason | 测试',
        epoch: 42,
      ));
      context.controller.pending!.complete(false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'reason | 测试',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认踢出'));
      await tester.pump();
      context.controller.pending!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(context.controller.calls, hasLength(2));
    },
  );

  testWidgets('cancel makes no request; channel kick allows an empty reason', (
    tester,
  ) async {
    final context = await _mount(tester);
    await tester.tap(find.text('踢出频道'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(context.controller.calls, isEmpty);
    await _openActionsMenu(tester);
    await tester.tap(find.text('踢出频道'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认踢出'));
    await tester.pump();
    expect(context.controller.calls.single.target, KickTarget.channel);
    expect(context.controller.calls.single.reason, '');
    context.controller.pending!.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('reconnect invalidates an open confirmation', (tester) async {
    final context = await _mount(tester);
    await tester.tap(find.text('踢出服务器'));
    await tester.pumpAndSettle();
    context.controller.reconnect();
    await tester.pumpAndSettle();
    expect(find.text('连接已变化，请关闭后重新操作'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认踢出'))
          .onPressed,
      isNull,
    );
    expect(context.controller.calls, isEmpty);
  });

  testWidgets(
    'channel move and permission revocation disable a pending confirmation',
    (tester) async {
      final context = await _mount(tester);
      await tester.tap(find.text('踢出频道'));
      await tester.pumpAndSettle();
      context.access.channel = 0;
      context.container.invalidate(sessionAccessProvider);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认踢出'))
            .onPressed,
        isNull,
      );
      context.access.channel = 50;
      context.container.invalidate(sessionAccessProvider);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认踢出'))
            .onPressed,
        isNotNull,
      );
      context.controller.movePeer();
      await tester.pumpAndSettle();
      expect(find.text('成员已离线或更换频道，请重新选择'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认踢出'))
            .onPressed,
        isNull,
      );
      expect(context.controller.calls, isEmpty);
    },
  );
}
