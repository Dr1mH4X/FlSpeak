# AGENTS.md — FFI bridge

这些规则补充根 [AGENTS.md](../../AGENTS.md)，只覆盖 `plugins/flspeak_ffi/`。

- `rust/src/api/session.rs` 是 flutter_rust_bridge 唯一解析的模块。新增或修改
  Dart 可见类型时只改这里，不要把 `core/` 的内部类型直接暴露给桥。
- 这一层只做转发和类型转换。协议、连接边界、音频和持久化逻辑留在 `core/`。
- 改完 `rust/src/api/**` 后重跑：

  ```sh
  cd plugins/flspeak_ffi
  flutter_rust_bridge_codegen generate
  ```

  生成物包括 `rust/src/frb_generated.rs`、`lib/src/rust/**` 和
  `api/*.freezed.dart`，不要手改。
- Dart 只通过 `CoreSession.events()` 接收 UI 事件；语音帧不走这条通道。
- `CoreSession` 的订阅取消放在 `shutdown()` 之后，避免等待下一次广播失败才收尾。
- 错误统一映射成 `CoreError::InvalidAddress`、`BlockedAddress`、`Connection` 或 `Internal`，
  Dart 不解析 Rust 的内部错误文本。

Flutter 侧的规则见 [lib/AGENTS.md](../../lib/AGENTS.md)。
