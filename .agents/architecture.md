# 架构

## 分层

```text
Flutter UI (lib/)
  │  只读 sessionViewProvider；只调用语义化命令
  ▼
FFI (plugins/flspeak_ffi)
  │  api/session.rs：薄转发 + 类型转换，Dart 侧类型在这里定义
  ▼
session      命令队列 + 事件广播；独占 Client
  ▼
proto        策略门 + deny-all 解析器 + 建连
  ▼
policy       地址合法性、T1 硬拦、T2 登记
  ▼
tsclient-rs           Teamspeak 协议实现（crates.io 依赖）
```

音频链路是旁路：`audio` 直接由会话 actor 使用（见 `docs/audio.md`），
Dart 全程不接触音频数据。

## 为什么是 actor

tsclient-rs 的 `Client` 有两个特性决定了边界形状：

1. `connect` 等路径跨 `.await` 持 `std::sync::Mutex`（crate 级 `allow(await_holding_lock)`），
   这些 future 不是 `Send`。放进普通 `tokio::spawn` 直接编译不过。
2. 接收侧每个处理器、每个包 spawn 一个任务，处理器注册多次就会成倍放大。

所以：

- `SessionHandle::spawn` 起一个**独占线程**，跑 current-thread runtime + `LocalSet`，
  non-Send 的协议 future 在这里合法执行。
- 所有协议操作经 `mpsc` 命令通道串行进入 actor，用 `oneshot` 回结果。
- 事件经 `broadcast` 出去（容量 256，慢订阅者收到 `Lagged` 后跳过旧事件）。
- 每类事件只注册一个处理器，处理器只做“转成 `SessionEvent` 后广播”。
- **取消事件订阅要在 `shutdown()` 之后**：关闭会话会关掉广播通道，Rust 侧转发任务随即退出，
  这时 Dart 取消订阅立刻完成；反过来先取消，要等下一次 `add` 失败才收尾。

## 一次连接发生了什么

1. Dart 调 `registerServer(label, address)` → actor 调 `ServerRegistry::register`
   → **T1**：地址必须能解析成 host[:port]，不能是裸昵称，不能命中官方禁连清单。
2. 通过后成为档案，写进 `servers.json`，事件 `Servers` 推给 Dart。
3. Dart 调 `connect(id, nickname)` → actor 从档案取地址（**T2**：连接目标只能来自档案）。
4. 身份从 `identity.txt` 读，缺失则生成并存盘。
5. `proto::client` 再校验一次，构造 `Client`，强制注入 deny-all `AddrResolver`。
6. `connect()` + `wait_connected()` 带 20s 超时；失败先 `disconnect()` 再抛错。
7. 成功后 `Arc<Client>` 交给 actor，事件 `State(Connected{client_id, channel_id})`。

## 事件到界面

`SessionEvent` 在 FFI 层翻成 `CoreEvent`（freezed），Dart 的 `SessionController` 把它
收敛成一个 `SessionView`：连接状态、服务器列表、频道列表、在线成员、聊天消息、提示条。
页面永远只读这个快照。

## 尚未接线

- 语音：`audio` 已实现并有单测，但还没接进 actor（既不发也不收）。
- 文件传输：策略层已有 `check_transfer_host`，FFI 未暴露，Dart 无法传主机名。
- 私聊/频道消息的完整历史：只保留本次会话收到的消息。