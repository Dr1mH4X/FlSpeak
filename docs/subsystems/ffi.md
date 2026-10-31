# 子系统契约 — plugins/flspeak_ffi

本文定义 `plugins/flspeak_ffi` 的职责、关键调用序列与不变量。

## 职责

- 基于 `flutter_rust_bridge` 提供 Rust 核心库与 Flutter (Dart) 运行期之间的高性能双向交互桥。
- 维护 Dart 可见的纯视图模型（`*View`），阻断 `core/` 内部数据结构直接泄漏给生成代码。
- 将 Rust 底层异步事件收敛为 `StreamSink`，提供面向 Flutter UI 的单向不可变事件流 `CoreSession.events()`。
- 将 Rust 侧复杂错误统一归一化为枚举型 `CoreError`，消除字符串匹配依赖。

## 关键路径与序列

1. **会话创建与初始化**：
   Flutter 调用 `CoreSession.create(dbPath, storagePath)` → FFI 层拉起全局 Tokio 运行时并构建底层 `SessionHandle`。
2. **UI 命令调用派发**：
   Flutter 触发动作（如 `connect`, `switchChannel`, `sendMessage`） → FFI 桥函数完成入参从 Dart 类型到 Rust Core 类型的映射 → 异步调用对应 `SessionHandle` 方法 → 映射返回值或抛出结构化 `CoreError`。
3. **事件流订阅与清理**：
   Flutter 在初始化阶段建立事件订阅 → Rust 侧监听 `broadcast::Receiver<SessionEvent>` 并推送到 `StreamSink` → 当会话 `shutdown()` 时主动关闭 Sink，释放所有订阅者上下文。

## 不变量

- `rust/src/api/session.rs` 是 flutter_rust_bridge 唯一被扫描的解析入口，严禁暴露未经视图包装的 `core/` 原始结构体。
- FFI 桥绝不承载业务逻辑、地址解析策略或音频编解码操作，只做契约转发与类型转换。
- 生成代码（`rust/src/frb_generated.*`、`lib/src/rust/**`）禁止人工编辑，变更接口后统一通过 codegen 刷新。
