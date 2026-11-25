# 后端核心链路与生命周期

本文定义后端（Rust `core/`）在会话调度、状态同步、断线重连、身份升级、消息历史、网络遥测与开放身份互认上的端到端运行时契约与并发边界。语音链路见[音频](audio.md)，聊天图片见[聊天图片与 TS6 富文本](images.md)，频道文件与权限见[频道访问、权限组与文件](channels.md)，版本更新检查见[架构](architecture.md#版本更新检查)。

## Actor 与所有权

- `SessionHandle::spawn` 启动独立的单线程 Tokio runtime 与 `LocalSet`，拉起专属 Actor 任务并返回句柄；`tsclient-rs::Client` 的所有权只在该 Actor 内。
- 外部调用（FFI 与音频线程）把命令封装成 `Command` 投递到 MPSC 信道，Actor 主循环依序取出并同步调用底库 `Client`，结果经 oneshot 回复；涉及 `Client` 与协议对象的 UI 命令都走这条队列，不并发访问底库协议对象。
- 底库事件回调统一推入 `broadcast::Sender`（容量 256）派发给 UI；订阅慢时旧事件被丢弃，订阅者收到 `Lagged` 后继续。快照定时器周期触发全量结构同步。
- 原始音频帧不进入这条事件通道，只有 Opus 编码后的包经专有通道由 Actor 调度。
- 会话状态机为 `Disconnected` / `Connecting` / `Connected` / `Reconnecting`。
- `core/session::logging` 独占全局 `tracing` 订阅器与文件 worker：初始化幂等，队列 `lossy(true)` 保证背压时丢日志而不阻塞会话或实时音频线程，`WorkerGuard` 随停机释放。

## Actor 子状态与生命周期

Actor 内部按子域把状态封装在各子模块的私有结构体里，只经窄方法读写：`actor::connect::ReconnectState`、`actor::directory::DirectoryState`、`actor::streams::StreamCoordinatorState`、`actor::transfers::MediaTransferState`。

- 断线与切频道的清理统一收口到各子状态的 `reset_on_disconnect()`；`DirectoryState` 与 `StreamCoordinatorState` 另提供 `reset_on_channel_change()`。
- 断线、主动断开与新连接代次递增都要把旧子状态归零，迟到的回调不参与新会话的状态推导。
- 跨 FFI 的提示只传稳定 notice code：`VoiceStateView.message` 与 `SessionEvent::{Denied, Failed}` 携带 `voice.*` / `session.*` 代码，Dart 负责映射本地化文案，详细诊断写后端日志。

## 频道与成员持续同步

- 连接成功后 Actor 依次提交 `channelsubscribeall`、`channellist`、`clientlist` 与 `channellist -flags -codec`，广播 `Snapshot` 事件；订阅或标志读取失败执行优雅降级，不中断连接。
- 服务端拒绝显式列表查询时，Actor 回退使用 `tsclient-rs` 根据欢迎包与通知维护的 `directory_snapshot()`；频道顺序、主题、密码标记、人数上限与 codec 优先来自返回行，缺失时由快照补齐。
- 连接存活期间每 30 秒执行一次轮询，仅在结构内容变化时广播快照；成员变动事件保持实时增量派发，Dart 侧使用快照兜底。
- 自己的当前频道以 `ClientMoved` 事件为准，收到后查询目标频道 codec 并同步至音频子系统。
- 轮询与常规业务命令共享 Actor 串行队列，严格遵守命令限流阈值，不与建连并发。

## 断线重连与代次控制

```text
Connected ──非主动断开──> Reconnecting{attempt, delay}
    ▲                         │
    └──── 连接成功 ───────────┘
```

- 仅在非用户主动断开且此前处于连接状态的异常断线时触发自动重连。
- 退避间隔序列为 1s、2s、4s、15s、30s、60s、120s、300s；首轮会话成功前最多尝试 5 次，成功建立过会话后不限重试次数。
- 每次用户手动触发连接或断开时递增代次（generation），重连定时任务仅在代次匹配时生效，避免历史重连任务干扰新会话。
- 重连成功后重新拉取全量快照并重启语音通道；客户端保存 `lastChannelId` 并由 UI 提供快捷切回原频道操作。
- 连续 3 次建连握手超时将触发身份等级提升，升级完成后重置重连退避至 1s。

## 身份等级提升

- 连续 3 次 `wait_connected` 超时后，读取当前身份等级，计算目标等级为 `current + 5`（上限 29 级）。
- 身份挖矿在独立操作系统线程的单线程 Tokio 运行时上执行，不阻塞 Actor；支持外部通过 `AbortSignal` 取消。
- 身份、服务器档案与历史压缩结果采用同目录独占临时文件、`sync_all` 刷新与原子 rename 替换；替换失败时保留目标原文件并清理临时文件；Unix 下新文件权限严格限制为 `0600`。
- 提升进度通过 `IdentityUpgrade` 与 `IdentityUpgraded` 事件通知外部；失败时派发 `Failed` 并回退至常规重试。

## 文本消息与消息历史

- 文本消息发送由 Actor 通过 `Client::exec_command` 提交转义后的 `sendtextmessage` 并等待服务器确认（5 秒超时）：`target_mode=1` 为私聊、`2` 为频道、`3` 为服务器广播。Dart 仅在确认成功后清空草稿。
- ServerQuery 单行存在 8192 字节上限。Actor 在发送前按 UTF-8 字符边界执行分片，优先在空白处断开。
- 戳一下交互通过 Actor 串行调用 `tsclient_rs::poke`，接收侧统一注册 `on_poked` 监听并核对连接代次转换为 UI 通知；戳一下交互不落盘写入聊天历史。
- 接收侧统一注册单一 `on_text_message` 处理器，构造 `TextMessageView` 后推入事件队列；私聊记录以发送者 UID 为持久索引键。
- 消息持久化至 `<store>/messages.jsonl`，一行一条 NDJSON 记录；启动时自动压缩保留每个服务器最近 500 条记录；写入失败派发 `Failed` 事件，不阻塞前台广播。

## 按需网络遥测

- UI 在遥测面板可见期间发送 `SampleNetwork`；Actor 在命令循环里串行发送 `getconnectioninfo clid=<self>`（只等写入，不等回包），原始 `notifyconnectioninfo` 回到 Actor 后合并 ping、双向丢包与 idle 到 `NetworkMonitor`。面板关闭后停止采样。
- 协议 ping 是延迟的权威值，目录探测延迟用于失败率、抖动兜底与协议字段缺失时的延迟。
- 服务器查询本端连接信息时，Actor 用已知协议 ping（缺失时用探测延迟）回答 `setconnectioninfo`，并合并短时间内的重复请求。

## 开放身份互认与斜杠命令

- 由 Actor 内嵌的 `tsclient_rs::open_protocol::OpenProtocolEngine` 驱动，出站指令经 Actor 同线程 `spawn_local` 异步派发并回传结果信号，避免阻塞命令循环。
- 连接就绪或本端切换频道时（含首次快照补齐 `channel_id`），引擎按 2 秒防抖与尾随/单次重试规则在当前频道广播 `tsclient:identity`（`action="announce"`），并在建连首次就绪时向全服发送 1 次带 `noreply: true` 的单向公告。
- 人数不超过阈值的服务器启用低速跨频道单播探测队列：每 900ms 最多探测 1 名尚未识别成员，收到对端 `announce` 自动从队列剔除，遇到服务端 `524` 防洪错误立即熔断清空队列。
- 打开未识别节点的私信窗口时，UI 投递 `QueryPeerIdentity`，经发起侧冷却后发送单播 `query`。
- 收到对端 `announce`、`query` 或 `announce_ack` 后，引擎清洗截断字段并写入对端缓存；非 `noreply` 公告与显式 `query` 按 `(peer, action)` 冷却与全局令牌桶限流，校验完整 TS3 转义线缆命令 `< 1024` 字节后单播回执 `announce_ack`。
- 对声明 `"chat:slash_commands"` 的私信对象或同频道机器人，UI 投递 `FetchBotCommands`，引擎经带 TTL 的在途防重集合发送 `list_req`，收到 `list_ack` 后提取命令清单与可选 `command_prefix` 合并至 `ClientView`（含 `bot_command_prefix`）并推送 `CoreEvent::Snapshot`。

## 不变量

- `tsclient-rs::Client` 的所有权永远只归属于当前 Session Actor，外部代码不持有引用，也不跨线程调用。
- 涉及 `Client` 与协议对象的 UI 命令必须经过 Actor 命令队列排队串行处理。
- 原始音频采集与播放帧不进入 Actor 事件通道，仅 Opus 编码压缩后的包通过专有通道由 Actor 调度。
- 日志文件 worker 必须启用 `lossy(true)` 非阻塞队列；重复初始化具备幂等保护。
- 版本更新检查是旁路：全局异步锁保证同一时刻只跑一个检查，不占用 Actor 命令队列，也不访问 `Client`；失败不得覆盖上次成功缓存。
- 会话 Actor 维持单一 `current-thread` runtime 与 `LocalSet` 串行调度，子域状态只经窄方法与 `reset_on_disconnect()` / `reset_on_channel_change()` 收口。

## 相关决策

- [会话 Actor 调度与 tsclient-rs 所有权](../.agents/notes/implemented/architecture/2026-10-08-session-actor.md)
- [跨平台结构化日志](../.agents/notes/implemented/architecture/2026-11-07-cross-platform-logging.md)
- [网络遥测卡片延伸与连接统计](../.agents/notes/implemented/feature/2026-11-07-network-telemetry-card.md)
- [PluginCommand 开放身份互认与 Bot 斜杠命令协议](../.agents/notes/implemented/feature/2026-11-12-open-identity-and-bot-slash-commands.md)
- [自头像离线快照](../.agents/notes/implemented/feature/2026-11-22-identity-avatar-snapshot.md)
