# 决策记录：会话 actor 跑在独占线程的 LocalSet 上

日期：2026-10-08
状态：已实施

## 背景

第一版把 actor 循环放进 `tokio::spawn`，编译失败：

```text
error[E0277]: `std::sync::MutexGuard<'_, tsclient_rs::client::ClientInner>`
              cannot be sent between threads safely
   --> core/session/src/lib.rs:150:9
```

原因是 `Client::connect` / `wait_connected` 等 future 在 `.await` 期间持有
`std::sync::MutexGuard`（tsclient-rs 在 crate 级 `allow(clippy::await_holding_lock)`），
所以这些 future 不是 `Send`，无法交给多线程 runtime 的 `spawn`。

## 决策

`SessionHandle::spawn` 起一个名为 `session` 的独占线程，在 current-thread
runtime 上跑 `LocalSet::block_on`，actor 循环作为 non-Send future 在里面执行。

命令通道（`mpsc`）、回复通道（`oneshot`）、事件广播（`broadcast`）都是 `Send` 的，跨线程
没有问题；Dart 侧的异步调用只做“发命令 + 等回复”。

## 被否决的方案

- **把 connect 换成 `block_in_place` + `Handle::block_on`**：只修了 connect，其他
  `Client` 方法（`exec_command_with_response`、`listChannels`…）在同样的锁模式下随时会
  再踩一次；而且坑在多线程 runtime 内的行为更难讲清楚。
- **复制一份 transport 代码去掉跨 await 的锁**：等于 fork 上游，维护成本不可接受。
- **改成 current-thread runtime + `spawn_local`，但共用一个 runtime**：actor 是长生命周期
  的，给它独占线程最省心；会话本来也只需要一个。

## 后果

- 每个会话一个线程（本客户端只有单会话）。
- `SessionHandle::spawn` 返回 `Result`，线程创建失败会以 `SessionError::Spawn` 暴露，
  actor 的 runtime 启动失败则以 `SessionEvent::Failed` 事件暴露。
- 全仓库的协议调用都被这条边界挡住，不会再出现跨 await 持锁引发的 `Send` 问题。