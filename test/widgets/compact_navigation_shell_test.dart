// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        NavigationBar,
        NavigationDestination,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/app.dart';
import 'package:flspeak/core/android_app_lifecycle.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/stream_viewer.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/features/settings/settings_page.dart';
import 'package:flspeak/features/settings/widgets/settings_section.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/router.dart';
import 'package:flspeak/widgets/compact_navigation_shell.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  _Session([this._initial = const SessionView()]);
  final SessionView _initial;

  @override
  SessionView build() => _initial;

  void setView(SessionView next) => state = next;
}

class _Update extends UpdateController {
  @override
  UpdateStateView build() => const UpdateStateView(available: false);
}

class _FakeLifecycle implements AndroidAppLifecycleGateway {
  int moveToBackgroundCalls = 0;
  int exitAppCalls = 0;

  @override
  Future<bool> moveToBackground() async {
    moveToBackgroundCalls++;
    return true;
  }

  @override
  Future<void> exitApp() async {
    exitAppCalls++;
  }
}

class _Viewer extends StreamViewerController {
  int exitFullScreenCalls = 0;

  @override
  StreamViewerState build() => const StreamViewerState();

  void setTestFullScreen(bool value) {
    state = state.copyWith(isFullScreen: value);
  }

  @override
  Future<void> setFullScreen(bool fullScreen) async {
    if (!fullScreen && state.isFullScreen) {
      exitFullScreenCalls++;
    }
    state = state.copyWith(isFullScreen: fullScreen);
  }
}

