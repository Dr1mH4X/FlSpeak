// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目。
// 原始许可证：FlClash 应用代码为 GPL-3.0；其 plugins/window 插件为 MIT。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 本片段取自 plugins/window（MIT），可按 MIT 或 GPL-3.0 使用：对应
// plugins/window/lib/src/desktop_window.dart 的 startDragging、minimize、
// maximize、unmaximize、close、isMaximized、setAlwaysOnTop 以及窗口事件。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// `flspeak/window` 通道的 Dart 侧封装。
///
/// 把主题底色同步给桌面原生窗口（macOS NSWindow / Windows HWND）：
/// 标题栏与窗口边缘跟随当前主题底色。原生实现位于 macOS 与 Windows runner；
/// 没有实现的平台静默忽略。
class WindowChrome {
  const WindowChrome();

  static const MethodChannel _channel = MethodChannel('flspeak/window');

  /// 原生窗口是否处于全屏。窗口按钮让位与标题条留白都随它收起。
  static final ValueNotifier<bool> fullScreen = ValueNotifier<bool>(false);

  /// 原生窗口是否处于最大化状态。
  static final ValueNotifier<bool> isMaximized = ValueNotifier<bool>(false);

  /// 原生窗口是否置顶。
  static final ValueNotifier<bool> isPinned = ValueNotifier<bool>(false);

  static bool _attached = false;

  /// 挂上全屏及窗口事件并读一次初始状态。重复调用只挂一次。
  static void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onFullScreenChanged':
          fullScreen.value = call.arguments == true;
          break;
        case 'onEvent':
          final name = call.arguments is Map
              ? (call.arguments as Map)['name']?.toString()
              : call.arguments?.toString();
          switch (name) {
            case 'maximize':
              isMaximized.value = true;
              break;
            case 'unmaximize':
              isMaximized.value = false;
              break;
            case 'enter-full-screen':
              fullScreen.value = true;
              break;
            case 'leave-full-screen':
              fullScreen.value = false;
              break;
            case 'activate':
              unawaited(focus());
              break;
          }
          break;
      }
    });
    unawaited(_syncState());
  }

  static Future<void> _syncState() async {
    try {
      fullScreen.value =
          await _channel.invokeMethod<bool>('isFullScreen') ?? false;
      isMaximized.value =
          await _channel.invokeMethod<bool>('isMaximized') ?? false;
      isPinned.value =
          await _channel.invokeMethod<bool>('isAlwaysOnTop') ?? false;
    } on PlatformException {
      // 原生侧拒绝时保持窗口默认状态。
    } on MissingPluginException {
      // 非桌面平台没有原生实现。
    }
  }

  /// 从指针按下处开始拖动窗口。窗口顶部条与轨道顶部留白共用。
  static Future<void> startDragging() async {
    try {
      await _channel.invokeMethod<void>('startDragging');
    } on PlatformException {
      // 指针事件已经结束，原生侧拒绝这次拖动。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 双击标题条缩放窗口；全屏时先退出全屏。
  static Future<void> toggleZoom() async {
    try {
      await _channel.invokeMethod<void>('toggleZoom');
    } on PlatformException {
      // 原生侧拒绝时保持当前窗口尺寸。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 最小化窗口。
  static Future<void> minimize() async {
    try {
      await _channel.invokeMethod<void>('minimize');
    } on PlatformException {
      // 原生侧拒绝。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 最大化窗口。
  static Future<void> maximize() async {
    try {
      await _channel.invokeMethod<void>('maximize');
      isMaximized.value = true;
    } on PlatformException {
      // 原生侧拒绝。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 取消最大化（还原窗口）。
  static Future<void> unmaximize() async {
    try {
      await _channel.invokeMethod<void>('unmaximize');
      isMaximized.value = false;
    } on PlatformException {
      // 原生侧拒绝。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 切换最大化与还原状态。
  static Future<void> toggleMaximize() async {
    if (fullScreen.value) {
      await setFullScreen(false);
    } else if (isMaximized.value) {
      await unmaximize();
    } else {
      await maximize();
    }
  }

  /// 关闭窗口。
  static Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException {
      // 原生侧拒绝。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 激活并聚焦窗口。
  static Future<void> focus() async {
    try {
      await _channel.invokeMethod<void>('focus');
    } on PlatformException {
      // 原生侧拒绝。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 设置全屏状态。
  static Future<void> setFullScreen(bool value) async {
    try {
      await _channel.invokeMethod<void>('setFullScreen', value);
      fullScreen.value = value;
    } on PlatformException {
      // 原生侧拒绝。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 查询窗口是否置顶。
  static Future<bool> isAlwaysOnTop() async {
    try {
      return await _channel.invokeMethod<bool>('isAlwaysOnTop') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 设置窗口置顶状态。
  static Future<void> setAlwaysOnTop(bool value) async {
    try {
      await _channel.invokeMethod<void>('setAlwaysOnTop', value);
      isPinned.value = value;
    } on PlatformException {
      // 原生侧拒绝。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 切换置顶状态。
  static Future<void> togglePin() async {
    final current = await isAlwaysOnTop();
    await setAlwaysOnTop(!current);
  }

  /// 查询是否支持指定的窗口特效（如 mica、acrylic、blur）。
  static Future<bool> isEffectSupported(String effect) async {
    try {
      return await _channel.invokeMethod<bool>('isEffectSupported', effect) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 设置窗口系统材质特效。
  static Future<void> setEffect(
    String effect, {
    int? tint,
    Brightness? brightness,
  }) async {
    try {
      final Map<String, Object?> args = {'effect': effect};
      if (tint != null) {
        args['tint'] = tint;
      }
      if (brightness != null) {
        args['brightness'] = brightness.name;
      }
      await _channel.invokeMethod<void>('setEffect', args);
    } on PlatformException {
      // 平台不支持时静默。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }

  /// 用主题的 surface 色刷新窗口底色。
  Future<void> setBackground(int argb) async {
    try {
      await _channel.invokeMethod<void>('setBackgroundColor', argb);
    } on PlatformException {
      // 原生侧拒绝（参数异常）时保持系统底色即可。
    } on MissingPluginException {
      // 没有原生实现。
    }
  }
}
