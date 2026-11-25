import 'package:flspeak/core/platform/android_session_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('flspeak/session_service');
  const eventChannel = EventChannel('flspeak/session_service_actions');
  const service = AndroidSessionService();

  const sampleState = AndroidSessionNotificationState(
    title: 'Voice · Lobby',
    subtitle: 'In voice',
    channelName: 'Voice session',
    muteActionLabel: 'Mute',
    stopScreenShareActionLabel: 'Stop sharing',
    disconnectActionLabel: 'Disconnect',
    isMuted: false,
    isSharingScreen: false,
    includeMediaProjection: false,
    sessionEpoch: 2,
  );

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  test(
    'invokes Android session service channels and maps action events',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      final calls = <MethodCall>[];
      var permissionResult = true;
      var syncResult = true;
      var throwPlatformError = false;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        if (throwPlatformError) {
          throw PlatformException(code: 'failed', message: 'error');
        }
        return switch (call.method) {
          'requestNotificationPermission' => permissionResult,
          'syncSession' => syncResult,
          'stopSession' => null,
          _ => null,
        };
      });

      messenger.setMockStreamHandler(
        eventChannel,
        _FakeActionStreamHandler((events) {
          events.success('toggleMute');
          events.success('unknownAction');
          events.success('stopScreenShare');
          events.success('disconnect');
        }),
      );

      expect(service.isSupported, isTrue);
      expect(await service.requestNotificationPermission(), isTrue);

      permissionResult = false;
      expect(await service.requestNotificationPermission(), isFalse);

      expect(await service.syncSession(sampleState), isTrue);
      syncResult = false;
      expect(await service.syncSession(sampleState), isFalse);

      await service.stopSession();

      throwPlatformError = true;
      expect(await service.requestNotificationPermission(), isFalse);
      expect(await service.syncSession(sampleState), isFalse);
      await service.stopSession();

      final observed = await service.actions.take(3).toList();
      expect(observed, const [
        AndroidSessionServiceAction.toggleMute,
        AndroidSessionServiceAction.stopScreenShare,
        AndroidSessionServiceAction.disconnect,
      ]);

      expect(calls[0].method, 'requestNotificationPermission');
      expect(calls[2].method, 'syncSession');
      expect(calls[2].arguments, <String, Object?>{
        'title': 'Voice · Lobby',
        'subtitle': 'In voice',
        'channelName': 'Voice session',
        'muteActionLabel': 'Mute',
        'stopScreenShareActionLabel': 'Stop sharing',
        'disconnectActionLabel': 'Disconnect',
        'isMuted': false,
        'isSharingScreen': false,
        'includeMediaProjection': false,
        'sessionEpoch': 2,
      });
      expect(calls[4].method, 'stopSession');
    },
  );

  test('is a complete no-op outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    var methodCalled = false;
    var streamListened = false;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      methodCalled = true;
      return true;
    });
    messenger.setMockStreamHandler(
      eventChannel,
      _FakeActionStreamHandler((_) {
        streamListened = true;
      }),
    );

    expect(service.isSupported, isFalse);
    expect(await service.requestNotificationPermission(), isTrue);
    expect(await service.syncSession(sampleState), isFalse);
    await service.stopSession();
    expect(await service.actions.toList(), isEmpty);
    expect(methodCalled, isFalse);
    expect(streamListened, isFalse);
  });

  test('notification state compares fields by value', () {
    const copy = AndroidSessionNotificationState(
      title: 'Voice · Lobby',
      subtitle: 'In voice',
      channelName: 'Voice session',
      muteActionLabel: 'Mute',
      stopScreenShareActionLabel: 'Stop sharing',
      disconnectActionLabel: 'Disconnect',
      isMuted: false,
      isSharingScreen: false,
      includeMediaProjection: false,
      sessionEpoch: 2,
    );
    const modified = AndroidSessionNotificationState(
      title: 'Voice · Lobby',
      subtitle: 'Muted',
      channelName: 'Voice session',
      muteActionLabel: 'Unmute',
      stopScreenShareActionLabel: 'Stop sharing',
      disconnectActionLabel: 'Disconnect',
      isMuted: true,
      isSharingScreen: false,
      includeMediaProjection: true,
      sessionEpoch: 2,
    );

    expect(sampleState, copy);
    expect(sampleState.hashCode, copy.hashCode);
    expect(sampleState, isNot(modified));
  });
}

class _FakeActionStreamHandler extends MockStreamHandler {
  _FakeActionStreamHandler(this.onListenCallback);

  final void Function(MockStreamHandlerEventSink events) onListenCallback;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    onListenCallback(events);
  }

  @override
  void onCancel(Object? arguments) {}
}
