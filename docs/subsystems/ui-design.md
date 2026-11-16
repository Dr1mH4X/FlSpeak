# Flutter 界面设计规范

本文定义 FlSpeak Flutter 客户端的组件选型边界、视觉表面层级、超椭圆圆角、排版字阶、按压反馈与设置列表规格。

## 组件选型与 Prism 优先

所有 Flutter 界面均通过 [lib/widgets/prism.dart](../../lib/widgets/prism.dart) 优先使用 `prism_ui` 提供的原生原语（包括 `FilledButton`、`OutlinedButton`、`TextButton`、`IconButton`、`TonalButton`、`TonalButtonGroup`、`TonalButtonTheme`、`Switch`、`Checkbox`、`Chip`、`SegmentedControl`、`PopupMenu`、`ListRow`、`ListHeader`、`ListFooter`、`LinearProgressIndicator`、`SurfaceScope`、`CardSurface`、`PressSurface`、`ElasticButton`、`ElasticPress`、`FocusRing`、`GooSurface`、`GooPane`、`TextField`、`TextFormField`、`InputDecoration`、`InputDecorationTheme`、`NoInputBorder`、`TextSelectionMenu`、`LiquidGlass` 等）。

- **优先桥接复用**：`prism_ui` 已具备的控件、表面容器或视觉效果（含上游包已导出但尚未经过 `lib/widgets/prism.dart` 转出的模块），在 [lib/widgets/prism.dart](../../lib/widgets/prism.dart) 补充导出与主题适配后直接复用，不在 `lib/` 手写替代实现，也不回退到同名 `package:flutter/material.dart` 控件。
- **隐藏冲突控件**：UI 文件同时引入 `package:flutter/material.dart` 时，`hide` 与 `lib/widgets/prism.dart` 同名冲突的 Material 控件与样式类型，确保按钮、开关、进度条、菜单与表单控件统一走 `prism_ui`。
- **文本输入体系**：表单与单行/多行输入统一采用 `prism_ui` 的 `TextField` / `TextFormField`，由 `PrismRootScope` 注入 `InputDecorationTheme`（填充底色、超椭圆 `AppShape.input` 轮廓与原生编辑菜单 `TextSelectionMenu`）；表单字段标题以独立标签置于输入框上方，横排紧凑槽位直接使用 `hintText`。
- **自定义组件边界**：`lib/widgets/` 与 `lib/features/` 仅承接业务插槽装配、桌面窗口宿主交互或 `prism_ui` 未覆盖的专项视觉组件（如自定义标识徽章与连接动效框架）。

## Surface 层级与边界

界面依靠明度台阶区隔层级，不在普通卡片或设置行外围绘制描边，色彩仅用于标识选中、激活、错误与核心操作状态。`SurfaceScope` 与 `SurfaceLevel`（由 `prism_ui` 经 `lib/widgets/prism.dart` 导出）定义四个表面深度：

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

所有按压与悬停反馈均由 `prism_ui` 原生原语驱动：

| 控件类别 | 反馈机制 | 细则 |
| --- | --- | --- |
| 常规按钮（`FilledButton`/`OutlinedButton`/`TextButton`/`IconButton`） | `PressSurface`（`PressLook.tint`） | 通过 `CardSurface` 绘制无水波纹按压着色与焦点外环；位于可滚动容器内时支持短延迟点亮并在滚动开始时取消；置于 `ElasticButton` 内时自动切至 `PressLook.none`。 |
| 顶栏工具按钮、弹窗/模态框主 CTA 按钮 | `ElasticButton`（`ElasticPress`） | 将按钮主题切为 `PressLook.none` 并交由 `ElasticPress` 承担弹性形变与拖拽跟随反馈。 |
| 交互卡片、列表行、侧栏导航按钮与颜色色板 | `PressSurface` / `AnimatedInkWell` | 基于 `PressLook.tint` 提供统一悬停（4% `onSurface`）与按压反馈，无水波纹扩散。 |
| 开关控件（设置列表与权限开关） | `Switch`（`prism_ui`） | 采用 `52×32 dp` 轨道与胶囊滑块，支持点击与水平拖拽切换；开启 `LiquidGlassScope` 时按压与跨中点切换会抬升滑块并切换为 `LiquidGlassStyle.lens` 透镜态，`200 ms` 后回落；键盘聚焦显示外扩 2 dp 焦点环（`focusRingSide`）。 |
| 桌面端系统窗口控制按钮 | 系统原生高亮 | 保留固定方形交互区与纯悬停/按下明暗着色，不参与弹性形变。 |

