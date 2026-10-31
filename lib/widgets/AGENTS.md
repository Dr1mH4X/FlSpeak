# AGENTS.md — 公共 UI 组件库 (lib/widgets)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/widgets/`。

## 规则与约束

- **禁止悬停提示**：不引入 `Tooltip`，也不给 `IconButton` 等控件传 `tooltip:` 参数。图标按钮的无障碍名称统一通过 `semanticLabel` 或 `Semantics` 提供。
- **纯粹展示与通用性**：本目录组件保持高度通用，不耦合具体业务模型或特定的会话状态；通过属性参数与回调与外部解耦。
- **窗口手势安全**：涉及桌面端窗口拖拽区域（`WindowDragRegion`）时，不得遮挡返回按钮或可交互图标的触摸/点击手势。
