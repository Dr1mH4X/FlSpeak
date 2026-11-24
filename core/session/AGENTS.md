# AGENTS.md — 会话管理与并发调度 (core/session)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `core/session` crate。

## 规则与约束

- **Actor 独占 Client**：`tsclient_rs::Client` 仅由本 crate 内的专属 Actor 线程持有，外部调用必须通过 MPSC 信道排队串行执行。
- **旁路语音发送**：编码后的语音包通过专用通道送入 Actor，由 Actor 串行调用 `send_voice`。
- **日志订阅器归属**：Rust 全局 `tracing` 订阅器与文件 worker 由 `core/session::logging` 独占管理，FFI 仅作调用转发；队列强制 `lossy(true)` 保证非阻塞，初始化保证幂等性与 guard 安全。
- **日志归属与真相来源**：遵循 [../../docs/defensive-patterns/logging.md](../../docs/defensive-patterns/logging.md)，会话状态机、协议交互与底层错误一律通过 `tracing` 归入 `backend.YYYY-MM-DD.log`，作为核心状态唯一权威事实来源。
- **广播通道容量与背压**：事件广播通道固定容量为 256，UI 滞后触发 `Lagged` 丢弃旧事件；频道快照按固定周期触发。
- **媒体与图片归属**：`core/session::media` 统一管理本地媒体磁盘缓存（`IconCache`、`AvatarDiskQueue`）与第三方图片抓取和图床上传；生产代码中成员头像与自头像快照的磁盘读写仅经 `AvatarDiskQueue` 单一 FIFO 阻塞线程执行。
- **Actor 子状态封装与生命周期重置**：`Actor` 内部子域状态封装在各自子模块的私有结构体中（`actor::connect::ReconnectState`、`actor::directory::DirectoryState`、`actor::streams::StreamCoordinatorState`、`actor::transfers::MediaTransferState`），仅通过窄方法读写；断线与切频道清理统一收口到各子状态的 `reset_on_disconnect()`（`DirectoryState` 与 `StreamCoordinatorState` 另提供 `reset_on_channel_change()`）。
- 完整子系统契约见 [../../docs/subsystems/session.md](../../docs/subsystems/session.md)。
