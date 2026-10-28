// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目。
// 原始许可证：FlClash 应用代码为 GPL-3.0；其 plugins/window 插件为 MIT。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 本片段取自 plugins/window（MIT），可按 MIT 或 GPL-3.0 使用：对应
// plugins/window/lib/src/desktop_window.dart 的 startDragging 调用，以及同目录的
// 窗口全屏事件。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// `flspeak/window` 通道的 Dart 侧封装。
///
/// 把主题底色同步给桌面原生窗口（macOS NSWindow）：标题栏与窗口圆角边缘
/// 的底色跟随当前主题，不再露出系统默认的窗口背景色。原生实现只存在于
/// macOS runner；没有实现的平台静默忽略。
class WindowChrome {
  const WindowChrome();

  static const MethodChannel _channel = MethodChannel('flspeak/window');

  /// 原生窗口是否处于全屏。窗口按钮让位与标题条留白都随它收起。
  static final ValueNotifier<bool> fullScreen = ValueNotifier<bool>(false);

  static bool _attached = false;

  /// 挂上全屏事件并读一次初始状态。重复调用只挂一次。
  static void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFullScreenChanged') {
        fullScreen.value = call.arguments == true;
      }
    });
    unawaited(_syncFullScreen());
  }

  static Future<void> _syncFullScreen() async {
    try {
      fullScreen.value =
          await _channel.invokeMethod<bool>('isFullScreen') ?? false;
    } on PlatformException {
      // 原生侧拒绝时保持窗口模式。
    } on MissingPluginException {
      // 非 macOS 平台没有原生实现。
    }
  }

  /// 从指针按下处开始拖动窗口。窗口顶部条与轨道顶部留白共用。
  static Future<void> startDragging() async {
    try {
      await _channel.invokeMethod<void>('startDragging');
    } on PlatformException {
      // 指针事件已经结束，原生侧拒绝这次拖动。
    } on MissingPluginException {
      // 非 macOS 平台没有原生实现。
    }
  }

  /// 双击标题条缩放窗口；全屏时先退出全屏。
  static Future<void> toggleZoom() async {
    try {
      await _channel.invokeMethod<void>('toggleZoom');
    } on PlatformException {
      // 原生侧拒绝时保持当前窗口尺寸。
    } on MissingPluginException {
      // 非 macOS 平台没有原生实现。
    }
  }

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
