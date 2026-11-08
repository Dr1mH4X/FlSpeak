# AGENTS.md — 会话管理与并发调度 (core/session)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `core/session` crate。

## 规则与约束

- **Actor 独占 Client**：`tsclient_rs::Client` 仅由本 crate 内的专属 Actor 线程持有，外部调用必须通过 MPSC 信道排队串行执行。
- **旁路语音发送**：编码后的语音包通过专用通道送入 Actor，由 Actor 串行调用 `send_voice`。
- **日志订阅器归属**：Rust 全局 `tracing` 订阅器与文件 worker 由 `core/session::logging` 独占管理，FFI 仅作调用转发；队列强制 `lossy(true)` 保证非阻塞，初始化保证幂等性与 guard 安全。
- **日志归属与真相来源**：遵循 [../../docs/defensive-patterns/logging.md](../../docs/defensive-patterns/logging.md)，会话状态机、协议交互与底层错误一律通过 `tracing` 归入 `backend.YYYY-MM-DD.log`，作为核心状态唯一权威事实来源。
- **广播通道容量与背压**：事件广播通道固定容量为 256，UI 滞后触发 `Lagged` 丢弃旧事件；频道快照按固定周期触发。
- 完整子系统契约见 [../../docs/subsystems/session.md](../../docs/subsystems/session.md)。
