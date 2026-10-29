// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'app.dart';
import 'theme/app_theme.dart';
import 'core/models.dart';
import 'core/providers.dart';
import 'core/preferences.dart';
import 'router.dart';

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
      storePathProvider.overrideWithValue('/tmp/flspeak-test/servers.json'),
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
}
