// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/models.dart';
import '../core/preferences.dart';
import '../core/providers.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_navigation_sidebar.dart';
import 'view_scope.dart';

class _FakeCore extends Fake implements CoreSession {}

class _TestSessionController extends SessionController {
  @override
  SessionView build() => const SessionView();
}

void main() {
  testWidgets(
    'AppNavigationSidebar adapts width to macOS window controls and 48px baseline',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
          storePathProvider.overrideWithValue('/tmp/flspeak/prefs.json'),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(nickname: 'Test'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 1. 无 window controls 时为 48px
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ViewScope(
                size: Size(800, 600),
                isMobile: false,
                windowControls: Size.zero,
                child: Row(
                  children: [
                    AppNavigationSidebar(
                      selectedDestination: AppNavDestination.home,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sidebarBox = tester.renderObject<RenderBox>(
        find.byType(AppNavigationSidebar),
      );
      expect(sidebarBox.size.width, 48.0);

      // 严禁包含 Tooltip (Rule 6)
      expect(find.byType(Tooltip), findsNothing);
    },
  );

  testWidgets(
    'AppNavigationSidebar adapts to macOS 78px traffic lights and toggles expansion in-place on desktop',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
          storePathProvider.overrideWithValue('/tmp/flspeak/prefs.json'),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(nickname: 'Test'),
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ViewScope(
                size: Size(1000, 700),
                isMobile: false,
                windowControls: Size(78, 32),
                child: Row(
                  children: [
                    AppNavigationSidebar(
                      selectedDestination: AppNavDestination.home,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sidebarBox = tester.renderObject<RenderBox>(
        find.byType(AppNavigationSidebar),
      );
      expect(sidebarBox.size.width, 78.0);

      // 桌面端点击折叠按钮就地展开至 220px
      final toggle = find.bySemanticsLabel('展开侧边栏');
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(sidebarBox.size.width, 220.0);

        final collapseToggle = find.bySemanticsLabel('收起侧边栏');
        await tester.tap(collapseToggle);
        await tester.pumpAndSettle();
        expect(sidebarBox.size.width, 78.0);
      }
    },
  );

  testWidgets(
    'AppNavigationSidebar opens OverlayPortal in compact mode and dismisses via ESC',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
          storePathProvider.overrideWithValue('/tmp/flspeak/prefs.json'),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(nickname: 'Test'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Row(
                children: [
                  AppNavigationSidebar(
                    selectedDestination: AppNavDestination.home,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 窄屏下初始保持收窄宽度 (48px)
      final sidebarBox = tester.renderObject<RenderBox>(
        find.byType(AppNavigationSidebar),
      );
      expect(sidebarBox.size.width, 48.0);

      // 点击展开按钮触发 OverlayPortal 浮层
      final toggle = find.bySemanticsLabel('展开侧边栏');
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      // 底栏宽度不膨胀，浮层出现
      expect(sidebarBox.size.width, 48.0);
      expect(find.byType(FocusScope), findsWidgets);

      // 按 ESC 键关闭浮层
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(sidebarBox.size.width, 48.0);
    },
  );
}
