# 后端收口设计

日期：2026-10-17（2026-10-18 更新为双线程语音）
状态：已实施（文件传输 UI、历史清除入口、AEC/降噪留待后续）

这份文档记录“后端收口”这一轮的边界与取舍：语音端到端、频道/成员持续同步、断线重连、
身份等级提升、消息历史与文件传输。不变量仍然以 `AGENTS.md` 与 `docs/connection-boundary.md`
为准，本文只解释新增部分为什么长这样。

## 范围

| 能力 | 这轮做到 | 不做 |
| --- | --- | --- |
| 语音 | capture/playback 双线程；采集 → Opus → actor 发送；接收 → 每说话人 jitter/解码/混音 → 播放；mute/deafen/PTT；频道跟随 codec | 回声消除、降噪、AGC、3D 声像、真正的包重排序 |
| 同步 | 连接后拉取快照；成员事件增量更新；连接期间每 30s 轮询频道/成员/codec | 频道创建/删除的实时通知（上游没暴露） |
| 重连 | 1/2/4/15/30/…s 退避，首轮成功前最多 5 次、之后不限次；自动回原频道，UI 提供按钮 | 会话恢复、未发送消息重放 |
| 身份 | 连续 3 次握手超时自动 +5 安全等级，独立线程挖矿、可取消、原子写入 | 自动选等级/导入身份 |
| 历史 | 文本消息按服务器持久化，连接时回放，500 条/服务器 | 搜索、导出、端到端加密 |
| 文件传输 | 上传/下载、进度事件、主机固定为 SRV 解析后的会话主机、精确字节传输 | 目录浏览、断点续传、UI 文件选择器 |

## 语音

### 线程与所有权

```text
session 线程（actor，独占 Client）
  │  控制命令（mute/deafen/PTT/codec/设备）
  ├──────────────┐
  ▼              ▼
capture 线程     playback 线程
cpal 输入        cpal 输出
  │                ▲
  └── Outbound ──> actor ── Client::send_voice(data, codec)
                         ← on_voice_data ── 有界通道
```

- `cpal::Stream` 不是 `Send`，必须在创建它的线程上使用和销毁。capture/playback 各占一个
  普通 `std::thread`；actor 只拿命令句柄，不碰设备对象。
- cpal 回调只做 `ArrayQueue` 的 push/pop，零分配、零锁；格式转换、VAD、Opus、混音都在
  工作线程。Mumble 的 CoreAudio 回调里直接编码/混音是反面教材。
- 所有 `Client` 调用仍然只在 actor 里发生。capture 线程只产出已编码包，经
  `AudioEvent::Outbound` 回到 actor，由 actor 串行 `send_voice`。
- `on_voice_data` 只把 `VoiceFrame` 塞进 playback 的有界通道；满了就丢，不在收包回调里
  解码。
- 控制通道和语音数据通道分开：mute/deafen 不会被语音帧挤掉。

### 采集

- 10ms tick 排空输入 ring；设备格式 → 48kHz 目标声道（codec 4 单声道 / codec 5 立体声）。
- 20ms 成帧；能量 VAD（阈值 0.012、250ms 尾音）或 PTT 决定是否发送。VAD 是 `Vad` trait，
  将来换 RNNoise 不动结构。
- 语音段开始重置 Opus 编码器；mute/deafen 清空缓冲并停发，解静音不补发旧音频。
- `VoicePacer` 稳态 20ms、空闲复位、落后 >200ms 重定位。
- actor 发送前检查载荷 ≤484 字节（TS 单包 500 字节）。

### 播放

- 每说话人独立 `OpusDecoder` + jitter buffer + PCM 余量 + 增益包络；解码缓冲 120ms。
- tsclient-rs 丢弃 seq，只能按到达时间做 60ms 固定目标延迟；队列 >200ms/12 帧丢最旧；
  缺包最多 3 帧 PLC；500ms 无包淡出并移除。
- 10ms 混音；软削波三段曲线（≤0.5 线性，以上 tanh）；deafen 清空并静音。

### mute / deafen / PTT

