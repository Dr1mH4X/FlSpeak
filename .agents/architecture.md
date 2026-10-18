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
proto        SRV 解析 + 最终连接边界 + deny-all 解析器 + 建连
  ├────────> server   档案模型 + 地址解析 + 本地登记
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
   → `server::parse_address` 只接受 IP/域名和可选端口，拒绝裸昵称。
2. 通过后成为档案，写进 `servers.json`，事件 `Servers` 推给 Dart。
3. Dart 调 `connect(id, nickname)` → actor 从档案取地址，连接目标只能来自档案。
4. 身份从 `identity.txt` 读，缺失则生成并存盘。
5. `proto::resolve_target` 先做 SRV 查询（标准 DNS）；`proto::client` 在最终目标上
   检查一次官方主机清单，构造 `Client`，强制注入 deny-all `AddrResolver`。
6. `connect()` + `wait_connected()` 带 8s 超时；失败先 `disconnect()`。连续 3 次握手超时
   触发身份等级提升（+5，上限 29，独立线程、可取消、原子写身份文件）。
7. 成功后 `Arc<Client>` 交给 actor，事件 `State(Connected{client_id, channel_id})`，
   随后拉取频道/成员/codec 快照与历史消息；capture/playback 线程按频道 codec 启动。
8. 非主动断开按 1/2/4/15/30/…s 退避重连；首轮成功前最多 5 次，之后不限次。

## 事件到界面

`SessionEvent` 在 FFI 层翻成 `CoreEvent`（freezed），Dart 的 `SessionController` 把它
收敛成一个 `SessionView`：连接状态、服务器列表、频道列表、在线成员、聊天消息、提示条。
页面永远只读这个快照。

## 尚未接线

- 聊天图片：TS6 官方图片是 `ts.file.myts` JSON，字节在 myTS 附件服务；当前只显示
  “不支持的图片格式”。第三方 URL 走 `core/session::images::fetch_image`（DNS/私网/
  重定向/大小校验），图床上传未接线。见 `docs/images.md`。
- TSDNS：可选 legacy fallback，当前只做 SRV，未实现 TSDNS。
- 文件传输 UI：后端与 FFI 已暴露上传/下载、进度事件，Dart 还没有文件选择器和传输列表。
- 历史清除入口：`messages.jsonl` 已持久化并在连接时回放，设置页还不能清除。
- 音频处理：没有 AEC/降噪/AGC；语音包没有 seq，播放只能按到达顺序做固定延迟 jitter。
- 频道创建/删除没有实时事件，靠 30s 轮询快照兜底。
