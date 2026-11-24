import 'package:flspeak/core/platform/android_app_lifecycle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lifecycleChannel = MethodChannel('flspeak/app_lifecycle');
  const lifecycle = AndroidAppLifecycle();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lifecycleChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('moves app to background on Android and invokes SystemNavigator.pop on exit', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    final lifecycleCalls = <String>[];
    final platformCalls = <String>[];
    messenger.setMockMethodCallHandler(lifecycleChannel, (call) async {
      lifecycleCalls.add(call.method);
      return call.method == 'moveToBackground';
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call.method);
      return null;
    });

    expect(await lifecycle.moveToBackground(), isTrue);
    await lifecycle.exitApp();

    expect(lifecycleCalls, ['moveToBackground']);
    expect(platformCalls, ['SystemNavigator.pop']);
  });

  test('skips moveToBackground channel outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lifecycleChannel, (call) async {
          called = true;
          return true;
        });

    expect(await lifecycle.moveToBackground(), isFalse);
    expect(called, isFalse);
  });
}
