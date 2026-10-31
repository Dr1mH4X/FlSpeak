# AGENTS.md — 会话主工作区 (lib/features/workspace)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/features/workspace/`。

## 规则与约束

- **组件响应式更新**：工作区（频道树、成员列表、聊天窗口）纯依赖 `SessionView` 渲染，严禁在 Widget State 中私自缓存成员或频道列表。
- **无悬停提示原则**：严格执行全仓无悬停提示规则，禁止使用 `Tooltip`，禁止给 `IconButton` 等传入 `tooltip:` 参数；无障碍文本统一使用 `Semantics` 或 `semanticLabel`。
- **消息发送与限制**：文本消息直接提交给控制器，长消息和图床上传遵从既定大小和格式约束。
