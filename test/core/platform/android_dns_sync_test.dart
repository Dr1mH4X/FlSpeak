import 'package:flspeak/core/platform/android_dns_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('flspeak/network_dns');
  const eventChannel = EventChannel('flspeak/network_dns_events');

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await AndroidDnsSync.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  test('syncs initial and updated DNS servers on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'getDnsServers');
      return <String>['223.6.6.6', '119.29.29.29'];
    });

    final handler = _FakeDnsStreamHandler(
      onListenCallback: (events) {
        events.success(<String>['192.168.31.1']);
      },
    );
    messenger.setMockStreamHandler(eventChannel, handler);

    final updates = <List<String>>[];
    await AndroidDnsSync.initialize(onUpdate: updates.add);
    await pumpEventQueue();

    expect(updates, [
      ['223.6.6.6', '119.29.29.29'],
      ['192.168.31.1'],
    ]);
  });

  test('skips platform channels outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var methodCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          methodCalled = true;
          return <String>[];
        });

    final updates = <List<String>>[];
    await AndroidDnsSync.initialize(onUpdate: updates.add);

    expect(methodCalled, isFalse);
    expect(updates, isEmpty);
  });
}

class _FakeDnsStreamHandler extends MockStreamHandler {
  _FakeDnsStreamHandler({required this.onListenCallback});

  final void Function(MockStreamHandlerEventSink events) onListenCallback;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    onListenCallback(events);
  }

  @override
  void onCancel(Object? arguments) {}
}
