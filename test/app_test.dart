// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'package:flspeak/app.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/notices.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/router.dart';
import 'package:flspeak/widgets/app_navigation_sidebar.dart';
import 'package:flspeak/widgets/prism.dart' show BannerHost, Surface;
import 'package:flspeak/widgets/update_dot.dart';

class _PttSession extends SessionController {
  final presses = <bool>[];
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    pttMode: true,
  );
  @override
  Future<void> setPttActive(bool active) async {
    presses.add(active);
  }
}

class _PttCore extends Fake implements CoreSession {}

Future<ProviderContainer> _mountPtt(
  WidgetTester tester,
  _PttSession controller,
) async {
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_PttCore()),
      storePathProvider.overrideWithValue('/tmp/flspeak-test/preferences.json'),
      sessionViewProvider.overrideWith(() => controller),
      preferencesStoreProvider.overrideWithValue(
        PreferencesStore.inMemory(
          preferences: SessionPreferences(
            nickname: 'Test',
            locale: 'zh',
            pttHotkey: LogicalKeyboardKey.keyA.keyId,
          ),
        ),
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
  const hotkey = MethodChannel('flspeak/global_hotkey');
  for (final recordedKey in [
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyB,
  ]) {
    testWidgets(
      'recording ${recordedKey.keyLabel} releases PTT and suppresses it until the recorder closes',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hotkey,
          (call) async => call.method == 'register' ? true : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            hotkey,
            null,
          ),
        );
        final controller = _PttSession();
        final container = await _mountPtt(tester, controller);
        container.read(routerProvider).go(AppRoutes.settings);
        await tester.pumpAndSettle();
        final generalCategory = find.text('通用');
        await tester.ensureVisible(generalCategory);
        await tester.tap(generalCategory);
        await tester.pumpAndSettle();
        final voiceTile = find.text('语音');
        await tester.ensureVisible(voiceTile);
        await tester.tap(voiceTile);
        await tester.pumpAndSettle();
        final shortcut = find.text('按住说话快捷键');
        await tester.ensureVisible(shortcut);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        expect(controller.presses, [true, false]);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyDownEvent(recordedKey);
        await tester.pumpAndSettle();
        expect(controller.presses, [true, false]);
        expect(find.text('录制快捷键'), findsNothing);
        expect(
          container.read(preferencesProvider).pttHotkey,
          recordedKey.keyId,
        );
        await tester.sendKeyUpEvent(recordedKey);
        await tester.sendKeyDownEvent(recordedKey);
        expect(controller.presses, [true, false, true]);
        await tester.sendKeyUpEvent(recordedKey);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'changing the PTT key and disposing the app release the held microphone',
    (tester) async {
      var unregisters = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
        call,
      ) async {
        if (call.method == 'unregister') {
          unregisters++;
          return null;
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hotkey,
          null,
        ),
      );
      final controller = _PttSession();
      final container = await _mountPtt(tester, controller);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      container
          .read(preferencesProvider.notifier)
          .setPttHotkey(LogicalKeyboardKey.keyB.keyId);
      await tester.pump();
      expect(controller.presses, [true, false]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.presses, [true, false, true, false]);
      expect(unregisters, 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
    },
  );

  testWidgets(
    'late hotkey registration cannot disable the focus-loss PTT fallback',
    (tester) async {
      final old = Completer<bool>();
      final current = Completer<bool>();
      var registrations = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
        call,
      ) async {
        if (call.method != 'register') return null;
        return ++registrations == 1 ? old.future : current.future;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hotkey,
          null,
        ),
      );
      final controller = _PttSession();
      final container = await _mountPtt(tester, controller);
      container
          .read(preferencesProvider.notifier)
          .setPttHotkey(LogicalKeyboardKey.keyB.keyId);
      await tester.pump();
      current.complete(false);
      await tester.pump();
      old.complete(true);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(controller.presses, [true, false]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in Brightness.values) {
    test('theme text and status contrast: $brightness', () {
      final theme = buildAppTheme(brightness);
      final scheme = theme.colorScheme;
      final status = theme.extension<StatusColors>()!;
      for (final pair in [
        (scheme.onSurface, scheme.surface),
        (scheme.onSurfaceVariant, scheme.surfaceContainerLow),
        (scheme.onPrimary, scheme.primary),
        (scheme.onPrimaryContainer, scheme.primaryContainer),
        (status.live, scheme.surfaceContainer),
      ]) {
        final first = pair.$1.computeLuminance();
        final second = pair.$2.computeLuminance();
        final ratio = first > second
            ? (first + 0.05) / (second + 0.05)
            : (second + 0.05) / (first + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });
  }

  test('深色主题要求浅色系统栏图标', () {
    final style = appSystemUiOverlayStyle(buildAppTheme(Brightness.dark));

    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
  });

  test('浅色主题要求深色系统栏图标', () {
    final style = appSystemUiOverlayStyle(buildAppTheme(Brightness.light));

    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('logging initialization failure shows a startup notice', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(_PttCore()),
        storePathProvider.overrideWithValue(
          '/tmp/flspeak-test/preferences.json',
        ),
        sessionViewProvider.overrideWith(_PttSession.new),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore.inMemory(
            preferences: const SessionPreferences(
              nickname: 'Test',
              locale: 'zh',
            ),
          ),
        ),
        loggingFailureProvider.overrideWithValue(StateError('no log dir')),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TsClientApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('文件日志不可用，应用将继续以控制台日志运行。'), findsOneWidget);
  });

  testWidgets(
    'checks updates on startup when enabled, shows notice once, and does not recheck on about page',
    (tester) async {
      var checkCalls = 0;
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_PttCore()),
          appVersionProvider.overrideWithValue('0.1.0'),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          sessionViewProvider.overrideWith(_PttSession.new),
          startupUpdateCheckEnabledProvider.overrideWithValue(true),
          updateCheckClientProvider.overrideWithValue(() async {
            checkCalls++;
            return const UpdateStateView(
              available: true,
              latestVersion: '0.2.0',
              releaseUrl:
                  'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
            );
          }),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(
                nickname: 'Test',
                locale: 'zh',
                autoCheckUpdate: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TsClientApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(checkCalls, 1);
      expect(find.text('有新版本 0.2.0'), findsOneWidget);

      container.read(routerProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();

      final aboutCategory = find.text('关于');
      await tester.ensureVisible(aboutCategory);
      await tester.tap(aboutCategory);
      await tester.pumpAndSettle();

      expect(checkCalls, 1);
      expect(find.byType(UpdateDot), findsOneWidget);
    },
  );

  testWidgets('skips startup update check when autoCheckUpdate is disabled', (
    tester,
  ) async {
    var checkCalls = 0;
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(_PttCore()),
        storePathProvider.overrideWithValue(
          '/tmp/flspeak-test/preferences.json',
        ),
        sessionViewProvider.overrideWith(_PttSession.new),
        startupUpdateCheckEnabledProvider.overrideWithValue(true),
        updateCheckClientProvider.overrideWithValue(() async {
          checkCalls++;
          return const UpdateStateView(available: true, latestVersion: '0.2.0');
        }),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore.inMemory(
            preferences: const SessionPreferences(
              nickname: 'Test',
              locale: 'zh',
              autoCheckUpdate: false,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TsClientApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(checkCalls, 0);
    expect(find.text('有新版本 0.2.0'), findsNothing);
  });

  testWidgets(
    'clicking settings back button from a secondary menu preserves sidebar and top-bar colors across every frame',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_PttCore()),
          appVersionProvider.overrideWithValue('0.1.0'),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          sessionViewProvider.overrideWith(_PttSession.new),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(
                nickname: 'Test',
                locale: 'zh',
                theme: AppThemePreference.light,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TsClientApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, Duration.zero);

      container.read(routerProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();

      Surface sidebarSurface() => tester.widget<Surface>(
        find
            .descendant(
              of: find.byType(AppNavigationSidebar),
              matching: find.byType(Surface),
            )
            .first,
      );

      final baselineSidebarColor = sidebarSurface().color;
      final baselineTheme = Theme.of(
        tester.element(find.byType(AppNavigationSidebar)),
      );

      final generalCategory = find.text('通用');
      await tester.ensureVisible(generalCategory);
      await tester.tap(generalCategory);
      await tester.pumpAndSettle();

      final backButton = find.byIcon(Icons.arrow_back_rounded);
      expect(backButton, findsOneWidget);
      final topBarTitleColor = tester
          .widget<Text>(find.text('通用').first)
          .style
          ?.color;

      await tester.tap(backButton);
      for (final step in [
        Duration.zero,
        const Duration(milliseconds: 16),
        const Duration(milliseconds: 40),
        const Duration(milliseconds: 100),
      ]) {
        await tester.pump(step);
        expect(sidebarSurface().color, baselineSidebarColor);
        expect(
          identical(
            Theme.of(tester.element(find.byType(AppNavigationSidebar))),
            baselineTheme,
          ),
          isTrue,
        );
        expect(
          tester.widget<Text>(find.text('设置').first).style?.color,
          topBarTitleColor,
        );
      }
      await tester.pumpAndSettle();
      expect(sidebarSurface().color, baselineSidebarColor);
      expect(find.byKey(const ValueKey<String>('overview')), findsOneWidget);
    },
  );

  testWidgets(
    'NoticeCenter maps tones into BannerHost without double-adding window header height',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_PttCore()),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          sessionViewProvider.overrideWith(_PttSession.new),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(
                nickname: 'Test',
                locale: 'zh',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TsClientApp(),
        ),
      );
      await tester.pumpAndSettle();

      final host = tester.widget<BannerHost>(find.byType(BannerHost));
      expect(host.stacked, isTrue);
      expect(host.topInset, Sizes.header + 8);

      container.read(noticeCenterProvider.notifier)
        ..show('操作已完成', tone: NoticeTone.info)
        ..show('连接失败', tone: NoticeTone.error);
      await tester.pumpAndSettle();

      expect(find.text('操作已完成'), findsOneWidget);
      expect(find.text('连接失败'), findsOneWidget);

      // Windows 32px 标题栏已由 WindowHeaderContainer 扣除，横幅从 32 + 56 = 88 下方展开。
      final topBannerY = tester.getTopLeft(find.text('连接失败')).dy;
      expect(topBannerY, greaterThanOrEqualTo(32 + Sizes.header + 8));
      expect(topBannerY, lessThan(32 + 32 + Sizes.header + 8));
    },
  );
}
