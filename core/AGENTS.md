# AGENTS.md — Rust core

这些规则补充根 [AGENTS.md](../AGENTS.md)，只覆盖 `core/`。

## 边界

- `server` 只做纯数据：服务器档案、地址格式化与语法级校验，零网络 IO、零异步运行时依赖；`ServerProfile.id` 恒等于 `join_host_port(&host, port)`，天然实现同目标去重。
- `proto` 独占标准 DNS 解析（`_ts3._udp.<domain>` SRV 与 IPv4 A 记录）与唯一的最终连接边界：官方主机清单 `FORBIDDEN_HOST_SUFFIXES` 只在这里维护，`client` 在建连前检查一次，`DenyResolver` 恒定拒绝任何解析请求。其他 crate 不复制清单，也不判断是否允许连接。
- `session` 独占 `Client`：所有协议调用都经 actor 的命令队列串行执行，FFI、Dart 或音频线程不直接调用 tsclient-rs。
- `audio` 自己采集、编码、解码和播放：音频帧不进入 FFI，实时回调里零分配、零锁、零 IO，数据交换一律走无锁环形缓冲区；编码后的包回到 actor，由 actor 调用 `send_voice`。无 `audio` feature 时纯数学与格式转换模块仍可独立编译与单测。
- 保持依赖方向：`server` 不依赖网络或协议；`proto` 依赖 `server`；`session` 依赖 `proto` 与 `audio`；FFI 只依赖 `session`。
- 版本更新检查是 `session` 的旁路，不进入 Actor 命令队列；固定主机、超时、缓存、失败回退与静默约束见 [connection-boundary.md](../docs/connection-boundary.md)。

## 模块归属

- `core/session::logging` 独占全局 `tracing` 订阅器与文件 worker，FFI 只做调用转发；队列强制 `lossy(true)` 保证非阻塞，初始化幂等。
- `core/session::media` 统一管理本地媒体磁盘缓存、第三方图片抓取与图床上传；成员头像与自头像快照的磁盘读写只经 `AvatarDiskQueue` 的单一 FIFO 阻塞线程。
- 事件广播通道容量 256，UI 滞后时丢旧事件；Actor 子状态按子域封装，生命周期与清理规则见 [backend.md](../docs/backend.md)。

## 实现约定

编码反面与错误处理见 [../docs/defensive-patterns/README.md](../docs/defensive-patterns/README.md)，测试约定见 [../docs/testing.md](../docs/testing.md)，开发流程与语言约定见 [../docs/development.md](../docs/development.md)。