## 设置节与列表行规范

设置模块统一通过 `generateSection`、`generateGroup`、`ListHeader`、`ListFooter`、`ListItem`（`lib/features/settings/widgets/settings_section.dart` 与 `lib/features/settings/widgets/list_item.dart`）与 `ListRow` 组织：

- **节结构与间距**：`ListHeader` 使用 `headline` 字阶并可右侧挂载 36 dp 高度的 `TonalButtonSize.section` 操作组；`ListFooter` 使用 `footnote` 字阶（`onSurfaceVariant`）置于卡片下方。
- **行几何**：`ListRow` 在行高内对 `leading`、标题/副标题列与 `trailing`（如 `Switch` 与收紧 `minimumSize: Size.zero` 的 `OptionsValueButton`）执行纵轴居中对齐，`PopupMenu` 展开后的内部选项行与设置项共享 `prism_ui` 列表规范。
- **子页面过渡与材质隔离**：设置多级钻取（概览页与二/三级子页切换）外层采用 [lib/widgets/scaffold/scaffold.dart](../../lib/widgets/scaffold/scaffold.dart) 的悬浮 `Scaffold` 承担标题与返回按钮（带 `Semantics` 无障碍标签，内部动作按钮保留 FlClash 原样），主体内容区为每个页面槽位绑定独立 `ValueKey` 与本地 `Material` 边界，并在 `AnimatedSwitcher` 中执行双向水平推入/拉回转场（进入自右侧推入，返回自左侧退回并揭开上一级，采用 `300 ms` 临界阻尼弹簧）。
- **行内容与分组位置**：前置图标统一为 `24 dp` 裸图标（无额外背景框）；分组内每行经 `ItemPositionScope` 感知首/中/尾/单项位置，中间插入 1 物理像素高的 `14% onSurface` 分隔线。

## 状态栏与安全区退避

应用在 Android 上以 `SystemUiMode.edgeToEdge` 运行，根组件挂载 `_AppMediaQuery` 钳制异常顶部系统边距并通过 `AnnotatedRegion<SystemUiOverlayStyle>`（`sized: false`）维持透明状态栏与透明系统导航栏（三键导航开启 `systemNavigationBarContrastEnforced`）；`android/app/src/main/res/values-v27` 与 `values-night-v27` 声明 `windowLayoutInDisplayCutoutMode=shortEdges` 以适配刘海与挖孔屏幕。

- **悬浮顶栏页面**：连接页、设置页与窄屏工作区主区使用 `lib/widgets/scaffold/scaffold.dart` 的 `Scaffold`（基于 `prism_ui` `PrismScaffold`、`ScaffoldBar` 与 `FloatingHeader`），顶栏内部通过 `SafeArea(bottom: false)` 退避状态栏并将渐变背景延伸至状态栏下方，滚动内容按 `context.appBarInset` 预留顶栏高度。
- **三栏布局与侧栏退避**：宽屏（`>= Breakpoints.compact`）下 `AppNavigationSidebar` 在自身内部包裹 `SafeArea` 并结合 `SidebarContentInset` 剥离已由侧栏承担一侧的水平安全边距，防止右侧内容区重复退避；工作区宽屏三栏中的频道面板顶栏、底部状态卡与主区域 `_ChannelHeader` 各自内置 `SafeArea` 退避状态栏与系统导航栏。

## 外观主题与窄屏底部导航

外观偏好持久化在 Rust `UiSettings`（`core/session`）与 Dart `SessionPreferences`，默认主题种子色为 `#C44D78` 并由 `buildAppColorScheme` 与 `buildPrismTheme` 结合 `seededColorScheme`、`AppColorStyle`、`pureBlack` 及对比度守护统一出表色，支持经 `lib/core/system_fonts.dart` 异步加载并筛选系统字体以及经 `PrismRootScope`、`MediaQuery.textScaler` 与 `MeasureScope` 控制文字缩放比例（`0.8–1.4`）。

- **窄屏底部导航与转场**：窗口宽度低于 `Breakpoints.compact` 时，`GoRouter` 将「首页」与「设置」纳入 `CompactNavigationShell`，按 `floatingNavigationBar` 在悬浮胶囊 `NavigationDock`（开启 `LiquidGlassScope` 时附带真实透视玻璃与 `BarItemPresence` 过渡）与停靠 `NavigationBar` 间切换，并按 `tabAnimation` 在水平滑动或 `SnapshotWidget` 原位交叉淡入淡出（`_FadeTabPage`）间切换；钻入设置二三级子页、键盘弹出或切入工作区 `/workspace` 时自动收起底栏，窄屏工作区频道顶栏左侧固定保留退回首页/设置入口的返回按钮与抽屉按钮。

