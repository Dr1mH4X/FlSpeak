import 'package:flutter/services.dart';

import 'hotkey_codes.dart';

/// `flspeak/global_hotkey` 通道的 Dart 侧封装。
///
/// 原生实现只存在于桌面 runner（macOS Carbon、Windows 低级键盘钩子、Linux
/// X11 XGrabKey）；没有实现的平台 `register` 返回 false，调用方退到应用内
/// 按键兜底。按键事件由原生推到 [setHandler] 注册的回调。
class GlobalHotkey {
  const GlobalHotkey();

  static const MethodChannel _channel = MethodChannel('flspeak/global_hotkey');

  /// 设置原生事件的接收端；不传参即清除。
  void setHandler({void Function()? onKeyDown, void Function()? onKeyUp}) {
    if (onKeyDown == null && onKeyUp == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onKeyDown':
          onKeyDown?.call();
        case 'onKeyUp':
          onKeyUp?.call();
      }
      return null;
    });
  }

  /// 注册全局热键。`code` 的含义由平台决定（macOS Carbon 键码 / Windows VK /
  /// X11 键码），返回是否注册成功。
  Future<bool> register(int code) async {
    try {
      return await _channel.invokeMethod<bool>('register', code) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 注销全局热键；没注册过或平台不支持时静默成功。
  Future<void> unregister() async {
    try {
      await _channel.invokeMethod<void>('unregister');
    } on PlatformException {
      // 平台不支持或未注册。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// 便捷方法：按持久化的 `LogicalKeyboardKey.keyId` 注册到当前平台。
  /// `null` 或不支持的键都退回「未注册」。
  Future<bool> registerByKeyId(int? keyId) async {
    final key = keyId == null ? null : LogicalKeyboardKey.findKeyByKeyId(keyId);
    final code = key == null ? null : nativePttKeyCode(key);
    if (code == null) {
      await unregister();
      return false;
    }
    return register(code);
  }
}
