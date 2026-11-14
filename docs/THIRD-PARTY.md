# 第三方代码

本仓库包含 FlClash 的代码。每个复制文件的开头标注了来源、来源提交与原始许可证。

| 来源 | 原始许可证 | 引入形式与内容 |
| --- | --- | --- |
| [FlClash](https://github.com/chen08209/FlClash) | GPL-3.0 | macOS 标题条布局、窗口尺寸与红绿灯让位，Windows 标题栏控制按钮与 Segoe Fluent 矢量图标，以及设置行与设置文本卡片适配 |
| [prism_ui](https://pub.dev/packages/prism_ui) | GPL-3.0 | Pub 依赖 `prism_ui`，直接提供按钮、弹性按压、`PressSurface`、表面层级、超椭圆形状、滑块开关、弹出菜单、`ListRow`、`DecorationListItem`、Liquid Glass、Goo 与主题过渡原语 |
| [FlClash 的 `plugins/window`](https://github.com/chen08209/FlClash/tree/main/plugins/window) | MIT | 隐藏标题栏、窗口拖拽、双击缩放、最小化/最大化/关闭、置顶、系统材质特效（Mica/Acrylic）、单实例检测与全屏状态 |
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | MIT | Markdown 正文段落单物理行检查门禁脚本 |

## FlClash

来源提交：`7fd417fb9a9a277c6a9339a8ac87f907df7c25f7`（v0.9.2）与 `be84736`（v0.9.3）。

原始许可证为 GNU General Public License v3.0，见 FlClash 仓库根 `LICENSE`，原文见 https://www.gnu.org/licenses/gpl-3.0.txt 。复制片段的版权归 FlClash 作者所有。

复制内容来自 `lib/common/layout.dart` 的窗口尺寸与红绿灯区域、`lib/manager/window_manager.dart` 的 `WindowHeaderContainer`、`WindowHeaderLayout`、`WindowHeaderBar`、`WindowHeader`、`lib/ui/sidebar.dart`、`lib/ui/icons/app_glyphs.dart`、`lib/ui/icons/caption_icon.dart`、`lib/ui/list_item.dart` 与 `lib/ui/setting_text_card.dart`。

| 本仓库文件 | 原始文件 |
| --- | --- |
| `lib/core/window_metrics.dart` | `lib/common/layout.dart` |
| `lib/widgets/window_header.dart` | `lib/manager/window_manager.dart`、`lib/ui/scaffold.dart` |
| `lib/widgets/app_navigation_sidebar.dart` | `lib/ui/sidebar.dart` |
| `lib/widgets/app_glyphs.dart` | `lib/ui/icons/app_glyphs.dart` |
| `lib/widgets/caption_icon.dart` | `lib/ui/icons/caption_icon.dart` |
| `lib/features/settings/widgets/list_item.dart` | `lib/ui/list_item.dart` |
| `lib/features/settings/widgets/setting_text_card.dart` | `lib/ui/setting_text_card.dart` |

## prism_ui

包地址：[pub.dev/packages/prism_ui](https://pub.dev/packages/prism_ui)（上游仓库：`https://github.com/chen08209/prism_ui`）。

原始许可证为 GNU General Public License v3.0，见上游仓库 `LICENSE`，原文见 https://www.gnu.org/licenses/gpl-3.0.txt 。该包代码版权归 `prism_ui` 作者所有。

FlSpeak 通过 `pubspec.yaml` Pub 依赖与 [lib/widgets/prism.dart](../lib/widgets/prism.dart) 桥接直接引用 `package:prism_ui/prism_ui.dart` 的原生组件，同时保留与 Flutter 设置转场（`page_transition.dart` 的 `300 ms` 临界阻尼推入弹簧参数）的一致性。

| 本仓库接入位置 | 对应模块内容 |
| --- | --- |
| `pubspec.yaml` | 完整引入 `prism_ui`（按钮、按压表面、弹性缩放、表面层级、形状、开关、弹出菜单、分组列表、Liquid Glass 着色器、Goo 与主题过渡） |
| `lib/widgets/prism.dart` | `PrismRootScope`、`PrismUiLocalizationsDelegate`、`SurfaceCard`、`ElevatedSurfaceTheme`、`AnimatedInkWell`、`OptionsValueButton` 桥接与统一导出 |
| `lib/features/settings/settings_page.dart` | 沿用 `page_transition.dart` 的 `300 ms` 临界阻尼推入弹簧参数与导航架构 |

## FlClash 的 window 插件

位置为 FlClash 仓库的 `plugins/window`，原始许可证为 MIT，见该目录的 `LICENSE`。

复制内容来自：
- `macos/window/Sources/window/WindowStyle.swift` 的 `.hidden` 标题栏分支，以及 `WindowController.swift` 的 `startDragging`、`maximize`、`setFullScreen` 行为。
- `windows/window_style.h` 与 `windows/window_style.cpp` 的隐藏标题栏、DWM 边框延伸、暗色模式与 Mica/Acrylic 材质。
- `windows/window_controller.h` 与 `windows/window_controller.cpp` 的非客户区消息处理、顶部 1px 细边框 hit-test 与缩放、窗口拖拽、最小化、最大化与全屏。
- `windows/running_instance.h` 与 `windows/running_instance.cpp` 的单实例进程匹配与激活。

| 本仓库文件 | 原始文件 |
| --- | --- |
| `macos/Runner/MainFlutterWindow.swift` | `plugins/window/macos/window/Sources/window/WindowStyle.swift`、`WindowController.swift` |
| `windows/runner/running_instance.h`、`windows/runner/running_instance.cpp` | `plugins/window/windows/running_instance.h`、`running_instance.cpp` |
| `windows/runner/window_style.h`、`windows/runner/window_style.cpp` | `plugins/window/windows/window_style.h`、`window_style.cpp` |
| `windows/runner/window_controller.h`、`windows/runner/window_controller.cpp` | `plugins/window/windows/window_controller.h`、`window_controller.cpp` |
| `windows/runner/flutter_window.h`、`windows/runner/flutter_window.cpp` | `plugins/window/windows/window_plugin.cpp`、`window_controller.cpp` |
| `windows/runner/main.cpp` | `windows/runner/main.cpp` |
| `lib/core/window_chrome.dart` | `plugins/window/lib/src/desktop_window.dart` |

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

## DeepSeek Harness

来源仓库：[deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)。原始许可证为 MIT License，版权归 DeepSeek 所有。

复制与移植内容来自 `scripts/verify-md-wrap.ts` 的 AST/状态机段落单物理行检查门禁。

| 本仓库文件 | 原始文件 |
| --- | --- |
| `website/scripts/verify-md-wrap.mjs` | `scripts/verify-md-wrap.ts` |

## 许可证关系

本仓库以 AGPL-3.0 发布，见根 `LICENSE`。GPL-3.0 作品与 AGPL-3.0 作品的组合依据 AGPL-3.0 第 13 条；MIT 片段保留原始版权与许可声明，并随本仓库按 AGPL-3.0 分发。
