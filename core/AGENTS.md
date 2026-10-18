# AGENTS.md — Rust core

这些规则补充根 [AGENTS.md](../AGENTS.md)，只覆盖 `core/`。

## 边界

- `server` 只负责服务器档案和地址解析，不判断是否允许连接。
- `proto` 负责 SRV 解析和唯一的最终连接边界；`client` 在建连前检查一次
  官方主机清单，其他 crate 不复制这份清单。
- `session` 独占 `Client`。所有协议调用都经 actor 的命令队列串行执行，
  FFI、Dart 或音频线程不得直接调用 tsclient-rs。
- `audio` 自己采集、编码、解码和播放。音频帧不进入 FFI；编码后的包回到
  actor，由 actor 调用 `send_voice`。
- 保持依赖方向：`server` 不依赖网络或协议；`proto` 依赖 `server`；
  `session` 依赖 `proto` 与 `audio`；FFI 只依赖 `session`。

## 实现约定

- 错误用 `thiserror`，每层一个错误类型；跨层用 `#[from]`，不要用 `unwrap`
  掩盖失败。
- 公共类型字段默认 `pub`，与 tsclient-rs 的风格保持一致；内部细节才收窄。
- Rust 单测写在模块内 `#[cfg(test)] mod tests`，不依赖网络或真实服务器。
- 需要官方域名做测试夹具时，从 `proto::FORBIDDEN_HOST_SUFFIXES` 拼，
  不要写字面量。

完整编码约定见 [.agents/rules.md](../.agents/rules.md)。
