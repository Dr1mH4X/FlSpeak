# 第三方代码

本仓库包含 FlClash 的代码。每个复制文件的开头标注了来源、来源提交与原始许可证。

| 来源 | 原始许可证 | 引入形式与内容 |
| --- | --- | --- |
| [FlClash](https://github.com/chen08209/FlClash) | GPL-3.0 | macOS 标题条布局、窗口尺寸与红绿灯让位，Windows 标题栏控制按钮与 Segoe Fluent 矢量图标，Windows Inno Setup 安装脚本与简体中文语言包，窄屏底部导航与标签页淡入淡出，业务图标矢量定义（`AppGlyphs`），系统字体枚举、调色板、外观设置与交互预览卡片，设置行与设置文本卡片适配，页面 `Scaffold` / `ScaffoldBar` / `BaseScaffold`、系统栏与异常顶部边距保护及 Android `values-v27` 挖孔屏配置 |
| [prism_ui](https://pub.dev/packages/prism_ui) | GPL-3.0 | Pub 依赖 `prism_ui`，直接提供按钮、弹性按压、`PressSurface`、表面层级、超椭圆形状、开关、滑块、`SegmentedControl`、`Glyph`/`Glyphs`（含 `Glyphs.sidebar`）/`GlyphIcon`/`AnimatedGlyph`、弹出菜单、`ListRow`、`DecorationListItem`、`NavigationDock`/`NavigationBar`、`PrismScaffold`/`ScaffoldBar`/`FloatingHeader`/`BuildContextExtension`、`AnimatedVisibility`、`OpenContainer`、`AlertDialog`/`showFloatingDialog`、`showSheet`、`SearchField`、`NullStatus`、seeded 取色与纯黑映射、Liquid Glass、Goo 与主题过渡原语 |
| [FlClash 的 `plugins/window`](https://github.com/chen08209/FlClash/tree/main/plugins/window) | MIT | 隐藏标题栏、窗口拖拽、双击缩放、最小化/最大化/关闭、置顶、Windows Mica/Acrylic 样式支持、单实例检测与全屏状态 |
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | MIT | Markdown 正文段落单物理行检查门禁脚本 |

## FlClash

来源提交：`7fd417fb9a9a277c6a9339a8ac87f907df7c25f7`（v0.9.2）与 `be84736`（v0.9.3）。

原始许可证为 GNU General Public License v3.0，见 FlClash 仓库根 `LICENSE`，原文见 https://www.gnu.org/licenses/gpl-3.0.txt 。复制片段的版权归 FlClash 作者所有。

复制内容来自 `lib/common/layout.dart` 的窗口尺寸与红绿灯区域、`lib/manager/window_manager.dart` 的 `WindowHeaderContainer`、`WindowHeaderLayout`、`WindowHeaderBar`、`WindowHeader`、`lib/manager/theme_manager.dart` 的 `_AppMediaQuery` 与 `AnnotatedRegion<SystemUiOverlayStyle>`、`lib/manager/app_manager.dart` 的侧栏安全区去重、`lib/ui/scaffold/`（`scaffold.dart`、`scaffold_actions.dart`、`scaffold_search.dart`）、`lib/ui/scaffold/scaffold_search.dart` 的搜索展开弹簧动效、`lib/ui/sidebar.dart`、`lib/ui/icons/app_glyphs.dart`、`lib/ui/icons/caption_icon.dart`、`lib/ui/list_item.dart`、`lib/ui/setting_text_card.dart`、`lib/common/dialog.dart` 与 `lib/providers/actions/common.dart` 的新版本提示弹窗布局与更新日志富文本样式、`lib/common/system_fonts.dart`、`lib/pages/home.dart` 的 `PageView` 过渡与 `_FadeTabPage`、`lib/widgets/palette.dart`、`lib/views/font_family.dart`、`lib/features/form/selection_sheet.dart`、`lib/views/theme_preview.dart`、`lib/views/theme.dart`、`android/app/src/main/res/values-v27/styles.xml`、`android/app/src/main/res/values-night-v27/styles.xml` 与 `windows/packaging/exe/` 的 `inno_setup.iss`、`ChineseSimplified.isl`。

| 本仓库文件 | 原始文件 |
| --- | --- |
| `lib/app.dart` | `lib/manager/theme_manager.dart` |
| `lib/core/window_metrics.dart` | `lib/common/layout.dart` |
| `lib/core/system_fonts.dart` | `lib/common/system_fonts.dart` |
| `lib/core/window_chrome.dart` | `plugins/window/lib/src/desktop_window.dart`、`lib/common/window.dart` |
| `lib/widgets/window_header.dart` | `lib/manager/window_manager.dart`、`lib/ui/scaffold.dart` |
| `lib/widgets/scaffold/scaffold.dart`、`scaffold_actions.dart`、`scaffold_search.dart` | `lib/ui/scaffold/scaffold.dart`、`scaffold_actions.dart`、`scaffold_search.dart` |
| `lib/features/connect/connect_page.dart`（搜索展开动效） | `lib/ui/scaffold/scaffold_search.dart` |
| `lib/widgets/compact_navigation_shell.dart` | `lib/pages/home.dart` |
| `lib/widgets/app_navigation_sidebar.dart` | `lib/ui/sidebar.dart`、`lib/manager/app_manager.dart` |
| `lib/widgets/app_glyphs.dart` | `lib/ui/icons/app_glyphs.dart` |
| `lib/widgets/update_dialog.dart` | `lib/common/dialog.dart`、`lib/providers/actions/common.dart` |
| `lib/widgets/caption_icon.dart` | `lib/ui/icons/caption_icon.dart` |
| `lib/features/settings/widgets/list_item.dart` | `lib/ui/list_item.dart` |
| `lib/features/settings/widgets/setting_text_card.dart` | `lib/ui/setting_text_card.dart` |
| `lib/features/settings/widgets/palette.dart` | `lib/widgets/palette.dart` |
| `lib/features/settings/widgets/font_family_view.dart` | `lib/views/font_family.dart`、`lib/features/form/selection_sheet.dart` |
| `lib/features/settings/widgets/theme_preview.dart` | `lib/views/theme_preview.dart` |
| `lib/features/settings/widgets/theme_settings_view.dart` | `lib/views/theme.dart` |
| `android/app/src/main/res/values-v27/styles.xml`、`values-night-v27/styles.xml` | `android/app/src/main/res/values-v27/styles.xml`、`values-night-v27/styles.xml` |
| `windows/packaging/exe/inno_setup.iss`、`ChineseSimplified.isl` | `windows/packaging/exe/inno_setup.iss`、`ChineseSimplified.isl` |

## prism_ui

包地址：[pub.dev/packages/prism_ui](https://pub.dev/packages/prism_ui)（上游仓库：`https://github.com/chen08209/prism_ui`）。

原始许可证为 GNU General Public License v3.0，见上游仓库 `LICENSE`，原文见 https://www.gnu.org/licenses/gpl-3.0.txt 。该包代码版权归 `prism_ui` 作者所有。

FlSpeak 通过 `pubspec.yaml` Pub 依赖与 [lib/widgets/prism.dart](../lib/widgets/prism.dart) 桥接直接引用 `package:prism_ui/prism_ui.dart` 的原生组件；设置详情通过 `showExtend(forceFull: true)` 复用上游的 `FadePageRoute` 与 `CardPageRoute`。

| 本仓库接入位置 | 对应模块内容 |
| --- | --- |
| `pubspec.yaml` | 完整引入 `prism_ui`（按钮、按压表面、弹性缩放、表面层级、形状、开关、弹出菜单、分组列表、Liquid Glass 着色器、Goo 与主题过渡） |
| `lib/widgets/prism.dart` | `PrismRootScope`、`PrismUiLocalizationsDelegate`、`SurfaceCard`、`ElevatedSurfaceTheme`、`AnimatedInkWell`、`OptionsValueButton`、`Slider`、`SegmentedControl`、`Glyphs`/`GlyphIcon`/`AnimatedGlyph`、`NavigationDock`/`NavigationBar`、`PrismScaffold`/`ScaffoldBar`/`FloatingHeader`/`BuildContextExtension`、`OpenContainer`、`AlertDialog`/`showFloatingDialog`、`showSheet`/`showExtend`、`SearchField`、`NullStatus`、seeded 取色/纯黑接口桥接与统一导出 |
| `lib/widgets/app_navigation_sidebar.dart` | 使用 `prism_ui` 的 `GlyphIcon(Glyphs.sidebar(progress))` 绘制与 FlClash `NavigationSidebar` 一致的侧栏展开/收起图标及 `progress` 过渡动效 |
| `lib/features/settings/settings_page.dart` | 沿用 FlClash 的设置多级导航与 `showExtend(forceFull: true)` 整页推入 |

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
