# AGENTS.md — 公共 UI 组件库 (lib/widgets)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/widgets/`。

## 规则与约束

- **悬停提示与无障碍名称**：遵守 [Flutter 界面文案与操作按钮约束](../../docs/defensive-patterns/ui.md)。
- **纯粹展示与通用性**：本目录组件保持高度通用，不耦合具体业务模型或特定的会话状态；通过属性参数与回调与外部解耦。
- **窗口手势安全**：涉及桌面端窗口拖拽区域（`WindowDragRegion`）时，不得遮挡返回按钮或可交互图标的触摸/点击手势。
- **视觉与交互原语**：表面层级、超椭圆圆角、按压反馈（`PressSurface` / `ElasticButton` / `AnimatedInkWell`）、`TonalButton` 与弹出层由子模块 `plugins/prism_ui` 经 [lib/widgets/prism.dart](prism.dart) 桥接提供，规范详见 [docs/subsystems/ui-design.md](../../docs/subsystems/ui-design.md)。
