# Agent Note: 跨平台结构化日志

Status: implemented

## Problem

Flutter 与 Rust 的诊断信息此前各走各的通道：Rust 的 `EventLogger` 只把消息塞进`SessionEvent::Log`，Dart 侧用 `debugPrint` 打印，设置页也没有一个稳定路径能让用户找到这些输出。排查连接、音频与屏幕共享问题时，日志既没有持久化，也没有统一的时间与字段格式。

## Decision

日志目录固定为 `<应用支持目录>/logs`，与 `preferences.json`、`settings.json` 和身份文件同级。`lib/core/logging/logger.dart` 的 `logDirectoryFor` 从 `storePath` 推导这个路径，启动时同时交给 Dart Talker 与 Rust tracing。目录选择与既有的档案持久化保持一致，不使用 documents 目录。

Rust 侧由 `core/session::logging::init` 安装全局订阅器，`plugins/flspeak_ffi` 的`api/session.rs` 只把 `init_logging` 与 `shutdown_logging` 转发给 core。初始化用互斥锁串行化；`WorkerGuard` 只在 `try_init` 成功后保存，失败时随局部变量释放，重试不会留下与订阅器不匹配的 guard。写入使用 `tracing-appender` 的 non-blocking worker，`lossy(true)` 保证队列满时丢弃日志而不是阻塞采集或会话线程。每日按 UTC 轮转，文件名为 `rust.YYYY-MM-DD.log`；`max_log_files` 只作为 Rust 单独运行时的数量上限。

Dart 侧由 `JsonLinesFileObserver` 把 Talker 事件写成 `dart.YYYY-MM-DD.log`。`onLog`只入队，异步串行落盘，错误级别立即 flush；队列有上限，溢出丢最旧记录。观察器按 UTC日期清理 `dart.*` 与 `rust.*` 两类文件，保留最近七天；Rust worker 正占用的文件删除失败时留到下次清理。

两边使用同一套 NDJSON 记录：`timestamp` 是带 `Z` 的 UTC RFC3339，`level` 是大写，`message`、`target` 在顶层，结构化字段扁平化到顶层，异常写 `error`，堆栈写 `stack`。Rust 通过 `flatten_event(true)` 与 `ChronoUtc` 生成这个布局；Dart 在写入前把`StructuredTalkerLog.fields` 合并到顶层。debug 构建保留 `DEBUG`，release 过滤到`INFO`。

启动阶段任何一步失败都不阻止应用：`initLoggingPipeline` 返回 `LoggingSetup.error`，`main` 继续启动，`TsClientApp` 首帧通过 `NoticeCenter` 提示一次。Rust 文件日志不可用时Dart 仍写自己的文件；目录不可用时退回纯控制台 Talker。正常退出由`shutdownLoggingPipeline` 先 flush 观察器，再释放 Rust worker；移动端 `detached` 只做尽力而为。

现有诊断进入这条管道：`EventLogger` 在广播 `SessionEvent::Log` 的同时发出 `tracing`事件；Dart 的 `debugPrint` 调用点改用 `logDebug`、`logWarn`、`logError`，由统一 helper附加 target 与结构化字段。`CoreEvent_Log` 的处理保留 `debugPrint`，它属于调试面板输出，再写一份到 Dart 文件会与 Rust 文件重复。

## Alternatives considered

**使用 documents 目录。** documents 在 iOS 与 Android 上更接近用户可见区域，但与`resolveStorePath` 的既有位置分叉，设置页还要维护两个根路径；应用支持目录与档案、身份文件同级，备份与清理策略更一致。

**新建 `core/logging` crate。** 职责边界更纯，但日志订阅器只被 FFI 与会话使用，新增crate 会把 `tracing-subscriber` 的依赖图再拆一层；放进 `core/session` 已满足「持久化留在 core、FFI 只转发」的约束。

**保持 `lossy(false)`。** 不丢日志，但磁盘抖动时 `send` 会阻塞，音频采集线程与会话actor 都可能被日志拖住。日志是诊断设施，丢记录比卡住实时链路代价低。

**只靠 Rust 的 `max_log_files` 保留。** 它按文件数量而不是日期限制，日志稀疏时超过七天的文件仍会留下；Dart 观察器统一扫描两类文件才能兑现七天保留。

**覆盖全局 `debugPrint`。** 一行就能收集所有 Flutter 诊断，但会把框架自身的噪声也写进应用日志；逐点迁移能保留 target 与级别语义。

**日志初始化失败时 FAILFAST。** 与仓库的 FAILFAST 原则一致，但聊天客户端不应因为日志目录不可写而完全打不开；这里选择显式降级并提示，失败原因仍然可见。

## Consequences

- 日志目录在移动端仍位于应用沙箱内，用户只能通过设置页复制路径或在桌面文件管理器中打开；这不是用户可以随手浏览的位置。
- `lossy(true)` 在突发日志或磁盘缓慢时会丢记录；需要完整审计时应降低日志级别而不是改回阻塞写入。
- Dart 异步写入在进程被强杀时仍可能丢最后几条；`shutdownLoggingPipeline` 只覆盖正常退出。
- release 构建不写 `DEBUG`，因此 `log_debug!` 与 `logDebug` 只在 debug 构建的日志文件中出现。
- NDJSON 没有版本字段；以后增加必需字段需要同时更新两端的 schema 测试。
