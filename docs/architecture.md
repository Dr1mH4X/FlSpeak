# 架构

## 分层

```text
Flutter UI (lib/)
  │  只读 sessionViewProvider，只发语义化命令
  ▼
FFI 边界 (plugins/flspeak_ffi)
  │  api/session.rs 是 flutter_rust_bridge 唯一解析的模块
  ▼
session      命令队列 + 事件广播，独占 Client
  ▼
proto        合规门 + deny-all 解析器 + 建连
  ▼
policy       地址校验（T1）、档案登记（T2）、禁连清单
  ▼
tsclient-rs           协议实现（crates.io 依赖 0.1.5）
```

职责划分一句话：**Flutter 负责 UI，Rust 负责业务逻辑与协议实现**。Dart 侧没有任何协议
知识，也不持有身份私钥。

音频是旁路：`audio` 由会话 actor 直接使用，音频数据不进 FFI（见 `audio.md`）。

## 一次连接的时序

```text
Dart: registerServer(label, "ts.example.com:9987")
  └─ FFI 转发 ─> actor ─> policy 校验（T1）
                 ├─ 拒绝：返回 CoreError.policyDenied（官方域名 / 裸昵称 / 非法端口）
                 └─ 通过：写 servers.json，广播 Servers 事件
Dart: connect(id, nickname)
  └─ FFI 转发 ─> actor
        ├─ 从档案取 host:port（T2：地址只能来自档案）
        ├─ 读/生成 identity.txt（Dart 拿不到私钥）
        ├─ proto 再校验 + 注入 DenyResolver + Client::new
        ├─ connect() + wait_connected()（20s 超时）
        └─ 成功：广播 State(Connected{client_id, channel_id})
Dart: listChannels() / moveToChannel() / sendText()
  └─ 全部经同一个命令队列串行执行
```

## 事件流

Rust 侧把协议事件收敛成 `SessionEvent`，FFI 翻成 `CoreEvent`（freezed），Dart 的
`SessionController` 再收敛成一个不可变 `SessionView`：

```text
State / Servers / TextMessage / ClientJoined / ClientLeft / ClientMoved / Log / Denied / Failed
```

- 广播通道容量 256；订阅慢时旧事件被丢弃，订阅者收到 `Lagged` 后继续。
- `Log` 事件目前不入界面（避免刷屏），保留给调试面板。
- 语音帧不在这条链路上。

## 线程与并发模型

| 线程 | 职责 |
| --- | --- |
| Flutter main isolate | UI、`Stream<CoreEvent>` 消费 |
| FFI runtime（2 线程，`OnceLock`） | 事件转发任务（`broadcast` → `StreamSink`） |
| `session` 线程 | current-thread runtime + `LocalSet`，串行执行所有协议调用 |

会话线程必须独占的原因见 `.agents/notes/implemented/2026-10-08-session-actor.md`：
tsclient-rs 的建连 future 不是 `Send`。

## 目录职责

| 路径 | 职责 |
| --- | --- |
| `core/policy` | 地址合法性、禁连清单、档案注册表；无网络、无协议依赖 |
| `core/proto` | `approve()`、`DenyResolver`、`client()`、`check_transfer_host()` |
| `core/session` | `SessionHandle` / actor / 档案与身份持久化 |
| `core/audio` | 设备枚举、采集、播放、Opus 编解码、说话人队列 |
| `plugins/flspeak_ffi` | Dart 侧类型、转发、事件桥、生成物 |
| `lib/` | UI、状态收敛、本地化 |

## 尚未接线

- 语音收发：`audio` 有实现与单测，但 actor 还没有接上语音包。
- 文件传输：策略层已具备主机校验，FFI 未暴露，Dart 无法传主机名。
- 频道/成员快照是拉取式的（连接后与手动刷新），没有持续同步。