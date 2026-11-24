// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:material_ui/material_ui.dart'
    hide InputDecorationTheme, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'package:flspeak/app.dart';
import 'package:flspeak/core/logging/json_lines_file_observer.dart';
import 'package:flspeak/core/logging/logger.dart';
import 'package:flspeak/core/platform/global_hotkey.dart';
import 'package:flspeak/features/settings/settings_page.dart';
import 'package:talker/talker.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/notices.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/router.dart';
import 'package:flspeak/widgets/app_navigation_sidebar.dart';
import 'package:flspeak/widgets/prism.dart'
    show
        BannerHost,
        InputDecorationTheme,
        LiquidGlassQuality,
        LiquidGlassScope,
        ScaffoldBar,
        Surface,
        TextField;
import 'package:flspeak/widgets/update_dot.dart';

class _PttSession extends SessionController {
  _PttSession({this.initialPttMode = true, this.initialConnected = true});

  final bool initialPttMode;
  final bool initialConnected;
  final presses = <bool>[];

  @override
  SessionView build() => SessionView(
    state: initialConnected
        ? const CoreSessionState.connected(clientId: 1, channelId: 5)
        : const CoreSessionState.disconnected(),
    pttMode: initialPttMode,
  );

  @override
  Future<void> setPttMode(bool enabled) async {
    state = state.copyWith(pttMode: enabled);
  }

  void setConnected(bool connected) {
    state = state.copyWith(
      state: connected
          ? const CoreSessionState.connected(clientId: 1, channelId: 5)
          : const CoreSessionState.disconnected(),
    );
  }

  @override
  Future<void> setPttActive(bool active) async {
    presses.add(active);
  }
}

class _PttCore extends Fake implements CoreSession {
  @override
  Future<AudioDevicesView> listAudioDevices() async =>
      const AudioDevicesView(inputs: [], outputs: []);
}