Future<ProviderContainer> _mountCompactApp(
  WidgetTester tester, {
  SessionPreferences preferences = const SessionPreferences(
    nickname: 'Test',
    locale: 'zh',
  ),
  SessionView sessionView = const SessionView(),
  Size size = const Size(390, 844),
  AndroidAppLifecycleGateway? lifecycle,
  DateTime Function()? clock,
  _Viewer? viewer,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_Core()),
      sessionViewProvider.overrideWith(() => _Session(sessionView)),
      updateProvider.overrideWith(_Update.new),
      appVersionProvider.overrideWithValue('0.1.0'),
      if (lifecycle != null)
        androidAppLifecycleProvider.overrideWithValue(lifecycle),
      if (clock != null) clockProvider.overrideWithValue(clock),
      if (viewer != null) streamViewerProvider.overrideWith(() => viewer),
      storePathProvider.overrideWithValue('/tmp/flspeak-test/preferences.json'),
      preferencesStoreProvider.overrideWithValue(
        PreferencesStore.inMemory(preferences: preferences),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const TsClientApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'compact root renders NavigationDock vs NavigationBar, switches tabs with Slide/Fade, and hides bottom bar inside settings subpages',
    (tester) async {
      final container = await _mountCompactApp(
        tester,
        preferences: const SessionPreferences(
          nickname: 'Test',
          locale: 'zh',
          floatingNavigationBar: true,
          tabAnimation: TabAnimation.fade,
        ),
      );

      expect(find.byType(CompactNavigationShell), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ConnectPage), findsOneWidget);

      // 切换为停靠底栏。
      container
          .read(preferencesProvider.notifier)
          .setFloatingNavigationBar(false);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      // 切回悬浮 NavigationDock 后点「设置」。
      container
          .read(preferencesProvider.notifier)
          .setFloatingNavigationBar(true);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDock), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDock),
          matching: find.text('设置'),
        ),
      );
      // 验证淡入淡出中途存在透明帧。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.byType(SnapshotWidget), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      // 钻入外观二级页面时底栏自动收起，退回总览后重新显现。
      await tester.tap(find.widgetWithText(SettingsTile, '外观'));
      await tester.pumpAndSettle();
      final visibilityWhileSubpage = tester.widget<AnimatedVisibility>(
        find.byType(AnimatedVisibility),
      );
      expect(visibilityWhileSubpage.visible, isFalse);

      await tester.tap(
        find.bySemanticsLabel(
          MaterialLocalizations.of(tester.element(find.byType(SettingsPage)))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      final visibilityAtOverview = tester.widget<AnimatedVisibility>(
        find.byType(AnimatedVisibility),
      );
      expect(visibilityAtOverview.visible, isTrue);

      // 切回 Slide 动画也能从设置切回主页。
      container
          .read(preferencesProvider.notifier)
          .setTabAnimation(TabAnimation.slide);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDock),
          matching: find.text('主页'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConnectPage), findsOneWidget);
    },
  );

  testWidgets(
    'compact workspace hides bottom bar and provides both top-left back exit and drawer navigation back to Home/Settings',
    (tester) async {
      final container = await _mountCompactApp(
        tester,
        sessionView: const SessionView(
          state: CoreSessionState.connected(clientId: 1, channelId: 1),
          activeServerId: 'srv-1',
          channels: [
            ChannelView(id: 1, parentId: 0, name: '大厅', description: ''),
          ],
          clients: [
            ClientView(id: 1, nickname: 'Tester', uid: 'tester', channelId: 1),
          ],
        ),
      );

      // 导航至工作区频道视图：底栏彻底收起。
      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();

      expect(find.byType(WorkspacePage), findsOneWidget);
      expect(find.byType(NavigationDock), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      // 检查抽屉中也有侧栏出口，然后关闭抽屉再测试顶栏返回按钮。
      await tester.tap(find.bySemanticsLabel('打开频道菜单'));
      await tester.pumpAndSettle();
      expect(find.text('主页'), findsWidgets);
      expect(find.text('设置'), findsWidgets);
      Navigator.of(tester.element(find.byType(WorkspacePage))).pop();
      await tester.pumpAndSettle();

      // 点击频道顶栏左上角返回按钮，直接退回窄屏底部导航壳（可见「首页/设置」底栏）。
      await tester.tap(
        find.bySemanticsLabel(
          MaterialLocalizations.of(tester.element(find.byType(WorkspacePage)))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorkspacePage), findsNothing);
      expect(find.byType(CompactNavigationShell), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);
    },
  );

  testWidgets(
    'Android system back closes workspace fullscreen/drawer first and returns to Connect without disconnecting',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final lifecycle = _FakeLifecycle();
      final viewer = _Viewer();
      final container = await _mountCompactApp(
        tester,
        lifecycle: lifecycle,
        viewer: viewer,
        sessionView: const SessionView(
          state: CoreSessionState.connected(clientId: 1, channelId: 1),
          activeServerId: 'srv-1',
          channels: [
            ChannelView(id: 1, parentId: 0, name: '大厅', description: ''),
          ],
          clients: [
            ClientView(id: 1, nickname: 'Tester', uid: 'tester', channelId: 1),
          ],
        ),
      );

      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsOneWidget);

      // 1. 全屏观看期间侧滑先退出全屏。
      viewer.setTestFullScreen(true);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(viewer.exitFullScreenCalls, 1);
      expect(container.read(streamViewerProvider).isFullScreen, isFalse);
      expect(find.byType(WorkspacePage), findsOneWidget);

      // 2. 打开抽屉后侧滑先收起抽屉。
      await tester.tap(find.bySemanticsLabel('打开频道菜单'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(WorkspacePage), findsOneWidget);

      // 3. 工作区正常态侧滑返回首页，会话保持在线且不退出应用。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsNothing);
      expect(find.byType(ConnectPage), findsOneWidget);
      expect(container.read(sessionViewProvider).connected, isTrue);
      expect(lifecycle.exitAppCalls, 0);
      expect(lifecycle.moveToBackgroundCalls, 0);
    },
  );

  testWidgets(
    'Android system back navigates Settings subpages back to overview with dock, then returns to Home tab; pushed Settings pops to caller',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final lifecycle = _FakeLifecycle();
      final container = await _mountCompactApp(
        tester,
        lifecycle: lifecycle,
        sessionView: const SessionView(
          state: CoreSessionState.connected(clientId: 1, channelId: 1),
          activeServerId: 'srv-1',
          channels: [
            ChannelView(id: 1, parentId: 0, name: '大厅', description: ''),
          ],
          clients: [
            ClientView(id: 1, nickname: 'Tester', uid: 'tester', channelId: 1),
          ],
        ),
      );

      // 切到设置标签并进入「通用」->「语音」。
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDock),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SettingsTile, '通用'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SettingsTile, '语音'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedVisibility>(find.byType(AnimatedVisibility))
            .visible,
        isFalse,
      );

      // 三级 -> 二级
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SettingsTile, '语音'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedVisibility>(find.byType(AnimatedVisibility))
            .visible,
        isFalse,
      );

      // 二级 -> 一级概览，底栏重新显现
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SettingsTile, '通用'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedVisibility>(find.byType(AnimatedVisibility))
            .visible,
        isTrue,
      );

      // 一级概览侧滑 -> 切回主页标签，不退出应用
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ConnectPage), findsOneWidget);
      expect(lifecycle.exitAppCalls, 0);
      expect(lifecycle.moveToBackgroundCalls, 0);

      // 从工作区抽屉 push 打开设置，概览态侧滑应 pop 回工作区。
      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();
      unawaited(container.read(routerProvider).push(AppRoutes.settings));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsOneWidget);
      expect(lifecycle.exitAppCalls, 0);
    },
  );

  testWidgets(
    'Android root back moves app to background when connected and requires double back within 2s when disconnected',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final lifecycle = _FakeLifecycle();
      final container = await _mountCompactApp(
        tester,
        lifecycle: lifecycle,
        clock: () => now,
        sessionView: const SessionView(
          state: CoreSessionState.connected(clientId: 1, channelId: 1),
          activeServerId: 'srv-1',
        ),
      );

      // 1. 已连接状态下首页根返回：直接退回后台。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(lifecycle.moveToBackgroundCalls, 1);
      expect(lifecycle.exitAppCalls, 0);
      expect(find.text('再按一次返回退出应用'), findsNothing);

      // 2. 断开连接后：首次返回展示提示，超时后需重新计时，2 秒内连按两次退出。
      (container.read(sessionViewProvider.notifier) as _Session).setView(
        const SessionView(),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('再按一次返回退出应用'), findsOneWidget);
      expect(lifecycle.exitAppCalls, 0);

      // 超过 2 秒后再次返回，不退出。
      now = now.add(const Duration(seconds: 3));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(lifecycle.exitAppCalls, 0);

      // 2 秒内第二次返回，退出应用。
      now = now.add(const Duration(seconds: 1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(lifecycle.exitAppCalls, 1);
      expect(lifecycle.moveToBackgroundCalls, 1);
    },
  );

  testWidgets(
    'Android system back on wide layout pops pushed settings and workspace returns to Connect before root exit guard',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final lifecycle = _FakeLifecycle();
      final container = await _mountCompactApp(
        tester,
        size: const Size(1000, 800),
        lifecycle: lifecycle,
        sessionView: const SessionView(
          state: CoreSessionState.connected(clientId: 1, channelId: 1),
          activeServerId: 'srv-1',
          channels: [
            ChannelView(id: 1, parentId: 0, name: '大厅', description: ''),
          ],
          clients: [
            ClientView(id: 1, nickname: 'Tester', uid: 'tester', channelId: 1),
          ],
        ),
      );

      // 宽屏下从首页 push 打开设置，侧滑返回应回到首页。
      unawaited(container.read(routerProvider).push(AppRoutes.settings));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.byType(ConnectPage), findsOneWidget);

      // 宽屏下进入工作区后侧滑返回，应回到首页且保持连接。
      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsNothing);
      expect(find.byType(ConnectPage), findsOneWidget);

      // 在首页已连接状态下侧滑返回 -> 退回后台。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(lifecycle.moveToBackgroundCalls, 1);
      expect(lifecycle.exitAppCalls, 0);
    },
  );
}
