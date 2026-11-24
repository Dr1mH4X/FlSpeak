import 'package:flspeak/core/platform/android_audio_permission.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flspeak/audio_permissions');
  const permission = AndroidAudioPermission();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps Android permission outcomes and openAppSettings calls', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    final methods = <String>[];
    var nextStatus = 'granted';
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return switch (call.method) {
        'requestMicrophonePermission' => nextStatus,
        'openAppSettings' => true,
        _ => null,
      };
    });

    expect(permission.enforcesRuntimePermission, isTrue);
    expect(await permission.request(), MicrophonePermissionStatus.granted);

    nextStatus = 'denied';
    expect(await permission.request(), MicrophonePermissionStatus.denied);

    nextStatus = 'permanentlyDenied';
    expect(
      await permission.request(),
      MicrophonePermissionStatus.permanentlyDenied,
    );

    expect(await permission.openSettings(), isTrue);
    expect(methods, [
      'requestMicrophonePermission',
      'requestMicrophonePermission',
      'requestMicrophonePermission',
      'openAppSettings',
    ]);
  });

  test('skips method channel outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called = true;
          return 'denied';
        });

    expect(permission.enforcesRuntimePermission, isFalse);
    expect(await permission.request(), MicrophonePermissionStatus.granted);
    expect(await permission.openSettings(), isFalse);
    expect(called, isFalse);
  });
}
