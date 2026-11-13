# Flutter 界面设计规范

本文定义 FlSpeak Flutter 客户端的组件选型边界、视觉表面层级、超椭圆圆角、排版字阶、按压反馈与设置列表规格。

## 组件选型与 Prism 优先

所有 Flutter 界面均通过 [lib/widgets/prism.dart](../../lib/widgets/prism.dart) 优先使用子模块 `plugins/prism_ui` 提供的原生原语（包括 `FilledButton`、`OutlinedButton`、`TextButton`、`IconButton`、`TonalButton`、`TonalButtonGroup`、`Switch`、`Checkbox`、`Chip`、`SegmentedControl`、`PopupMenu`、`ListRow`、`ListHeader`、`ListFooter`、`LinearProgressIndicator`、`SurfaceScope`、`CardSurface`、`PressSurface`、`ElasticButton`、`LiquidGlass` 等）。

- **优先桥接复用**：`plugins/prism_ui` 已具备的控件、表面容器或视觉效果（含子模块已导出但尚未经过 `lib/widgets/prism.dart` 转出的模块），在 [lib/widgets/prism.dart](../../lib/widgets/prism.dart) 补充导出与主题适配后直接复用，不在 `lib/` 手写替代实现，也不回退到同名 `package:flutter/material.dart` 控件。
- **隐藏冲突控件**：UI 文件同时引入 `package:flutter/material.dart` 时，`hide` 与 `lib/widgets/prism.dart` 同名冲突的 Material 控件与样式类型，确保按钮、开关、进度条、菜单与表单控件统一走 `prism_ui`。
- **自定义组件边界**：`lib/widgets/` 与 `lib/features/` 仅承接业务插槽装配、桌面窗口宿主交互或 `prism_ui` 未覆盖的专项视觉组件（如自定义标识徽章与连接动效框架）。

## Surface 层级与边界

界面依靠明度台阶区隔层级，不在普通卡片或设置行外围绘制描边，色彩仅用于标识选中、激活、错误与核心操作状态。`SurfaceScope` 与 `SurfaceLevel`（由子模块 `plugins/prism_ui` 经 `lib/widgets/prism.dart` 导出）定义四个表面深度：

| 层级 | 浅色角色 | 深色角色 | 典型容器 |
| --- | --- | --- | --- |
| `page` | `surfaceContainer` | `surface` | 页面底板与弹窗/面板页基准 |
| `card` | `surfaceBright` | `surfaceContainer` | 卡片、分组列表容器、浅色浮层 |
| `block` | `surfaceContainer` | `surfaceContainerHigh` | 卡片内的子区块、未选中分段、深色浮层 |
| `inset` | `surfaceContainerHighest` | `surfaceContainerHighest` | 子区块内的徽标底托、空轨道与微小凹槽 |

- **嵌套步进**：共享表面容器从上下文读取 `context.raisedSurfaceLevel`（由 `page` 依次步进到 `card`、`block`、`inset`），并用新的 `SurfaceScope` 包裹子树，组件不在调用点硬编码页面或抽屉分支颜色。
- **提升表面**：深色模式下的覆盖层通过 `ElevatedSurfaceTheme` 将各层表面色向上提升一级，使其与下层页面区分。
- **浮层**：弹窗、菜单、气泡提示框与悬浮工具条使用 `SurfaceLevel.floatingOf(colorScheme)`（浅色取 `card`，深色取 `block`）。
- **无色调填充容器**：`primaryContainer`、`secondaryContainer`、`tertiaryContainer` 不用于普通卡片、列表行、图标底框或导航背景；错误行/卡使用 `errorContainer` 与 `onErrorContainer` 且不加描边。
- **保留描边与分隔线**：仅桌面端侧栏/标题栏与内容交界、输入框轮廓以及键盘聚焦环（2 dp `primary`）保留线条。分隔线颜色统一取 `dividerColorOf(context)`（`onSurface` 14% 不透明度），禁用 `outlineVariant`，列表行分隔线按物理像素对齐并省略末尾行及无效行两侧。

## 圆角与容器形态

所有圆角均采用连续超椭圆（`RoundedSuperellipseBorder`、`ClipRSuperellipse`、`ShapeDecoration`），禁止使用圆弧角 API（`RoundedRectangleBorder`、`ClipRRect`、`BoxDecoration(borderRadius: ...)`）。

