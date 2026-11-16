// ignore_for_file: depend_on_referenced_packages

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
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
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
}

class _Update extends UpdateController {
  @override
  UpdateStateView build() => const UpdateStateView(available: false);
}

Future<ProviderContainer> _mountCompactApp(
  WidgetTester tester, {
  SessionPreferences preferences = const SessionPreferences(
    nickname: 'Test',
    locale: 'zh',
  ),
  SessionView sessionView = const SessionView(),
  Size size = const Size(390, 844),
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
}
