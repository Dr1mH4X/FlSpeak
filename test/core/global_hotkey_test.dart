import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/global_hotkey.dart';
import 'package:flspeak/core/hotkey_codes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flspeak/global_hotkey');
  const hotkey = GlobalHotkey();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('GlobalHotkeyResult.fromChannel', () {
    test('parses every GlobalHotkeyReason and native code', () {
      final cases = <(GlobalHotkeyReason, bool, int?)>[
        (GlobalHotkeyReason.registered, true, null),
        (GlobalHotkeyReason.unsupportedPlatform, false, null),
        (GlobalHotkeyReason.unsupportedKey, false, null),
        (GlobalHotkeyReason.conflict, false, -9878),
        (GlobalHotkeyReason.permissionDenied, false, 5),
        (GlobalHotkeyReason.failed, false, 10),
      ];

      for (final (reason, ok, code) in cases) {
        final result = GlobalHotkeyResult.fromChannel(<String, Object?>{
          'ok': ok,
          'reason': reason.name,
          'code': code,
        });
        expect(result, GlobalHotkeyResult(ok: ok, reason: reason, code: code));
      }
    });

    test('supports legacy bool responses and malformed fallbacks', () {
      expect(
        GlobalHotkeyResult.fromChannel(true),
        const GlobalHotkeyResult(
          ok: true,
          reason: GlobalHotkeyReason.registered,
        ),
      );
      expect(
        GlobalHotkeyResult.fromChannel(false),
        const GlobalHotkeyResult(ok: false, reason: GlobalHotkeyReason.failed),
      );
      expect(
        GlobalHotkeyResult.fromChannel(<String, Object?>{
          'ok': false,
          'reason': 'unexpected',
          'code': 42,
        }),
        const GlobalHotkeyResult(
          ok: false,
          reason: GlobalHotkeyReason.failed,
          code: 42,
        ),
      );
      expect(
        GlobalHotkeyResult.fromChannel('bad'),
        const GlobalHotkeyResult(ok: false, reason: GlobalHotkeyReason.failed),
      );
    });
  });

  group('GlobalHotkey channel calls', () {
    test('register maps every structured channel reason', () async {
      final responses = <Map<String, Object?>>[
        {'ok': true, 'reason': 'registered', 'code': null},
        {'ok': false, 'reason': 'unsupportedPlatform', 'code': null},
        {'ok': false, 'reason': 'unsupportedKey', 'code': null},
        {'ok': false, 'reason': 'conflict', 'code': -9878},
        {'ok': false, 'reason': 'permissionDenied', 'code': 5},
        {'ok': false, 'reason': 'failed', 'code': 1400},
      ];
      var index = 0;
      final calls = <Object?>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'register') {
              calls.add(call.arguments);
              return responses[index++];
            }
            return null;
          });

      for (var i = 0; i < responses.length; i++) {
        final expected = GlobalHotkeyResult.fromChannel(responses[i]);
        final actual = await hotkey.register(0x41 + i);
        expect(actual, expected);
      }
      expect(calls, [0x41, 0x42, 0x43, 0x44, 0x45, 0x46]);
    });

    test(
      'register handles null, MissingPluginException, and PlatformException',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        expect(
          await hotkey.register(0x41),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.unsupportedPlatform,
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        expect(
          await hotkey.register(0x41),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.unsupportedPlatform,
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => throw PlatformException(code: 'ERR'),
            );
        expect(
          await hotkey.register(0x41),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.failed,
          ),
        );
      },
    );

    test(
      'registerByKeyId checks null keyId, platform support, and key support',
      () async {
        var unregisters = 0;
        final registeredCodes = <Object?>[];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'unregister') {
                unregisters++;
                return true;
              }
              if (call.method == 'register') {
                registeredCodes.add(call.arguments);
                return <String, Object?>{
                  'ok': true,
                  'reason': 'registered',
                  'code': null,
                };
              }
              return null;
            });

        expect(
          await hotkey.registerByKeyId(null, operatingSystem: 'macos'),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.unsupportedKey,
          ),
        );
        expect(
          await hotkey.registerByKeyId(
            LogicalKeyboardKey.keyA.keyId,
            operatingSystem: 'android',
          ),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.unsupportedPlatform,
          ),
        );
        expect(
          await hotkey.registerByKeyId(
            LogicalKeyboardKey.keyA.keyId,
            operatingSystem: 'ios',
          ),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.unsupportedPlatform,
          ),
        );
        expect(
          await hotkey.registerByKeyId(
            LogicalKeyboardKey.insert.keyId,
            operatingSystem: 'macos',
          ),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.unsupportedKey,
          ),
        );
        expect(
          await hotkey.registerByKeyId(
            LogicalKeyboardKey.shiftLeft.keyId,
            operatingSystem: 'windows',
          ),
          const GlobalHotkeyResult(
            ok: false,
            reason: GlobalHotkeyReason.unsupportedKey,
          ),
        );
        expect(unregisters, 5);
        expect(registeredCodes, isEmpty);

        expect(
          await hotkey.registerByKeyId(
            LogicalKeyboardKey.insert.keyId,
            operatingSystem: 'windows',
          ),
          const GlobalHotkeyResult(
            ok: true,
            reason: GlobalHotkeyReason.registered,
          ),
        );
        expect(
          await hotkey.registerByKeyId(
            LogicalKeyboardKey.keyA.keyId,
            operatingSystem: 'linux',
          ),
          const GlobalHotkeyResult(
            ok: true,
            reason: GlobalHotkeyReason.registered,
          ),
        );
        expect(registeredCodes, [
          nativePttKeyCode(
            LogicalKeyboardKey.insert,
            operatingSystem: 'windows',
          ),
          nativePttKeyCode(LogicalKeyboardKey.keyA, operatingSystem: 'linux'),
        ]);
      },
    );

    test('requestPermission and openPermissionSettings forward channel booleans and degrade on errors', () async {
      var requestResult = true;
      var openSettingsResult = true;
      final methods = <String>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return switch (call.method) {
              'requestPermission' => requestResult,
              'openPermissionSettings' => openSettingsResult,
              _ => null,
            };
          });

      expect(await hotkey.requestPermission(), isTrue);
      expect(await hotkey.openPermissionSettings(), isTrue);
      expect(methods, ['requestPermission', 'openPermissionSettings']);

      requestResult = false;
      openSettingsResult = false;
      expect(await hotkey.requestPermission(), isFalse);
      expect(await hotkey.openPermissionSettings(), isFalse);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await hotkey.requestPermission(), isFalse);
      expect(await hotkey.openPermissionSettings(), isFalse);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'ERR'),
          );
      expect(await hotkey.requestPermission(), isFalse);
      expect(await hotkey.openPermissionSettings(), isFalse);
    });
  });

  group('PttHotkeyStatus & controller', () {
    test('retry and in-app-only flags match state semantics', () {
      const inactive = PttHotkeyStatus.inactive(keyId: 1);
      expect(inactive.isRegistered, isFalse);
      expect(inactive.shouldRetry, isFalse);
      expect(inactive.isInAppOnly, isFalse);

      final registered = PttHotkeyStatus.fromResult(
        const GlobalHotkeyResult(
          ok: true,
          reason: GlobalHotkeyReason.registered,
        ),
        keyId: 1,
        nativeCode: 0,
      );
      expect(registered.isRegistered, isTrue);
      expect(registered.shouldRetry, isFalse);
      expect(registered.isInAppOnly, isFalse);

      final permissionDenied = PttHotkeyStatus.fromResult(
        const GlobalHotkeyResult(
          ok: false,
          reason: GlobalHotkeyReason.permissionDenied,
          code: 5,
        ),
        keyId: 1,
        nativeCode: 0,
      );
      expect(permissionDenied.isRegistered, isFalse);
      expect(permissionDenied.shouldRetry, isTrue);
      expect(permissionDenied.isInAppOnly, isFalse);

      for (final reason in [
        GlobalHotkeyReason.conflict,
        GlobalHotkeyReason.failed,
      ]) {
        final status = PttHotkeyStatus.fromResult(
          GlobalHotkeyResult(ok: false, reason: reason, code: 12),
        );
        expect(status.shouldRetry, isTrue);
        expect(status.isInAppOnly, isTrue);
      }

      for (final reason in [
        GlobalHotkeyReason.unsupportedPlatform,
        GlobalHotkeyReason.unsupportedKey,
      ]) {
        final status = PttHotkeyStatus.fromResult(
          GlobalHotkeyResult(ok: false, reason: reason),
        );
        expect(status.shouldRetry, isFalse);
        expect(status.isInAppOnly, isTrue);
      }
    });

    test('controller updates status and invokes attached retry handler', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(pttHotkeyStatusProvider),
        const PttHotkeyStatus.inactive(),
      );

      var retries = 0;
      void onRetry() => retries++;

      final controller = container.read(pttHotkeyStatusProvider.notifier);
      controller.attachRetryHandler(onRetry);
      controller.requestRetry();
      expect(retries, 1);

      controller.setStatus(
        const PttHotkeyStatus(
          state: PttHotkeyState.conflict,
          keyId: 0x61,
          nativeCode: 0x00,
          errorCode: -9878,
        ),
      );
      expect(
        container.read(pttHotkeyStatusProvider).state,
        PttHotkeyState.conflict,
      );

      controller.detachRetryHandler(onRetry);
      controller.requestRetry();
      expect(retries, 1);
    });
  });
}