- 进频道自动收发；mute 停发送；deafen 停发送并静音播放；PTT 模式下按下才发送。
- 不在频道（`channel_id == 0`）不采集；离开频道停采集。
- 设备失败只发 `Voice` 事件，连接保持。

### 频道 codec

TS3 的 codec 是频道属性，不是客户端全局配置。actor 在快照/移动时读取
`channellist -flags -codec` 或 `channelinfo cid=...` 的 `channel_codec`：

- 4 → 单声道 `Application::Voip`，64kbps；
- 5 → 立体声 `Application::Audio`，128kbps；
- 其他 → 停采集并提示不支持。

Opus 不能中途换声道数，切 codec 时 capture 线程重建 encoder。

### 事件

- `Voice { muted, deafened, ptt_mode, ptt_active, input_ready, output_ready, message? }`
- `Speaking { client_ids }`：远端活跃说话人集合变化。
- `SelfSpeaking { speaking }`：本端 VAD/PTT 是否在发送。
- 音频帧不跨 FFI。

## 频道与成员持续同步

- 连接成功后 actor 先尝试 `channelsubscribeall`，再拉 `channellist`、`clientlist`、
  `channellist -flags -codec`，发 `Snapshot`；订阅或标志读取失败只降级，不中止连接；
- 服务端拒绝显式 `channellist` / `clientlist` 时，actor 使用 `tsclient-rs` 从欢迎包
  和通知维护的 `directory_snapshot()`；频道顺序、主题、密码标记、人数上限与 codec
  优先来自当前返回行，缺失时由该快照补齐；
- 连接期间每 30 秒轮询一次，只有内容变化时才发快照；
- 成员事件继续即时推送，Dart 用快照兜底；
- 自己的频道以 `ClientMoved` 事件为准，收到后查 codec 并同步给音频层。

轮询和命令共用 actor 串行队列，不会与建连/发送并发；命令限流 4 token/s，30s 两次查询
远低于阈值。

## 断线重连

```text
Connected ──非主动断开──> Reconnecting{attempt, delay}
    ▲                         │
    └──── 连接成功 ───────────┘
```

- 只有“曾经连上、且不是用户主动 disconnect”的断开才重连；
- 退避序列 1、2、4、15、30、60、120、300s；
- 首轮成功会话前最多 5 次；成功连上过之后不限次，避免长时间挂着被踢下线；
- 每次用户 connect/disconnect 递增 generation，延迟任务只在 generation 匹配时生效；
- 重连成功重新拉快照、重开语音，但不自动回原频道；Dart 保存 `lastChannelId`，UI 提供
  “回到上次频道”按钮；
- 连续 3 次握手超时触发身份等级提升，升级完成后从 1s 重新退避。

## 身份等级提升

- 连续 3 次 `wait_connected` 超时后，读取当前身份等级，目标 `current + 5`，上限 29。
- 挖矿在独立 OS 线程的 current-thread runtime 上跑，不阻塞 actor；`AbortSignal` 支持 UI
  取消。
- 写身份文件用临时文件 + `sync_all` + rename；Windows 上 rename 不覆盖时退化为先删后改。
- 事件：`IdentityUpgrade { from, to }`、`IdentityUpgraded { level }`；失败发 `Failed`。
- 结果带 generation，用户已经手动重连/断开时旧结果直接丢弃。

## 文本消息

- 发送统一走 `tsclient_rs::sendTextMessage`：`target_mode=1` 私聊、`2` 频道、`3` 服务器；
  频道消息的 `target` 是频道 id，服务器广播是 0。
- ServerQuery 单行上限 8192 字节。actor 在发送前按 UTF-8 字符边界分片，优先在空白处断开；
  分片之间不保证原子性，网络中断时可能只发出前几片。
- 接收侧只注册一个 `on_text_message` 处理器，转成 `TextMessageView` 后进 actor 的事件队列；
  `TextMessageView.from_id` 保留发送者客户端 id，私聊回复需要它。
- TS6 图片是 `{"msg_type":"ts.file.myts",...}` JSON，不是 URL；官方客户端从 myTS 附件
  服务下载。FlSpeak 不携带 myTS token，官方附件只显示“不支持的图片格式”占位。
