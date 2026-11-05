# AGENTS.md — 会话主工作区 (lib/features/workspace)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/features/workspace/`。

## 规则与约束

- **组件响应式更新**：工作区（频道树、成员列表、聊天窗口）纯依赖 `SessionView` 渲染，严禁在 Widget State 中私自缓存成员或频道列表。
- **悬停提示与无障碍名称**：遵守 [Flutter 界面文案与操作按钮约束](../../../docs/defensive-patterns/ui.md)。
- **消息发送与限制**：文本消息直接提交给控制器，长消息和图床上传遵从既定大小和格式约束。
