// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'core/providers.dart';
import 'features/connect/connect_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/widgets/settings_section.dart';
import 'features/workspace/workspace_page.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  _Session([this._initial = const SessionView()]);
  final SessionView _initial;

  @override
  SessionView build() => _initial;
}

Future<GoRouter> _mount(
  WidgetTester tester, {
  bool reduceMotion = false,
  SessionView sessionView = const SessionView(),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_Core()),
      sessionViewProvider.overrideWith(() => _Session(sessionView)),
      storePathProvider.overrideWithValue('/tmp/flspeak-test/preferences.json'),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('SDK MaterialApp 的设置导航在进入和返回时均有中间帧', (tester) async {
    final router = await _mount(tester);
    unawaited(router.push<void>(AppRoutes.settings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final route = ModalRoute.of(tester.element(find.byType(SettingsPage)))!;
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('减少动态效果时导航直接显示最终内容', (tester) async {
    final router = await _mount(tester, reduceMotion: true);
    unawaited(router.push<void>(AppRoutes.settings));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(SettingsPage)))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.animation!.value, 1);
  });

  testWidgets('从连接页侧栏进入设置后，一级菜单点击返回能回到连接页而非连接丢失页', (tester) async {
    await _mount(tester);
    expect(find.byType(ConnectPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('连接丢失'), findsNothing);
  });

  testWidgets('从连接页进入设置后，按 ESC 键也能直接退回连接页', (tester) async {
    await _mount(tester);
    expect(find.byType(ConnectPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ConnectPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('连接丢失'), findsNothing);
  });

  testWidgets('从工作区进入设置，一级菜单点击返回能回到工作区', (tester) async {
    const connectedView = SessionView(
      state: CoreSessionState.connected(clientId: 1, channelId: 5),
      activeServerId: 'server-1',
      servers: [
        ServerProfileView(
          id: 'server-1',
          label: 'Test Server',
          host: '127.0.0.1',
          port: 9987,
        ),
      ],
      channels: [
        ChannelView(id: 5, parentId: 0, name: 'Default', description: ''),
      ],
    );
    final router = await _mount(tester, sessionView: connectedView);
    router.go(AppRoutes.workspace);
    await tester.pumpAndSettle();
    expect(find.byType(WorkspacePage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(WorkspacePage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('无历史栈且未连接时，一级菜单返回退回连接页', (tester) async {
    final router = await _mount(tester);
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('连接丢失'), findsNothing);
  });

  testWidgets('从连接页进入设置二级页面后，按两次 ESC 依次退回一级菜单和连接页', (tester) async {
    await _mount(tester);
    expect(find.byType(ConnectPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    final appearanceCategory = find.widgetWithText(SettingsTile, '外观');
    await tester.ensureVisible(appearanceCategory);
    await tester.tap(appearanceCategory);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SettingsTile, '动效'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.widgetWithText(SettingsTile, '外观'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ConnectPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('连接丢失'), findsNothing);
  });
}
