# AGENTS.md — Flutter UI

这些规则补充根 [AGENTS.md](../AGENTS.md)，只覆盖 `lib/`。

- UI 控件、表面层级与交互反馈优先经 [lib/widgets/prism.dart](widgets/prism.dart) 使用 `prism_ui` 原语（缺口导出在桥接文件补充），不在页面或公共组件中手写同名替代控件或回退到冲突的 Material 组件，规格见 [../docs/ui-design.md](../docs/ui-design.md)。
- `SessionController` 消费唯一的 `CoreEvent` 流，并收敛成不可变 `SessionView`；页面只读 `sessionViewProvider`，不要各自保存会话状态。
- UI 只发语义化命令：添加服务器、连接、切换频道、发消息、静音、设备选择。不把协议字段、地址校验或音频处理写进 widget。
- 服务器地址输入只接受 IP、域名或 `localhost`（可带端口）；裸昵称在 UI 先拒绝，官方主机边界仍由 Rust 的最终出口处理。
- 所有用户可见文案走 `arb/`，不在 widget 里硬编码中文或英文。
- `lib/l10n/**` 是生成物，不要手改；改 `arb/` 后重跑 `flutter gen-l10n`。`arb/intl_en.arb` 与 `arb/intl_zh.arb` 的 key 集合严格对齐，新增文案两份同步加。
- FFI 生成类型在 `plugins/flspeak_ffi/lib/src/rust/**`，同样不要手改。
- 页面布局可以依赖 `SessionView`，但不能依赖 `CoreSession` 的内部状态。
- 页面级瞬时错误与提示统一走 `lib/core/notices.dart` 的 `NoticeCenter` 门面，由 `lib/app.dart` 挂载的 `prism_ui` `BannerHost` 渲染；不要在页面或卡片里自建错误横幅，也不要用 `SnackBar`。字段校验留在输入框旁，持久状态（设备不可用 chip、身份提升横幅）留在页面上。
- 动画曲线与时长统一走 `AppMotion`，并受 `AppearanceSettings.reduced_motion` 约束：减少动效时动画与 `shaders/` 的片元着色器一律降级为静态背景。
- 系统目录调起统一经 `launchOrCopyDirectory`，调用限最长 3 秒超时，失败或超时后降级为把目录路径写入剪贴板并提示用户。
- 桌面端窗口拖拽区（`WindowDragRegion`）不得遮挡返回按钮或可交互图标的点击手势。
- Dart 单测统一存放在根目录 `test/` 下（镜像 `lib/` 目录结构），靠 `just test`（即 `flutter test`）跑。

编码反面见 [../docs/defensive-patterns/README.md](../docs/defensive-patterns/README.md)，Flutter 文案与操作按钮约束见 [../docs/defensive-patterns/ui.md](../docs/defensive-patterns/ui.md)，Flutter 界面性能与帧预算约束见 [../docs/defensive-patterns/ui-performance.md](../docs/defensive-patterns/ui-performance.md)，性能探针流程见 [../.agents/skills/fls-ui-performance/SKILL.md](../.agents/skills/fls-ui-performance/SKILL.md)，开发流程与语言约定见 [../docs/development.md](../docs/development.md)。