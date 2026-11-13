# AGENTS.md — 公共 UI 组件库 (lib/widgets)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/widgets/`。

## 规则与约束

- **悬停提示与无障碍名称**：遵守 [Flutter 界面文案与操作按钮约束](../../docs/defensive-patterns/ui.md)。
- **纯粹展示与通用性**：本目录组件保持高度通用，不耦合具体业务模型或特定的会话状态；通过属性参数与回调与外部解耦。
- **窗口手势安全**：涉及桌面端窗口拖拽区域（`WindowDragRegion`）时，不得遮挡返回按钮或可交互图标的触摸/点击手势。
- **Prism 优先与桥接扩展**：标准控件、表面层级、超椭圆圆角、按压反馈（`PressSurface` / `ElasticButton` / `AnimatedInkWell`）、`TonalButton`、开关与弹出层均优先经 [lib/widgets/prism.dart](prism.dart) 复用子模块 `plugins/prism_ui`（含未转出子模块的补充导出）；`lib/widgets/` 仅承接业务装配、窗口宿主交互与 `prism_ui` 未覆盖的专项视觉组件，规范详见 [docs/subsystems/ui-design.md](../../docs/subsystems/ui-design.md)。
