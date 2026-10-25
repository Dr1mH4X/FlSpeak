# Agent Note: 会话 actor 跑在独占线程的 LocalSet 上

Status: implemented

## Problem

第一版把 actor 循环放进 `tokio::spawn`，编译失败：

```text
error[E0277]: `std::sync::MutexGuard<'_, tsclient_rs::client::ClientInner>`
              cannot be sent between threads safely
```

tsclient-rs 的 `Client::connect` / `wait_connected` 等 future 在 `.await` 期间持有
`std::sync::MutexGuard`（crate 级 `allow(clippy::await_holding_lock)`），这些 future 不是
`Send`，无法交给多线程 runtime 的 `spawn`。

## Decision

`SessionHandle::spawn` 起一个名为 `session` 的独占线程，在 current-thread runtime 上跑
`LocalSet::block_on`，actor 循环作为 non-Send future 在里面执行。

命令通道（`mpsc`）、回复通道（`oneshot`）、事件广播（`broadcast`）都是 `Send` 的，跨线程
没有问题；Dart 侧的异步调用只做「发命令 + 等回复」。

## Alternatives considered

- **把 connect 换成 `block_in_place` + `Handle::block_on`**：只修 connect 一处，
  `exec_command_with_response` 等其他 `Client` 方法在同样的锁模式下随时会再踩一次；而且
  这个坑在多线程 runtime 内的行为更难讲清楚。
- **复制一份 transport 代码去掉跨 await 的锁**：等于 fork 上游 tsclient-rs，维护成本
  不可接受。
- **current-thread runtime + `spawn_local`，但与其他任务共用一个 runtime**：actor 是
  长生命周期任务，给它独占线程最省心；本客户端本来也只有单会话。

## Consequences

- 每个会话一个线程（本客户端只有单会话）。
- `SessionHandle::spawn` 返回 `Result`，线程创建失败以 `SessionError::Spawn` 暴露；actor
  的 runtime 启动失败以 `SessionEvent::Failed` 事件暴露。
- 全仓库的协议调用都被这条边界挡住，不会再出现跨 await 持锁引发的 `Send` 问题。
