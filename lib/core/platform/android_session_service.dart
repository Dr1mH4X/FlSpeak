import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logging/logger.dart';

enum AndroidSessionServiceAction {
  toggleMute,
  stopScreenShare,
  disconnect;

  static AndroidSessionServiceAction? fromWire(Object? raw) => switch (raw) {
    'toggleMute' => AndroidSessionServiceAction.toggleMute,
    'stopScreenShare' => AndroidSessionServiceAction.stopScreenShare,
    'disconnect' => AndroidSessionServiceAction.disconnect,
    _ => null,
  };
}

@immutable
class AndroidSessionNotificationState {
  const AndroidSessionNotificationState({
    required this.title,
    required this.subtitle,
    required this.channelName,
    required this.muteActionLabel,
    required this.stopScreenShareActionLabel,
    required this.disconnectActionLabel,
    required this.isMuted,
    required this.isSharingScreen,
    this.includeMediaProjection = false,
    required this.sessionEpoch,
  });

  final String title;
  final String subtitle;
  final String channelName;
  final String muteActionLabel;
  final String stopScreenShareActionLabel;
  final String disconnectActionLabel;
  final bool isMuted;
  final bool isSharingScreen;
  final bool includeMediaProjection;
  final int sessionEpoch;

  Map<String, Object?> toArguments() => <String, Object?>{
    'title': title,
    'subtitle': subtitle,
    'channelName': channelName,
    'muteActionLabel': muteActionLabel,
    'stopScreenShareActionLabel': stopScreenShareActionLabel,
    'disconnectActionLabel': disconnectActionLabel,
    'isMuted': isMuted,
    'isSharingScreen': isSharingScreen,
    'includeMediaProjection': includeMediaProjection,
    'sessionEpoch': sessionEpoch,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AndroidSessionNotificationState &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.channelName == channelName &&
          other.muteActionLabel == muteActionLabel &&
          other.stopScreenShareActionLabel == stopScreenShareActionLabel &&
          other.disconnectActionLabel == disconnectActionLabel &&
          other.isMuted == isMuted &&
          other.isSharingScreen == isSharingScreen &&
          other.includeMediaProjection == includeMediaProjection &&
          other.sessionEpoch == sessionEpoch;

  @override
  int get hashCode => Object.hash(
    title,
    subtitle,
    channelName,
    muteActionLabel,
    stopScreenShareActionLabel,
    disconnectActionLabel,
    isMuted,
    isSharingScreen,
    includeMediaProjection,
    sessionEpoch,
  );
}

abstract interface class AndroidSessionServiceGateway {
  bool get isSupported;

  Future<bool> requestNotificationPermission();

  Future<bool> syncSession(AndroidSessionNotificationState state);

  Future<void> stopSession();

  Stream<AndroidSessionServiceAction> get actions;
}

/// 通过原生 `MainActivity` 通道管理 Android 会话前台服务、通知栏状态与快捷控制动作。
class AndroidSessionService implements AndroidSessionServiceGateway {
  const AndroidSessionService({
    MethodChannel? methodChannel,
    EventChannel? actionEventChannel,
  }) : _methodChannel = methodChannel ?? _defaultMethodChannel,
       _actionEventChannel = actionEventChannel ?? _defaultActionEventChannel;

  static const MethodChannel _defaultMethodChannel = MethodChannel(
    'flspeak/session_service',
  );
  static const EventChannel _defaultActionEventChannel = EventChannel(
    'flspeak/session_service_actions',
  );

  final MethodChannel _methodChannel;
  final EventChannel _actionEventChannel;

  @override
  bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          debugDefaultTargetPlatformOverride == TargetPlatform.android);

  @override
  Future<bool> requestNotificationPermission() async {
    if (!isSupported) {
      return true;
    }
    try {
      return await _methodChannel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return true;
    } on PlatformException catch (error) {
      logWarn(
        'failed to request Android notification permission',
        target: 'app',
        error: error,
      );
      return false;
    }
  }

  @override
  Future<bool> syncSession(AndroidSessionNotificationState state) async {
    if (!isSupported) {
      return false;
    }
    try {
      return await _methodChannel.invokeMethod<bool>(
            'syncSession',
            state.toArguments(),
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      logWarn(
        'failed to sync Android session foreground service',
        target: 'app',
        error: error,
      );
      return false;
    }
  }

  @override
  Future<void> stopSession() async {
    if (!isSupported) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('stopSession');
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      logWarn(
        'failed to stop Android session foreground service',
        target: 'app',
        error: error,
      );
    }
  }

  @override
  Stream<AndroidSessionServiceAction> get actions {
    if (!isSupported) {
      return const Stream<AndroidSessionServiceAction>.empty();
    }
    return _actionEventChannel
        .receiveBroadcastStream()
        .map(AndroidSessionServiceAction.fromWire)
        .where((action) => action != null)
        .cast<AndroidSessionServiceAction>()
        .handleError((Object error, StackTrace stackTrace) {
          if (error is MissingPluginException) {
            return;
          }
          logWarn(
            'failed to observe Android session notification actions',
            target: 'app',
            error: error,
          );
        });
  }
}
