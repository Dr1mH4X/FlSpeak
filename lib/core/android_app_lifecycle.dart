import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logging/logger.dart';

abstract interface class AndroidAppLifecycleGateway {
  Future<bool> moveToBackground();

  Future<void> exitApp();
}

/// 通过原生 `MainActivity` MethodChannel 与 Flutter 系统通道处理 Android 退后台与退出。
class AndroidAppLifecycle implements AndroidAppLifecycleGateway {
  const AndroidAppLifecycle({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'flspeak/app_lifecycle',
  );

  final MethodChannel _channel;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> moveToBackground() async {
    if (!_isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('moveToBackground') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      logWarn('Android 退回后台失败', target: 'app', error: error);
      return false;
    }
  }

  @override
  Future<void> exitApp() => SystemNavigator.pop();
}