- 第三方 URL 图片走 `core/session/src/images.rs` + FFI `fetchImage(url)`：校验 http/https、
  `proto::forbidden_host`、DNS 公网地址、重定向/大小/content-type/magic；图片字节不过音频链路。
  见 `images.md`。
- `core/session/examples/live_probe.rs` 是最小端到端探针：连接、保持在线、打印原文。
- Dart 侧 `MessageContent` 做 TS6 Markdown 渲染：粗体/斜体/删除线/下划线/高亮/行内代码/
  链接样式/标题/引用/列表/表格/折叠块/对齐块/少量 emoji；显式图片 URL 渲染为图片。
  未支持脚注、数学排版、链接点击。

## 消息历史

- 存储：`<store>/messages.jsonl`，一行一条，字段包含 server_id、unix 毫秒、发送者、投递范围。
- 写入：actor 收到文本消息后追加一行；写失败发 `Failed`，不阻塞消息广播。
- 回放：连接成功后按 server_id 读出最近 500 条，发 `History` 事件；Dart 用带时间戳的消息
  替换当前列表。
- 体积：启动时压缩一次（按服务器保留最近 500 条）；运行期只追加。
- 隐私：本地明文，和 `servers.json`、`identity.txt` 同级。清除历史入口留待后续。

## 文件传输

- 初始化（`ftinitupload` / `ftinitdownload`）在 actor 里；数据连接是独立 TCP 流，初始化后
  交给 local task 执行，避免大文件堵住命令队列。
- 主机只允许会话主机：`proto::check_transfer_host`，Dart 不能传主机名；端口用服务器下发值。
- TCP 先发送服务器下发的原始 `ftkey`，随后收发明文字节；下载严格校验声明的 `size`，不填充或截断文件。
- 频道图标使用频道 0 的 `/icon_<无符号 CRC-32 ID>` 文件。`SessionHandle::fetch_icon` 只返回图标字节，限制为 1 MiB、20 秒；协商在 actor 中串行执行，TCP 任务独立运行，连接代次变化后丢弃旧结果。
- 事件：`TransferStarted`、`TransferProgress`（256KiB/200ms 节流）、`TransferFinished`。
- UI 文件选择器/传输列表留待后续。

## FFI 增量

```text
setMuted(bool) / setDeafened(bool)
setPttMode(bool) / setPttActive(bool)
cancelIdentityUpgrade()
listAudioDevices() -> AudioDevices
setAudioDevices(inputId?, outputId?)
requestSnapshot()
setAutoReconnect(bool)
fetchImage(url) -> bytes
uploadFile(localPath, remotePath, channelId, password?, overwrite) -> transferId
downloadFile(remotePath, localPath, channelId, password?) -> transferId
```

事件增量：`Snapshot`、`History`、`Voice`、`Speaking`、`SelfSpeaking`、
`IdentityUpgrade`、`IdentityUpgraded`、`Transfer*`、`Reconnecting` 状态。

## 失败语义

- 音频设备失败：`Voice` 带错误 + 连接保持。
- 轮询失败：发 `Log`，不清空现有快照；下一次继续。
- 重连失败：退避耗尽后 `State(Disconnected)` + `Failed`。
- 历史写失败：`Failed`，消息仍然广播。
- 文件传输失败：`TransferFinished{error}`，不影响会话。
- 身份提升失败：`Failed`，继续按正常退避重连；用户可取消。

## 真实验证

连接链路有一个显式开关的集成测试，默认不跑：

```sh
cd plugins/flspeak_ffi/rust
FLSPEAK_TEST_SERVER=ts.example.com \
FLSPEAK_TEST_NICKNAME=flspeak-probe \
cargo test -p session --test live_connect -- --ignored --nocapture
```

它用 `SessionOptions { audio: false }` 关闭音频，验证地址录入、档案连接、握手、状态、
频道/成员查询与断开；服务器对访客关闭 `channellist` 时，列表错误只打印不判失败。

连接前 `proto::resolve_target` 会查标准 DNS 的 `_ts3._udp.<domain>` SRV；最终目标
由 `proto::client` 检查一次，DNS 失败回退档案字面地址。tsclient-rs 走 UDP 9987，
TSDNS 尚未实现。
