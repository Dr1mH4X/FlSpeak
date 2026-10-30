# 第三方代码

本仓库包含 FlClash 的代码。每个复制文件的开头标注了来源、来源提交与原始许可证。

| 来源 | 原始许可证 | 复制内容 |
| --- | --- | --- |
| [FlClash](https://github.com/chen08209/FlClash) | GPL-3.0 | macOS 标题条布局、窗口尺寸与红绿灯让位，选项弹层、文字模糊切换动效、整屏主题与语言平滑过渡、Liquid Glass 与 Goo 渲染底座 |
| [FlClash 的 `plugins/window`](https://github.com/chen08209/FlClash/tree/main/plugins/window) | MIT | 隐藏标题栏、窗口拖拽、双击缩放与全屏状态 |

## FlClash

来源提交：`7fd417fb9a9a277c6a9339a8ac87f907df7c25f7`（v0.9.2）。

原始许可证为 GNU General Public License v3.0，见 FlClash 仓库根 `LICENSE`，原文见 https://www.gnu.org/licenses/gpl-3.0.txt 。复制片段的版权归 FlClash 作者所有。

复制内容来自 `lib/common/layout.dart` 的窗口尺寸与红绿灯区域、`lib/ui/view_scope.dart`、`lib/manager/window_manager.dart` 的 `WindowHeaderContainer`、`WindowHeaderLayout`、`WindowHeaderBar`、`WindowHeader`，以及 `lib/ui/scaffold.dart` 的 `_WindowControlsClearance`；设置与弹出层体系来自 `shaders/liquid_glass.frag`、`lib/ui/shape.dart`、`lib/ui/motion.dart`、`lib/ui/navigation_dock.dart`（弹性按压）、`lib/ui/liquid_glass.dart`、`lib/ui/liquid_glass_capture.dart`、`lib/ui/goo.dart`、`lib/ui/theme_cross_fade.dart`、`lib/ui/popup.dart` 与 `lib/ui/list.dart`（选项值按钮）。

| 本仓库文件 | 原始文件 |
| --- | --- |
| `lib/core/window_metrics.dart` | `lib/common/layout.dart` |
| `lib/widgets/view_scope.dart` | `lib/ui/view_scope.dart` |
| `lib/widgets/window_header.dart` | `lib/manager/window_manager.dart`、`lib/ui/scaffold.dart` |
| `shaders/liquid_glass.frag` | `shaders/liquid_glass.frag` |
| `lib/widgets/shape.dart` | `lib/ui/shape.dart` |
| `lib/widgets/motion.dart` | `lib/ui/motion.dart` |
| `lib/widgets/elastic_press.dart` | `lib/ui/navigation_dock.dart` |
| `lib/widgets/liquid_glass.dart` | `lib/ui/liquid_glass.dart` |
| `lib/widgets/liquid_glass_capture.dart` | `lib/ui/liquid_glass_capture.dart` |
| `lib/widgets/goo.dart` | `lib/ui/goo.dart` |
| `lib/widgets/theme_cross_fade.dart` | `lib/ui/theme_cross_fade.dart` |
| `lib/widgets/popup.dart` | `lib/ui/popup.dart`、`lib/ui/list.dart` |
| `lib/widgets/app_navigation_sidebar.dart` | `lib/ui/sidebar.dart` |

## FlClash 的 window 插件

位置为 FlClash 仓库的 `plugins/window`，原始许可证为 MIT，见该目录的 `LICENSE`。

复制内容来自 `macos/window/Sources/window/WindowStyle.swift` 的 `.hidden` 标题栏分支，以及 `WindowController.swift` 的 `startDragging`、`maximize`、`setFullScreen` 行为。

| 本仓库文件 | 原始文件 |
| --- | --- |
| `macos/Runner/MainFlutterWindow.swift` | `plugins/window/macos/window/Sources/window/WindowStyle.swift`、`WindowController.swift` |
| `lib/core/window_chrome.dart` | `plugins/window/lib/src/desktop_window.dart` 的 `startDragging` 调用 |

MIT 许可原文：

```text
MIT License

Copyright (c) 2025 FlClash
Copyright (c) 2022-present LiJianying <lijy91@foxmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 许可证关系

本仓库以 AGPL-3.0 发布，见根 `LICENSE`。GPL-3.0 作品与 AGPL-3.0 作品的组合依据 AGPL-3.0 第 13 条；MIT 片段保留原始版权与许可声明，并随本仓库按 AGPL-3.0 分发。