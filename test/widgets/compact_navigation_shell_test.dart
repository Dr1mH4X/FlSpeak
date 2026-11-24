import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:material_ui/material_ui.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        NavigationBar,
        NavigationDestination,
        OutlinedButton,
        Switch,
        TextButton,
        TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/app.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/platform/android_app_lifecycle.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/stream_viewer.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/features/settings/settings_page.dart';
import 'package:flspeak/features/settings/widgets/settings_section.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/chat_pane.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/router.dart';
import 'package:flspeak/widgets/app_navigation_sidebar.dart';
import 'package:flspeak/widgets/common.dart';
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

  @override
  Future<bool> joinChannel(int channelId, {String? password}) async {
    final selfId = state.selfClientId;
    if (selfId == null) {
      return false;
    }
    final updatedClients = [
      for (final client in state.clients)
        if (client.id == selfId)
          ClientView(
            id: client.id,
            nickname: client.nickname,
            uid: client.uid,
            channelId: channelId,
            inputMuted: client.inputMuted,
            outputMuted: client.outputMuted,
            away: client.away,
            awayMessage: client.awayMessage,
            clientType: client.clientType,
            appName: client.appName,
            appVersion: client.appVersion,
            capabilities: client.capabilities,
            botCommands: client.botCommands,
            botCommandPrefix: client.botCommandPrefix,
          )
        else
          client,
    ];
    state = state.copyWith(
      state: CoreSessionState.connected(clientId: selfId, channelId: channelId),
      clients: updatedClients,
    );
    return true;
  }

  @override
  Future<void> setMuted(bool muted) async {
    state = state.copyWith(
      muted: muted,
      selfSpeaking: muted ? false : state.selfSpeaking,
    );
  }

  @override
  Future<void> setDeafened(bool deafened) async {
    state = state.copyWith(
      deafened: deafened,
      muted: deafened ? true : state.muted,
    );
  }

  @override
  Future<void> setPttMode(bool enabled) async {
    state = state.copyWith(pttMode: enabled);
  }

  @override
  Future<void> setPttActive(bool active) async {
    if (!state.pttMode) {
      return;
    }
    state = state.copyWith(selfSpeaking: active);
  }

  @override
  Future<bool> disconnect() async {
    state = const SessionView();
    return true;
  }
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
    'compact root renders NavigationDock vs NavigationBar, switches tabs with Fade, and pushes settings details over the root dock',
    (tester) async {
      final container = await _mountCompactApp(
        tester,
        preferences: const SessionPreferences(
          nickname: 'Test',
          locale: 'zh',
          floatingNavigationBar: true,
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

      // 钻入外观二级页面走卡片路由推入，覆盖根底栏；返回后底栏重新显现。
      await tester.tap(find.widgetWithText(SettingsTile, '外观'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDock), findsNothing);

      await tester.tap(
        find.bySemanticsLabel(
          MaterialLocalizations.of(tester.element(find.byType(SettingsPage)))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDock), findsOneWidget);

      // 从设置切回主页。
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDock),
          matching: find.text('主页'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConnectPage), findsOneWidget);

      // 未连接时仍可切入中间「工作区」标签查看空态，3 标签底栏保持可见。
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDock),
          matching: find.text('工作区'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('连接丢失'), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);
      expect(
        tester
            .widget<AnimatedVisibility>(find.byType(AnimatedVisibility))
            .visible,
        isTrue,
      );
    },
  );

  testWidgets(
    'compact workspace Level 1 keeps 3-tab root dock, single-tap channel enters Level 2 and hides root dock, and top-left back exits to Level 1',
    (tester) async {
      final container = await _mountCompactApp(
        tester,
        sessionView: const SessionView(
          state: CoreSessionState.connected(clientId: 1, channelId: 1),
          activeServerId: 'srv-1',
          servers: [
            ServerProfileView(
              id: 'srv-1',
              label: '测试服务器',
              host: '127.0.0.1',
              port: 9987,
            ),
          ],
          channels: [
            ChannelView(id: 1, parentId: 0, name: '大厅', description: ''),
            ChannelView(id: 2, parentId: 0, name: '语音厅', description: ''),
          ],
          clients: [
            ClientView(id: 1, nickname: 'Tester', uid: 'tester', channelId: 1),
          ],
        ),
      );

      // 导航至工作区一级总览：保留三标签根底栏，顶栏展示语音控制与断开按钮。
      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();

      expect(find.byType(CompactNavigationShell), findsOneWidget);
      expect(find.byType(ChannelPanel), findsOneWidget);
      expect(find.byType(WorkspacePage), findsNothing);
      expect(find.text('测试服务器'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);
      expect(
        tester
            .widget<AnimatedVisibility>(find.byType(AnimatedVisibility))
            .visible,
        isTrue,
      );

      // 单击其他频道立即加入并推入二级频道页：无 300ms 双击延迟，根底栏收起。
      await tester.tap(find.text('语音厅'));
      await tester.pumpAndSettle();

      expect(container.read(sessionViewProvider).selfChannelId, 2);
      expect(find.byType(WorkspacePage), findsOneWidget);
      expect(find.byType(NavigationDock), findsNothing);

      // 点击频道顶栏左上角返回按钮，退回一级总览并恢复根底栏。
      await tester.tap(
        find.bySemanticsLabel(
          MaterialLocalizations.of(tester.element(find.byType(WorkspacePage)))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorkspacePage), findsNothing);
      expect(find.byType(ChannelPanel), findsOneWidget);
      expect(find.byType(CompactNavigationShell), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);
    },
  );

  testWidgets(
    'resizing wide pops the compact channel page and restores the wide workspace',
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

      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();
      await tester.tap(find.text('大厅'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<WorkspacePage>(find.byType(WorkspacePage))
            .where((page) => page.forceCompact),
        isNotEmpty,
      );

      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();

      expect(find.byType(CompactNavigationShell), findsNothing);
      expect(find.byType(AppNavigationSidebar), findsOneWidget);
      expect(
        tester
            .widgetList<WorkspacePage>(find.byType(WorkspacePage))
            .where((page) => page.forceCompact),
        isEmpty,
      );
    },
  );

  testWidgets(
    'compact workspace 3-slot bottom bar adapts VAD/PTT dual-mode switching and floating vs docked styles',
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

      // 进入二级频道页（默认 VAD：文字输入模式）。
      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();
      await tester.tap(find.text('大厅'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatPane), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.add_photo_alternate_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.mic_rounded),
        ),
        findsOneWidget,
      );

      // 输入文字后右槽自动切换为发送按钮，清空文字后恢复语音按钮。
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.send_rounded),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.mic_rounded),
        ),
        findsOneWidget,
      );

      // 长按右槽切换到语音控制模式：展示键盘切换、静音/关闭声音分段条与红色挂断按钮。
      await tester.longPress(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.mic_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.keyboard_alt_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(ChatPane), matching: find.text('静音')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(ChatPane), matching: find.text('关闭声音')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.call_end_rounded),
        ),
        findsOneWidget,
      );

      // 切换为停靠底栏样式仍正常渲染，点按静音立即生效。
      container
          .read(preferencesProvider.notifier)
          .setFloatingNavigationBar(false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('静音'));
      await tester.pumpAndSettle();
      expect(find.text('取消静音'), findsOneWidget);

      // 退回一级总览后切为 PTT，再进入二级频道页：初始直接处于语音控制模式（全宽按住说话）。
      await tester.tap(
        find.bySemanticsLabel(
          MaterialLocalizations.of(tester.element(find.byType(WorkspacePage)))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      await container.read(sessionViewProvider.notifier).setPttMode(true);
      await tester.pumpAndSettle();

      await tester.tap(find.text('大厅'));
      await tester.pumpAndSettle();
      expect(find.text('按住说话'), findsOneWidget);

      final holdGesture = await tester.startGesture(
        tester.getCenter(find.text('按住说话')),
      );
      await tester.pump();
      expect(container.read(sessionViewProvider).selfSpeaking, isTrue);
      expect(find.text('正在说话…'), findsOneWidget);
      await holdGesture.up();
      await tester.pump();
      expect(container.read(sessionViewProvider).selfSpeaking, isFalse);

      // 左槽键盘按钮切到文字输入模式，再点按右槽切回语音控制模式。
      await tester.tap(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.keyboard_alt_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.mic_none_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byIcon(Icons.mic_none_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('按住说话'), findsOneWidget);
    },
  );

  testWidgets(
    'Android system back closes workspace fullscreen first, exits Level 2 to Level 1, and returns to Connect without disconnecting',
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
      await tester.tap(find.text('大厅'));
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

      // 2. 二级频道页侧滑先退回一级总览，根底栏重新显现。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsNothing);
      expect(find.byType(ChannelPanel), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);

      // 3. 工作区一级总览侧滑返回首页，会话保持在线且不退出应用。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChannelPanel), findsNothing);
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
      expect(find.byType(NavigationDock), findsNothing);

      // 三级 -> 二级
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SettingsTile, '语音'), findsOneWidget);
      expect(find.byType(NavigationDock), findsNothing);

      // 二级 -> 一级概览，底栏重新显现
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SettingsTile, '通用'), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);

      // 一级概览侧滑 -> 切回主页标签，不退出应用
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ConnectPage), findsOneWidget);
      expect(lifecycle.exitAppCalls, 0);
      expect(lifecycle.moveToBackgroundCalls, 0);

      // 从工作区进入二级频道页并 push 打开设置，概览态侧滑应 pop 回二级频道页。
      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pumpAndSettle();
      await tester.tap(find.text('大厅'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsOneWidget);

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
