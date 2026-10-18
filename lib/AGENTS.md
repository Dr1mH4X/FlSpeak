# AGENTS.md — Flutter UI

这些规则补充根 [AGENTS.md](../AGENTS.md)，只覆盖 `lib/`。

- `SessionController` 消费唯一的 `CoreEvent` 流，并收敛成不可变
  `SessionView`；页面只读 `sessionViewProvider`，不要各自保存会话状态。
- UI 只发语义化命令：添加服务器、连接、切换频道、发消息、静音、设备选择。
  不把协议字段、地址校验或音频处理写进 widget。
- 服务器地址输入只接受 IP、域名或 `localhost`（可带端口）；裸昵称在 UI 先拒绝，
  官方主机边界仍由 Rust 的最终出口处理。
- 所有用户可见文案走 `arb/`，不在 widget 里硬编码中文或英文。
- `lib/l10n/**` 是生成物，不要手改；改 `arb/` 后重跑 `flutter gen-l10n`。
- FFI 生成类型在 `plugins/flspeak_ffi/lib/src/rust/**`，同样不要手改。
- 页面布局可以依赖 `SessionView`，但不能依赖 `CoreSession` 的内部状态。

完整编码约定见 [.agents/rules.md](../.agents/rules.md)。
