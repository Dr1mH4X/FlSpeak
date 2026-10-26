import 'package:flutter/services.dart';

/// `flspeak/window` 通道的 Dart 侧封装。
///
/// 把主题底色同步给桌面原生窗口（macOS NSWindow）：标题栏与窗口圆角边缘
/// 的底色跟随当前主题，不再露出系统默认的窗口背景色。原生实现只存在于
/// macOS runner；没有实现的平台静默忽略。
class WindowChrome {
  const WindowChrome();

  static const MethodChannel _channel = MethodChannel('flspeak/window');

  /// 用主题的 surface 色刷新窗口底色。
  Future<void> setBackground(int argb) async {
    try {
      await _channel.invokeMethod<void>('setBackgroundColor', argb);
    } on PlatformException {
      // 原生侧拒绝（参数异常）时保持系统底色即可。
    } on MissingPluginException {
      // 非 macOS 平台没有原生实现。
    }
  }
}
