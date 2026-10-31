# AGENTS.md — 连接与档案管理 (lib/features/connect)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/features/connect/`。

## 规则与约束

- **输入校验**：服务器地址输入框仅接受 IP、域名或 `localhost`（可带端口）；裸昵称直接在 UI 提示格式错误，不提交给下游。
- **档案加载与维护**：本地服务器档案列表通过 `SessionController` 读写，支持增删改查与别名标注。
- **连接反馈**：连接状态通过全局 `SessionState` 响应式展示（连接中、错误提示等），错误字段紧邻对应输入项展示。
