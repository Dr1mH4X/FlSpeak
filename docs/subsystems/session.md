# 子系统契约 — core/session

本文定义 `core/session` 的职责、关键调用序列与不变量。

## 职责

- 独占管理 `tsclient-rs::Client` 实例，作为客户端协议栈与并发调度的唯一所有者。
- 采用 Actor 模型串行执行所有协议调用，彻底规避底库内部跨 await 持锁的死锁风险。
- 管理会话状态机（`Disconnected`, `Connecting`, `Connected`, `Reconnecting`）、频道快照轮询及断线重连。
- 维护本地身份标识、服务器历史消息持久化（上限 500 条）及应用配置管理 `SettingsManager`。
- 管理全局 `tracing` 订阅器与每日按 UTC 轮转的文件 worker（`rust.YYYY-MM-DD.log`）。
- 处理第三方聊天图片安全抓取校验及图床上传逻辑。

## 关键路径与序列

1. **会话创建与 Actor 启动**：
   通过 `SessionHandle::spawn` 启动独立单线程 Tokio Runtime 与 `LocalSet`，拉起专属 Actor 任务并返回句柄。
2. **命令投递与串行调度**：
   外部调用（FFI/音频）将命令封装为 `Command` 投递至 MPSC 信道 → Actor 主循环依序取出并同步调用底库 `Client` → 结果通过 oneshot 信道回复。
3. **语音包旁路调度**：
   音频线程编码完成的 Opus 语音包送回 Actor 信道 → Actor 调用 `Client::send_voice` 串行发往网络。
4. **事件派发与降采样**：
   底库事件回调统一推入广播信道 `broadcast::Sender<CoreEvent>`（容量 256）派发给 UI；快照定时器周期性触发全量结构同步。
5. **按需网络遥测**：
   UI 在遥测面板可见期间发送 `SampleNetwork` → Actor 在后台任务里调用 `getconnectioninfo clid=<self>` → 原始 `notifyconnectioninfo` 回到 Actor 后合并 ping、双向丢包与 idle 到 `NetworkMonitor`；面板关闭后停止采样。目录请求的探测延迟继续作为质量评估与字段缺失时的兜底。服务器查询本端连接信息时，Actor 用已知的探测延迟回答 `setconnectioninfo`。
6. **日志管道初始化与生命周期**：
   外部通过 `core/session::logging::init` 注入日志目录 → 互斥锁串行化防重入 → 启动 non-blocking worker 并安装 `tracing` 全局订阅器 → 成功后保留 `WorkerGuard`；应用退出时通过 `core/session::logging::shutdown` 释放 worker。

## 不变量

- `tsclient-rs::Client` 的所有权永远只归属于当前 Session Actor 内部，外部代码严禁直接持有引用或跨线程调用。
- 任何 UI 命令与状态变更必须经过 Actor 命令队列排队串行处理，不允许并发访问底库协议对象。
- 原始音频采集与播放帧不进入 Actor 事件通道，仅 Opus 编码压缩后的包通过专有通道由 Actor 调度。
- 日志文件 worker 必须启用 `lossy(true)` 非阻塞队列，在背压或写盘抖动时丢弃日志，严禁阻塞会话 Actor 或实时音频线程；重复初始化具备幂等保护。

## 相关决策

- [跨平台结构化日志](../../.agents/notes/implemented/architecture/2026-11-07-cross-platform-logging.md)
- [网络遥测卡片延伸与连接统计](../../.agents/notes/implemented/feature/2026-11-07-network-telemetry-card.md)