- **尺寸阶梯**：`AppCorner` 与 `AppShape`（由 `lib/widgets/prism.dart` 导出）定义标准圆角：`none` (0)、`xs` (4)、`sm` (8)、`md` (16)、`lg` (20)、`xl` (24)、`xxl` (28)、`alert` (34)、`full` (1000)。
- **卡片与同心圆角**：标准内容卡片使用 `AppShape.md`（或外层容器与内边距满足同心关系 `r_inner = r_outer - padding`），独立选项卡片 `SettingTextCard` 与 `AppearancePicker` 使用超椭圆裁剪与圆角边框。
- **按钮形态**：所有交互按钮直接使用 `prism_ui` 的 `FilledButton`、`OutlinedButton`、`TextButton`、`IconButton`（`ButtonStyle.from(...)`）呈现 `AppShape.full` 超椭圆胶囊；顶部工具栏、节头（`ListHeader`）与行内快捷操作使用 `TonalButton` 与 `TonalButtonGroup`（`bar`、`section`、`compact` 三个尺寸档位）；桌面端原生窗口控制按钮保留系统方形几何与悬停着色。

## 排版与字阶

字号与行高依据 `AppTextStyle`（由 `lib/widgets/prism.dart` 导出）采用 iOS Dynamic Type 默认比例，提供 `largeTitle`、`title1`、`title2`、`title3`、`headline`、`body`、`callout`、`subheadline`、`footnote`、`caption1`、`caption2` 及 `pageTitle`、`display` 档位，支持 `of(context, emphasized: ...)` 切换常规或强调字重。主要文本取 `onSurface`，次要与说明文本取 `onSurfaceVariant`，不以 `outline` 作为正文颜色。

## 按压、悬停与减少动效

所有按压与悬停反馈均由 `plugins/prism_ui` 原生原语驱动：

| 控件类别 | 反馈机制 | 细则 |
| --- | --- | --- |
| 常规按钮（`FilledButton`/`OutlinedButton`/`TextButton`/`IconButton`） | `PressSurface`（`PressLook.tint`） | 通过 `CardSurface` 绘制无水波纹按压着色与焦点外环；位于可滚动容器内时支持短延迟点亮并在滚动开始时取消；置于 `ElasticButton` 内时自动切至 `PressLook.none`。 |
| 顶栏工具按钮、弹窗/模态框主 CTA 按钮 | `ElasticButton`（`ElasticPress`） | 将按钮主题切为 `PressLook.none` 并交由 `ElasticPress` 承担弹性形变与拖拽跟随反馈。 |
| 交互卡片、列表行、侧栏导航按钮与 `AppearancePicker` | `PressSurface` / `AnimatedInkWell` | 基于 `PressLook.tint` 提供统一悬停（4% `onSurface`）与按压反馈，无水波纹扩散。 |
| 开关控件（设置列表与权限开关） | `Switch`（`plugins/prism_ui`） | 采用 `52×32 dp` 轨道与胶囊滑块，支持点击与水平拖拽切换；开启 `LiquidGlassScope` 时按压与跨中点切换会抬升滑块并切换为 `LiquidGlassStyle.lens` 透镜态，`200 ms` 后回落；键盘聚焦显示外扩 2 dp 焦点环（`focusRingSide`）。 |
| 桌面端系统窗口控制按钮 | 系统原生高亮 | 保留固定方形交互区与纯悬停/按下明暗着色，不参与弹性形变。 |

## 设置节与列表行规范

设置模块统一通过 `generateSection`、`generateGroup`、`ListHeader`、`ListFooter`、`ListItem`（`lib/features/settings/widgets/settings_section.dart` 与 `lib/features/settings/widgets/list_item.dart`）与 `ListRow` 组织：

- **节结构与间距**：`ListHeader` 使用 `headline` 字阶并可右侧挂载 36 dp 高度的 `TonalButtonSize.section` 操作组；`ListFooter` 使用 `footnote` 字阶（`onSurfaceVariant`）置于卡片下方。
- **行几何**：`ListRow` 在行高内对 `leading`、标题/副标题列与 `trailing`（如 `Switch` 与收紧 `minimumSize: Size.zero` 的 `OptionsValueButton`）执行纵轴居中对齐，`PopupMenu` 展开后的内部选项行与设置项共享 `plugins/prism_ui` 列表规范。
- **子页面过渡与材质隔离**：设置多级钻取（概览页与二/三级子页切换）为每个页面槽位绑定独立 `ValueKey` 与本地 `Material(type: MaterialType.transparency)` 边界（顶栏 `_SettingsTopBar` 独立承载于其上），采用双向水平推入/拉回转场（进入新页自右侧推入，返回自左侧退回并揭开上一级，采用 `300 ms` 临界阻尼弹簧）。
- **行内容与分组位置**：前置图标统一为 `24 dp` 裸图标（无额外背景框）；分组内每行经 `ItemPositionScope` 感知首/中/尾/单项位置，中间插入 1 物理像素高的 `14% onSurface` 分隔线。
