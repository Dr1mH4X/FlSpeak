# 架构

## 分层

```text
Flutter UI (lib/)
  │  只读 sessionViewProvider；只发语义化命令
  ▼
FFI 边界 (plugins/flspeak_ffi)
  │  api/session.rs 是 flutter_rust_bridge 唯一解析的模块
  ▼
session      命令队列 + 事件广播，独占 Client
  ▼
proto        SRV 解析 + 最终连接边界 + deny-all 解析器 + 建连
  ├────────> server   服务器档案、地址解析与本地登记
  ▼
tsclient-rs           协议实现（来源与固定提交见 Cargo.toml）
```

Flutter 负责界面，Rust 负责协议、连接边界与音频。Dart 不持有身份私钥，
也不把音频帧带过 FFI。

音频是旁路：capture/playback 两条线程各自独占 cpal 流，cpal 回调只搬
`ArrayQueue`；编码后的包回到 actor，由 actor 串行 `send_voice`。见
`docs/audio.md`。

## 一次连接

```text
Dart: registerServer(label, "ts.example.com:9987")
  └─ FFI 转发 ─> actor ─> server::parse_address
                 ├─ 拒绝：不是 IP/域名、端口非法或裸昵称
                 └─ 通过：写 servers.json，广播 Servers 事件
Dart: connect(id, nickname)
  └─ FFI 转发 ─> actor
        ├─ 从档案取 host:port（连接目标只能来自档案）
        ├─ 读/生成 identity.txt（Dart 拿不到私钥）
        ├─ proto::resolve_target 做 SRV 查询
        ├─ proto::client 对最终目标做一次官方主机检查
        ├─ 注入 DenyResolver + Client::new
        ├─ connect() + wait_connected()（8s 超时；连续 3 次超时提升身份等级）
        └─ 成功：广播 State(Connected{client_id, channel_id}) → Snapshot
             → History；进入支持的频道后启动语音
Dart: listChannels() / moveToChannel() / sendText()
  └─ 全部经同一个命令队列串行执行
```

`server::parse_address` 只接受 IP、域名、`localhost` 和可选端口。裸昵称会被拒绝，
因此 `named.myteamspeak.com/lookup` 不会从正常录入路径进入。`proto::client`
是唯一的最终出口检查：目标命中官方主机清单时直接拒绝。SRV 查询失败会回退到
档案里的字面地址；SRV 返回的目标也必须在 `client` 这一步通过检查。

## 事件流

Rust 侧把协议事件收敛成 `SessionEvent`，FFI 翻成 `CoreEvent`（freezed），Dart 的
`SessionController` 再收敛成一个不可变 `SessionView`：

```text
State / Servers / Snapshot / History / TextMessage / ClientJoined / ClientLeft /
ClientMoved / Voice / Speaking / SelfSpeaking / IdentityUpgrade / IdentityUpgraded /
Transfer* / Log / Denied / Failed
```

- 广播通道容量 256；订阅慢时旧事件被丢弃，订阅者收到 `Lagged` 后继续。
- `Log` 事件目前不入界面，保留给调试面板。
- 语音帧不在这条链路上。

## 线程与并发模型

| 线程 | 职责 |
| --- | --- |
| Flutter main isolate | UI、`Stream<CoreEvent>` 消费 |
| FFI runtime（2 线程，`OnceLock`） | 事件转发任务（`broadcast` → `StreamSink`） |
| `session` 线程 | current-thread runtime + `LocalSet`，串行执行所有协议调用 |
| `voice-capture` 线程 | cpal 输入、格式转换、VAD/PTT、20ms Opus、发送节拍 |
| `voice-playback` 线程 | cpal 输出、每说话人 jitter/解码/混音、设备格式转换 |

会话线程必须独占的原因见 `.agents/notes/implemented/architecture/2026-10-08-session-actor.md`：
tsclient-rs 的建连 future 不是 `Send`。

## 目录职责

| 路径 | 职责 |
| --- | --- |
| `core/server` | `ServerProfile`、`ServerRegistry`、地址解析；无网络、无协议依赖 |
| `core/proto` | `resolve_target`、`DenyResolver`、最终连接边界、`client()`、`check_transfer_host()` |
| `core/session` | `SessionHandle` / actor / 档案与身份持久化 / 第三方图片 URL 抓取 |
| `core/audio` | 设备枚举、双线程采集/播放、Opus、VAD、jitter/PLC、软削波 |
| `plugins/flspeak_ffi` | Dart 侧类型、转发、事件桥、生成物 |
| `lib/` | UI、状态收敛、本地化 |

## 尚未接线

- 聊天图片：TS6 官方图片是 `ts.file.myts` JSON，字节在 myTS 附件服务；FlSpeak 不带
  myTS token，只显示“不支持的图片格式”。第三方 URL 经 `fetchImage` 安全抓取；图床上传
  未接线。边界见 `docs/connection-boundary.md`。
- 聊天正文：Dart `MessageContent` 渲染 TS6 Markdown 的一个子集；原始文本不做转换，
  历史里保留原样。
- TSDNS：可选 legacy fallback，当前只做 SRV，未实现 TSDNS。
- 文件传输 UI：FFI 已暴露上传/下载与进度事件，Dart 还没有文件选择器和传输列表。
- 历史清除入口：历史已持久化并回放，设置页还不能清除。
- 音频处理：没有 AEC/降噪/AGC；语音包没有 seq，播放只能按到达顺序做固定延迟 jitter。
- 频道创建/删除没有实时事件，靠 30s 轮询快照兜底。
- 身份升级的挖矿进度只有开始/完成事件，没有百分比。