## 液态玻璃开关与渲染档位

外观偏好 `SessionPreferences.liquidGlass` 控制全局 `LiquidGlassMode`（`none` / `standard` / `ultra`，默认 `none`），经 `lib/app.dart` 传入 `PrismRootScope` 后分别映射为关闭（`null`）、`LiquidGlassQuality.standard` 与 `LiquidGlassQuality.ultra`。开启时 `PrismRootScope` 通过 `LiquidGlassScope` 与 `LiquidGlassHost` 向内置 `prism_ui` 组件注入离屏抓取和着色参数，同级叠放面板可纳入 `LiquidGlassGroup` 避免重复多层截取。

- **`none`（默认）**：关闭 `LiquidGlassScope`，不进行离屏画布捕捉与玻璃着色器绘制，弹出菜单、开关与横幅直接落盘常规纯色表面，消除低端机每帧额外的离屏纹理抓取与模糊耗时。
- **`standard`**：开启 `LiquidGlassScope` 并通过 `LiquidGlassStyle._standard` 省略色散与独立前雾分层，将双层模糊合并为单次降采样的统一 `blur`，`PopupMenu` 弹出形变采用 `coarse` 粗轮廓采样，兼顾透视观感与 GPU 负载。
- **`ultra`**：启用完整着色参数，保留色散效果、双层 `haze + blur` 混合及精细轮廓采样，适用于高负载渲染性能充裕的设备。
- **玻璃附着边界**：`LiquidGlass` 仅用于下层有内容滚动或页面正文透出的悬浮组件（聊天页悬浮于 `PrismListView` 之上的输入栏、附件预览条与斜杠命令面板，连接页顶栏通过 `GooSurface` 与 `GooPane` 承载的搜索按钮/胶囊，窄屏悬浮 `NavigationDock`，以及窄屏展开的侧栏浮层 `_SidebarOverlay`）；桌面端固定停靠的侧栏默认保持纯色 `Surface`，在 macOS 或 Windows 开启 `sidebarBlur` 时将根脚手架置透明、原生 window backdrop 同步开启系统材质（macOS `NSGlassEffectView` / `NSVisualEffectView` 或 Windows Acrylic/Mica）并将 `AppNavigationSidebar` 叠加为半透明着色表面，右侧内容面板始终保持不透明。

## 重建作用域、重绘隔离与后台休眠

界面层通过窄订阅、布局/重绘隔离与生命周期门控，将高频状态与后台空转负载隔离在局部叶节点内（强制编码禁忌与正反例见 [ui-performance.md](../defensive-patterns/ui-performance.md)，探针方法见 [fls-ui-performance](../../.agents/skills/fls-ui-performance/SKILL.md)）：

- **窄订阅与列表局部刷新**：根应用与工作区页面仅订阅所需的标量字段或值语义记录（如 `activeServerId`、`reconnecting`、`connected`、单个客户端的 `speaking` / 分享态 / 选中态）；频道树、成员栏、聊天列表、文件列表与侧栏均采用 `PrismListView` / `SliverPrismList` 与 `MemoBuilder` 进行按需渲染与行级剪枝。
- **重绘隔离边界**：`WorkspaceShell` 各分栏、`WorkspacePage` 主区与 `WidthBuilder`、`NetworkTelemetryPanel`、频道 `ServerRow` 及自绘动画组件（`SignalRibbon`、`ExpressiveFrame`、`MemberAvatar` 说话光环）各自持有独立 `RepaintBoundary`；持续动画与高频频谱直接通过 `CustomPaint(repaint: ...)` 驱动画笔重绘，不在布局作用域内触发 `setState`。
- **后台休眠门控**：`NetworkTelemetryPanel` 的 `1 s` 周期探测与 `VoiceActivityRibbon` 消费的 `voiceLevelsProvider`（`StreamProvider.autoDispose`）同时受 `WidgetsBindingObserver` 生命周期与 `TickerMode.valuesOf(context).enabled` 门控。进入 `hidden`、`paused`、`detached` 或 `TickerMode` 关闭时，在生命周期与依赖回调内同步停止定时器并通过 `ref.listenManual` 立即关闭流订阅；`resumed` 与桌面端并行窗口失焦的 `inactive` 阶段保持活跃。`ExpressiveFrame` 与 `MemberAvatar` 说话光环同时遵守 `MediaQuery.disableAnimationsOf(context)`。

