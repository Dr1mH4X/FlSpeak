import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logging/logger.dart';

enum MicrophonePermissionStatus { granted, denied, permanentlyDenied }

abstract interface class MicrophonePermissionGateway {
  bool get enforcesRuntimePermission;

  Future<MicrophonePermissionStatus> request();

  Future<bool> openSettings();
}

/// 通过原生 `MainActivity` MethodChannel 检查与申请 Android 录音权限。
class AndroidAudioPermission implements MicrophonePermissionGateway {
  const AndroidAudioPermission({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'flspeak/audio_permissions',
  );

  final MethodChannel _channel;

  @override
  bool get enforcesRuntimePermission =>
      !kIsWeb &&
      (Platform.isAndroid ||
          debugDefaultTargetPlatformOverride == TargetPlatform.android);

  @override
  Future<MicrophonePermissionStatus> request() async {
    if (!enforcesRuntimePermission) {
      return MicrophonePermissionStatus.granted;
    }
    try {
      final raw = await _channel.invokeMethod<String>(
        'requestMicrophonePermission',
      );
      return switch (raw) {
        'granted' => MicrophonePermissionStatus.granted,
        'permanentlyDenied' => MicrophonePermissionStatus.permanentlyDenied,
        _ => MicrophonePermissionStatus.denied,
      };
    } on MissingPluginException {
      return MicrophonePermissionStatus.granted;
    } on PlatformException catch (error) {
      logWarn(
        'failed to request Android recording permission',
        target: 'app',
        error: error,
      );
      return MicrophonePermissionStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    if (!enforcesRuntimePermission) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      logWarn(
        'failed to open Android app settings',
        target: 'app',
        error: error,
      );
      return false;
    }
  }
}