Future<ProviderContainer> _mountPtt(
  WidgetTester tester,
  _PttSession controller, {
  int? pttHotkey,
  bool overrideHotkey = true,
}) async {
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
            pttHotkey: overrideHotkey
                ? pttHotkey
                : LogicalKeyboardKey.keyA.keyId,
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
          (call) async => call.method == 'register'
              ? <String, Object?>{
                  'ok': true,
                  'reason': 'registered',
                  'code': null,
                }
              : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            hotkey,
            null,
          ),
        );
        final controller = _PttSession();
        final container = await _mountPtt(
          tester,
          controller,
          overrideHotkey: false,
        );
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
        return <String, Object?>{
          'ok': true,
          'reason': 'registered',
          'code': null,
        };
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hotkey,
          null,
        ),
      );
      final controller = _PttSession();
      final container = await _mountPtt(
        tester,
        controller,
        overrideHotkey: false,
      );
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
      final old = Completer<Map<String, Object?>>();
      final current = Completer<Map<String, Object?>>();
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
      final container = await _mountPtt(
        tester,
        controller,
        overrideHotkey: false,
      );
      container
          .read(preferencesProvider.notifier)
          .setPttHotkey(LogicalKeyboardKey.keyB.keyId);
      await tester.pump();
      current.complete(<String, Object?>{
        'ok': false,
        'reason': 'failed',
        'code': 5,
      });
      await tester.pump();
      old.complete(<String, Object?>{
        'ok': true,
        'reason': 'registered',
        'code': null,
      });
      await tester.pump();
      expect(
        container.read(pttHotkeyStatusProvider).state,
        PttHotkeyState.failed,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(controller.presses, [true, false]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'registers global hotkey only when pttMode is enabled and unregisters on disable',
    (tester) async {
      var registerCalls = 0;
      var unregisterCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
        call,
      ) async {
        if (call.method == 'register') {
          registerCalls++;
          return <String, Object?>{
            'ok': true,
            'reason': 'registered',
            'code': null,
          };
        }
        if (call.method == 'unregister') {
          unregisterCalls++;
          return true;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hotkey,
          null,
        ),
      );

      final controller = _PttSession(initialPttMode: false);
      final container = await _mountPtt(
        tester,
        controller,
        pttHotkey: LogicalKeyboardKey.keyA.keyId,
      );
      expect(registerCalls, 0);
      expect(unregisterCalls, 1);
      expect(
        container.read(pttHotkeyStatusProvider),
        PttHotkeyStatus.inactive(keyId: LogicalKeyboardKey.keyA.keyId),
      );

      await container.read(sessionViewProvider.notifier).setPttMode(true);
      await tester.pumpAndSettle();
      expect(registerCalls, 1);
      expect(
        container.read(pttHotkeyStatusProvider).state,
        PttHotkeyState.registered,
      );

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        hotkey.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onKeyDown'),
        ),
        (_) {},
      );
      await tester.pump();
      expect(controller.presses, [true]);

      await container.read(sessionViewProvider.notifier).setPttMode(false);
      await tester.pumpAndSettle();
      expect(unregisterCalls, 2);
      expect(controller.presses, [true, false]);
      expect(
        container.read(pttHotkeyStatusProvider),
        PttHotkeyStatus.inactive(keyId: LogicalKeyboardKey.keyA.keyId),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final reason in [
    GlobalHotkeyReason.permissionDenied,
    GlobalHotkeyReason.conflict,
    GlobalHotkeyReason.failed,
  ]) {
    testWidgets(
      'retries hotkey registration on resume and settings open for ${reason.name}',
      (tester) async {
        if (reason == GlobalHotkeyReason.permissionDenied) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
        }
        var registerCalls = 0;
        var currentResponse = <String, Object?>{
          'ok': false,
          'reason': reason.name,
          'code': 5,
        };
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
          call,
        ) async {
          if (call.method == 'register') {
            registerCalls++;
            return currentResponse;
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
        final container = await _mountPtt(
          tester,
          controller,
          pttHotkey: LogicalKeyboardKey.keyA.keyId,
        );
        expect(registerCalls, 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(registerCalls, 2);

        container.read(routerProvider).go(AppRoutes.settings);
        await tester.pumpAndSettle();
        expect(registerCalls, 3);

        currentResponse = <String, Object?>{
          'ok': true,
          'reason': 'registered',
          'code': null,
        };
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(registerCalls, 4);
        expect(
          container.read(pttHotkeyStatusProvider).state,
          PttHotkeyState.registered,
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(registerCalls, 4);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final reason in [
    GlobalHotkeyReason.unsupportedPlatform,
    GlobalHotkeyReason.unsupportedKey,
  ]) {
    testWidgets('does not retry hotkey registration for ${reason.name}', (
      tester,
    ) async {
      var registerCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
        call,
      ) async {
        if (call.method == 'register') {
          registerCalls++;
          return <String, Object?>{
            'ok': false,
            'reason': reason.name,
            'code': null,
          };
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
      final container = await _mountPtt(
        tester,
        controller,
        pttHotkey: LogicalKeyboardKey.keyA.keyId,
      );
      expect(registerCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(registerCalls, 1);

      container.read(routerProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(registerCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('does not retry registration when PTT mode is inactive', (
    tester,
  ) async {
    var registerCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
      call,
    ) async {
      if (call.method == 'register') {
        registerCalls++;
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        hotkey,
        null,
      ),
    );

    final controller = _PttSession(initialPttMode: false);
    final container = await _mountPtt(
      tester,
      controller,
      pttHotkey: LogicalKeyboardKey.keyA.keyId,
    );
    expect(registerCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    container.read(routerProvider).go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(registerCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('releases held PTT on disconnect and detached lifecycle', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
      call,
    ) async {
      if (call.method == 'register') {
        return <String, Object?>{
          'ok': true,
          'reason': 'registered',
          'code': null,
        };
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
    await _mountPtt(
      tester,
      controller,
      pttHotkey: LogicalKeyboardKey.keyA.keyId,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    expect(controller.presses, [true]);

    // While native hotkey is registered, inactive keeps PTT active.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.presses, [true]);

    // Disconnecting immediately resets PTT.
    controller.setConnected(false);
    await tester.pump();
    expect(controller.presses, [true, false]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);

    // Reconnect, press again, and verify detached resets PTT even when native registered.
    controller.setConnected(true);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    expect(controller.presses, [true, false, true]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(controller.presses, [true, false, true, false]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'logs leveled hotkey errors, deduplicates NoticeCenter notices, and displays voice settings status',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final previousTalker = talker;
      final testTalker = Talker(
        logger: TalkerLogger(formatter: const PlainLoggerFormatter()),
        settings: TalkerSettings(useConsoleLogs: false),
      );
      talker = testTalker;
      addTearDown(() => talker = previousTalker);

      var channelResponse = <String, Object?>{
        'ok': false,
        'reason': 'conflict',
        'code': -9878,
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
        call,
      ) async {
        if (call.method == 'register') {
          return channelResponse;
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
      final container = await _mountPtt(
        tester,
        controller,
        pttHotkey: LogicalKeyboardKey.keyA.keyId,
      );

      final conflictLogs = testTalker.history
          .whereType<StructuredTalkerLog>()
          .where((log) => log.title == 'hotkey')
          .toList();
      expect(conflictLogs, hasLength(1));
      expect(conflictLogs.single.logLevel, LogLevel.warning);
      expect(
        conflictLogs.single.fields?['keyId'],
        LogicalKeyboardKey.keyA.keyId,
      );
      expect(
        conflictLogs.single.fields?['nativeCode'],
        nativePttKeyCode(LogicalKeyboardKey.keyA),
      );
      expect(conflictLogs.single.fields?['platform'], isA<String>());
      expect(conflictLogs.single.fields?['code'], -9878);

      expect(find.text('全局快捷键不可用，当前仅应用内生效'), findsOneWidget);

      // Retrying with the same failure reason does not duplicate NoticeCenter notices.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(container.read(noticeCenterProvider), hasLength(1));

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
      expect(find.text('A · 仅应用内'), findsOneWidget);

      // Switch to permissionDenied via key change and verify UI & NoticeCenter update.
      channelResponse = <String, Object?>{
        'ok': false,
        'reason': 'permissionDenied',
        'code': 5,
      };
      container
          .read(preferencesProvider.notifier)
          .setPttHotkey(LogicalKeyboardKey.keyB.keyId);
      await tester.pumpAndSettle();
      expect(find.text('B · 需要输入监控权限'), findsOneWidget);
      expect(find.text('全局快捷键需要输入监控权限，当前仅应用内生效'), findsOneWidget);
      expect(find.text('去授权'), findsOneWidget);

      // Switch to unsupportedPlatform and verify INFO log level (no new warning).
      final warningsBeforeUnsupported = testTalker.history
          .whereType<StructuredTalkerLog>()
          .where(
            (log) => log.title == 'hotkey' && log.logLevel == LogLevel.warning,
          )
          .length;
      channelResponse = <String, Object?>{
        'ok': false,
        'reason': 'unsupportedPlatform',
        'code': null,
      };
      container
          .read(preferencesProvider.notifier)
          .setPttHotkey(LogicalKeyboardKey.keyC.keyId);
      await tester.pumpAndSettle();

      final warningsAfterUnsupported = testTalker.history
          .whereType<StructuredTalkerLog>()
          .where(
            (log) => log.title == 'hotkey' && log.logLevel == LogLevel.warning,
          )
          .length;
      expect(warningsAfterUnsupported, warningsBeforeUnsupported);
      final infoLogs = testTalker.history
          .whereType<StructuredTalkerLog>()
          .where(
            (log) => log.title == 'hotkey' && log.logLevel == LogLevel.info,
          )
          .toList();
      expect(infoLogs, hasLength(1));
      expect(find.text('C · 仅应用内'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'does not prompt Input Monitoring on startup and requests permission when user activates PTT or taps authorize',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var requestPermissionCalls = 0;
      var openSettingsCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
        call,
      ) async {
        switch (call.method) {
          case 'register':
            return <String, Object?>{
              'ok': false,
              'reason': 'permissionDenied',
              'code': null,
            };
          case 'requestPermission':
            requestPermissionCalls++;
            return false;
          case 'openPermissionSettings':
            openSettingsCalls++;
            return true;
          default:
            return true;
        }
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hotkey,
          null,
        ),
      );

      // App launch with PTT already enabled must never trigger a system permission dialog.
      final startupController = _PttSession(initialPttMode: true);
      await _mountPtt(
        tester,
        startupController,
        pttHotkey: LogicalKeyboardKey.keyA.keyId,
      );
      expect(requestPermissionCalls, 0);
      expect(openSettingsCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Starting with PTT off, then actively enabling PTT triggers one permission request.
      final controller = _PttSession(initialPttMode: false);
      final container = await _mountPtt(
        tester,
        controller,
        pttHotkey: LogicalKeyboardKey.keyA.keyId,
      );
      expect(requestPermissionCalls, 0);

      await container.read(sessionViewProvider.notifier).setPttMode(true);
      await tester.pumpAndSettle();
      expect(requestPermissionCalls, 1);
      expect(openSettingsCalls, 0);

      // Resuming app does not repeat requestPermission; it tries registration directly.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(requestPermissionCalls, 1);

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

      final authorizeButton = find.text('去授权');
      expect(authorizeButton, findsOneWidget);
      await tester.tap(authorizeButton);
      await tester.pumpAndSettle();
      expect(requestPermissionCalls, 2);
      expect(openSettingsCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Linux permissionDenied does not auto-retry on resume or settings open, shows portal label, and manually retries on button tap',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var registerCalls = 0;
      var openSettingsCalls = 0;
      var currentResponse = <String, Object?>{
        'ok': false,
        'reason': 'permissionDenied',
        'code': 1,
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(hotkey, (
        call,
      ) async {
        switch (call.method) {
          case 'register':
            registerCalls++;
            return currentResponse;
          case 'openPermissionSettings':
            openSettingsCalls++;
            return true;
          default:
            return true;
        }
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hotkey,
          null,
        ),
      );

      final controller = _PttSession();
      final container = await _mountPtt(
        tester,
        controller,
        pttHotkey: LogicalKeyboardKey.keyA.keyId,
      );
      expect(registerCalls, 1);
      const portalNotice = '全局快捷键未授权，在系统设置中重置';
      expect(find.text(portalNotice), findsOneWidget);
      final initialNoticeId = container.read(noticeCenterProvider).single.id;

      // Resuming after cancelling a Portal prompt must not auto-retry.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(registerCalls, 1);

      // Opening Settings must not auto-retry either.
      container.read(routerProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(registerCalls, 1);

      final generalCategory = find.text('通用');
      await tester.ensureVisible(generalCategory);
      await tester.tap(generalCategory);
      await tester.pumpAndSettle();
      final voiceTile = find.text('语音');
      await tester.ensureVisible(voiceTile);
      await tester.tap(voiceTile);
      await tester.pumpAndSettle();

      expect(find.text('A · 全局快捷键未授权'), findsOneWidget);
      final authorizeButton = find.text('去授权');
      expect(authorizeButton, findsOneWidget);

      // Manual tap when PermissionStore silently returns permissionDenied re-notifies the reset guide.
      await tester.tap(authorizeButton);
      await tester.pumpAndSettle();
      expect(registerCalls, 2);
      expect(openSettingsCalls, 0);
      expect(
        container.read(noticeCenterProvider).single.id,
        greaterThan(initialNoticeId),
      );
      expect(find.text(portalNotice), findsOneWidget);

      // Once user resets permission in System Settings, tapping authorize registers cleanly.
      currentResponse = <String, Object?>{
        'ok': true,
        'reason': 'registered',
        'code': null,
      };
      await tester.tap(authorizeButton);
      await tester.pumpAndSettle();
      expect(registerCalls, 3);
      expect(openSettingsCalls, 0);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('去授权'), findsNothing);

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

  test('dark theme uses light system bar icons', () {
    final style = appSystemUiOverlayStyle(buildAppTheme(Brightness.dark));

    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
  });

  test('light theme uses dark system bar icons', () {
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
    'checks updates on startup when enabled, shows dialog once, opens release url, and does not recheck on about page',
    (tester) async {
      var checkCalls = 0;
      final opened = <String>[];
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_PttCore()),
          appVersionProvider.overrideWithValue('0.1.0'),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          sessionViewProvider.overrideWith(_PttSession.new),
          startupUpdateCheckEnabledProvider.overrideWithValue(true),
          externalUrlOpenerProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
          updateCheckClientProvider.overrideWithValue(({
            bool force = false,
          }) async {
            checkCalls++;
            return const UpdateStateView(
              available: true,
              latestVersion: '0.2.0',
              releaseUrl:
                  'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
              releaseNotes: '# 0.2.0 (2026-11-20): Release\n\n## 新增\n- 弹窗更新提示',
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
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.textContaining('v0.2.0'), findsOneWidget);
      expect(find.textContaining('弹窗更新提示'), findsOneWidget);
      expect(find.text('不再提醒'), findsOneWidget);
      expect(find.text('前往下载'), findsOneWidget);

      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();

      expect(opened, [
        'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
      ]);
      expect(find.text('发现新版本'), findsNothing);
      expect(container.read(preferencesProvider).autoCheckUpdate, isTrue);

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

  testWidgets(
    'disables autoCheckUpdate when clicking do not remind on startup update dialog',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_PttCore()),
          appVersionProvider.overrideWithValue('0.1.0'),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          sessionViewProvider.overrideWith(_PttSession.new),
          startupUpdateCheckEnabledProvider.overrideWithValue(true),
          updateCheckClientProvider.overrideWithValue(({
            bool force = false,
          }) async {
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

      expect(find.text('发现新版本'), findsOneWidget);
      await tester.tap(find.text('不再提醒'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本'), findsNothing);
      expect(container.read(preferencesProvider).autoCheckUpdate, isFalse);
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
        updateCheckClientProvider.overrideWithValue(({
          bool force = false,
        }) async {
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
    expect(find.text('发现新版本'), findsNothing);
  });

  testWidgets(
    'pushing a settings detail keeps the theme and restores the sidebar on back',
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

      // 二级页是覆盖侧栏的整页路由。
      expect(find.byType(AppNavigationSidebar), findsNothing);
      expect(
        identical(
          Theme.of(tester.element(find.byType(SettingsPage))),
          baselineTheme,
        ),
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byType(ScaffoldBar),
          matching: find.text('通用'),
        ),
        findsOneWidget,
      );

      final backButton = find.bySemanticsLabel(
        MaterialLocalizations.of(tester.element(find.byType(SettingsPage)))
            .backButtonTooltip,
      );
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(sidebarSurface().color, baselineSidebarColor);
      expect(find.text('通用'), findsOneWidget);
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
      expect(host.topInset, 32 + Sizes.header + 8);

      container.read(noticeCenterProvider.notifier)
        ..show('操作已完成', tone: NoticeTone.info)
        ..show('连接失败', tone: NoticeTone.error);
      await tester.pumpAndSettle();

      expect(find.text('操作已完成'), findsOneWidget);
      expect(find.text('连接失败'), findsOneWidget);

      // BannerHost 位于标题栏之上，topInset 计入 Windows 32px 标题栏，横幅从 32 + 56 = 88 下方展开。
      final topBannerY = tester.getTopLeft(find.text('连接失败')).dy;
      expect(topBannerY, greaterThanOrEqualTo(32 + Sizes.header + 8));
      expect(topBannerY, lessThan(32 + 32 + Sizes.header + 8));
    },
  );

  testWidgets(
    'TsClientApp defaults LiquidGlassScope off and switches quality from preferences',
    (tester) async {
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

      BuildContext scopeContext() =>
          tester.element(find.byType(Navigator).last);

      expect(LiquidGlassScope.of(scopeContext()), isFalse);

      container
          .read(preferencesProvider.notifier)
          .setLiquidGlass(LiquidGlassMode.standard);
      await tester.pump();
      expect(LiquidGlassScope.of(scopeContext()), isTrue);
      expect(
        LiquidGlassScope.qualityOf(scopeContext()),
        LiquidGlassQuality.standard,
      );

      container
          .read(preferencesProvider.notifier)
          .setLiquidGlass(LiquidGlassMode.ultra);
      await tester.pump();
      expect(LiquidGlassScope.of(scopeContext()), isTrue);
      expect(
        LiquidGlassScope.qualityOf(scopeContext()),
        LiquidGlassQuality.ultra,
      );

      container
          .read(preferencesProvider.notifier)
          .setLiquidGlass(LiquidGlassMode.none);
      await tester.pump();
      expect(LiquidGlassScope.of(scopeContext()), isFalse);
    },
  );

  testWidgets(
    'TsClientApp injects prism InputDecorationTheme and renders search TextField under LiquidGlassScope',
    (tester) async {
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
                liquidGlass: LiquidGlassMode.standard,
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

      await tester.tap(find.bySemanticsLabel('搜索服务器'));
      await tester.pumpAndSettle();

      final fieldFinder = find.byType(TextField);
      expect(fieldFinder, findsOneWidget);
      final fieldContext = tester.element(fieldFinder);
      expect(LiquidGlassScope.of(fieldContext), isTrue);
      expect(InputDecorationTheme.of(fieldContext).filled, isTrue);

      await tester.enterText(fieldFinder, 'local');
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TsClientApp clamps anomalous top padding and enforces transparent system bars',
    (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final darkStyle = appSystemUiOverlayStyle(buildAppTheme(Brightness.dark));
      expect(darkStyle.statusBarColor, Colors.transparent);
      expect(darkStyle.systemNavigationBarColor, Colors.transparent);
      expect(darkStyle.systemNavigationBarContrastEnforced, isTrue);

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

      tester.view.padding = const FakeViewPadding(top: 300, bottom: 24);
      addTearDown(tester.view.resetPadding);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TsClientApp(),
        ),
      );
      await tester.pumpAndSettle();

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is AnnotatedRegion<SystemUiOverlayStyle> &&
                  !widget.sized,
            )
            .first,
      );
      expect(region.sized, isFalse);

      // BuildContext inside PrismRootScope should see clamped top padding (20.0).
      final scopeContext = tester.element(find.byType(BannerHost));
      expect(MediaQuery.paddingOf(scopeContext).top, 20.0);

      // Normal status bar height (44.0 <= 800 * 0.3) is preserved untouched.
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 24);
      await tester.pumpAndSettle();
      expect(MediaQuery.paddingOf(scopeContext).top, 44.0);
    },
  );

  testWidgets(
    'crossing the compact breakpoint on macOS keeps the banner host state',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      container.read(noticeCenterProvider.notifier).show('连接失败：连接超时');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('连接失败：连接超时'), findsOneWidget);
      expect(container.read(noticeCenterProvider.notifier).forwardedId, 0);

      // 等错误横幅自动收起并完成退场动画。
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('连接失败：连接超时'), findsNothing);

      // 跨过 compact 断点：macOS 标题栏出现，BannerHost 与桥接状态必须保留。
      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();
      expect(find.text('连接失败：连接超时'), findsNothing);
    },
  );
}
