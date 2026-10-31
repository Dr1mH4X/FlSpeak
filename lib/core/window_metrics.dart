// 本文件来源于 FlClash（https://github.com/chen08209/FlClash）项目，原始许可证为 GPL-3.0。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7
// 对应原文件：lib/common/layout.dart

import 'dart:ui' show Size;

/// macOS 红绿灯按钮在窗口左上角占用的区域，实测横向 9 到 69。
const macOSTrafficLightsArea = Size(78, 32);

/// Windows 11 draws its caption buttons 46 wide over a 32 tall title bar.
const captionButtonWidth = 46.0;

/// The pin is not a caption button: it keeps the round Material button in a
/// square slot the height of the bar, with a regular icon size.
const pinIconSize = 16.0;

Size getCaptionButtonSize(double headerHeight) =>
    Size(captionButtonWidth, headerHeight);

/// 窗口自绘标题条的高度。macOS 取 28，Windows 取 32。
double getWindowHeaderHeight({required bool isMacOS}) => isMacOS ? 28 : 32;

/// 是否展示顶栏：
/// - Windows 始终展示 32px 顶栏，提供拖拽与窗口控制按钮。
/// - macOS 宽于 compact 断点时，页面内容直接顶到窗口上沿，不画标题条；窄屏画 28px 标题条。
bool showsWindowHeader({
  required bool isMacOS,
  bool isWindows = false,
  required bool isMobileView,
}) {
  if (isWindows) {
    return true;
  }
  return isMacOS && isMobileView;
}

/// 窗口按钮区域与页面内容的重叠。窄屏由标题条承担，全屏没有红绿灯。
Size windowControlsOverPage({
  required bool isMacOS,
  required bool isMobileView,
  required bool isFullScreen,
}) {
  if (!isMacOS || isMobileView || isFullScreen) {
    return Size.zero;
  }
  return macOSTrafficLightsArea;
}
