# AGENTS.md — 设置与配置

本规则补充根目录 [AGENTS.md](../../../AGENTS.md) 与 [lib/AGENTS.md](../../AGENTS.md)，覆盖设置模块的页面导航与排版。

## 三级导航

设置页沿用全应用的空间骨架：全局导航侧栏（折叠 56 / 展开 180）加右侧设置区。一级是无标题卡片概览页，二级页占满右侧区域且只承载跳转入口，三级是终末设置页。

1. **多级菜单不是抽屉**：点分类卡片或子项入口后整页推入并占满主内容区，不使用从右侧滑出一半的导航抽屉；每级详情经 `prism_ui` `showExtend(forceFull: true)` 推入，页面自身用 `lib/widgets/scaffold/scaffold.dart` 的 `Scaffold` 承担悬浮顶栏与状态栏退避。窄屏得到 `CardPageRoute`，宽屏得到 `FadePageRoute` 并覆盖设置侧栏；详情页不绘制设置侧栏，窗口跨断点时留在根导航器上。字体选择与自定义调色板分别经 `OpenContainer`（窄屏）或 `showSheet`（桌面）打开独立选择器。
2. **逐级返回**：二三级详情页的顶栏返回按钮走 `Scaffold` 的 `backAction`（带 `Semantics` 标签），同时绑定 `LogicalKeyboardKey.escape`；一级概览页是导航目的地，不显示返回按钮，由宽屏侧栏或窄屏底栏离开，`ESC` 与系统返回按退栈规则退回来路，无历史路由时已连接退回工作区、未连接退回首页。
3. **悬浮顶栏与安全区**：设置主区域经 `SidebarContentInset` 剥离侧栏一侧的水平安全边距，内部滚动列表按 `context.appBarInset` 与 `MediaQuery.paddingOf(context)` 避让悬浮顶栏与系统安全区；桌面窗口拖拽由 `WindowHeader` 与侧栏顶部避让区承担。

## 小标题与排版

1. **只有终末级页面允许小标题**：一级概览页与非终末的二级页（「通用」）都用无标题卡片，跳转入口直接放进 `generateSection(items: ...)`；终末页（「外观」、「通用」下的「语音」与「屏幕共享」）保留 `ListHeader` 分组小标题，且只有「外观」页最上方放置单个 `ThemeLivePreview` 实时预览卡片。
2. **标题加当前值**：一级与二级卡片只展示分类名称与图标；枚举类设置经 `SettingsOptionsTile` 把当前值放在 `trailing`（含 `PopupValueText` 切换动效）并弹出依附控件的 `PopupMenu`，开关类设置统一用 `prism_ui` 的 `Switch`。
3. **文案与无障碍**：遵守 [Flutter 界面文案与操作按钮约束](../../../docs/defensive-patterns/ui.md)。
4. **合规与命名**：未直接依赖源码的文件中，不出现模仿或对齐外部项目的名称字样。

