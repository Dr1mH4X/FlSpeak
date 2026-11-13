# 项目结构与模块职责

| 模块 | 类型 | 职责边界 |
| :--- | :--- | :--- |
| `core/server/` | Rust crate | 服务器档案模型、地址格式化与自托管端点解析校验 |
| `core/proto/` | Rust crate | SRV 记录解析、连接目标白名单检查、官方主机黑名单过滤与协议安全边界 |
| `core/session/` | Rust crate | 会话 Actor 调度、独占驱动 `tsclient-rs` 的 `Client` 实例、事件分发总线与状态机生命周期 |
| `core/audio/` | Rust crate | 独占双线程全双工音频管线（设备枚举、采集、播放、Opus 编解码、VAD 语音检测与 JitterBuffer） |
| `plugins/flspeak_ffi/` | Flutter plugin | 唯一的跨语言 FFI 桥梁（flutter_rust_bridge 绑定层与 Native Assets 编译集成） |
| `plugins/prism_ui/` | Git 子模块 | Flutter UI 原语与设计系统组件库（经 [lib/widgets/prism.dart](../lib/widgets/prism.dart) 桥接导出，界面层优先复用） |
| `lib/` | Flutter App | 客户端 UI 组件、Riverpod 状态持有与响应式渲染 |
| `arb/` | L10n 资源 | 应用国际化多语言 ARB 词条源文件 |
| `.agents/` | 规范与上下文 | 面向编码 Agent 的架构决策记录（notes/）与专属复用工作流技能（skills/） |
| `.github/` | CI/CD | GitHub Actions 工作流（静态检查、构建打包与发布流水线）与 PR 模板 |

## 不变量

- **自托管边界只有一个最终检查**。`server::parse_address` 只接受 IP/域名/`localhost`，拒绝裸昵称；`proto::client` 在建连前检查一次官方主机清单。SRV 由 `core/proto` 用标准 DNS 解析，协议库仍然注入 deny-all 的 `AddrResolver`，tsclient-rs 自带的 discovery 不可达。
- **连接目标只能来自档案**。连接命令只收档案 id，不收地址；档案由用户录入的 IP/域名生成。
- **文件传输主机必须等于会话主机**（`proto::check_transfer_host`）。
- **actor 独占 `Client`**。tsclient-rs 在建连路径上跨 `.await` 持 `std::sync::Mutex`，这些 future 不是 `Send`；actor 因此跑在独占线程的 current-thread runtime + `LocalSet` 上。
- **每类事件只注册一个处理器**。tsclient-rs 为每个处理器、每个包 spawn 一个任务。
- **音频不跨 FFI**。Dart 只能通过单一 `Stream<CoreEvent>` 拿 UI 事件；capture/playback 各自独占 cpal 流，cpal 回调零分配零锁。
- **身份私钥不出 Rust**。`identity.json` 由 Rust 读写，Dart 只传 store 目录。

## 与 tsclient-rs 的关系

依赖 crates.io 上 `Cargo.toml` 的 `tsclient-rs`。上游是 teamspeak-js 的结构化移植，公共 API 刻意与 JS 对齐，**不要把本项目的连接边界逻辑推回上游**。只有中性的、纯增量的改动才值得提 PR（候选见 `.agents/notes/implemented/architecture/2026-10-18-full-duplex-audio.md`）。本地调试方式见 [开发流程](../docs/development.md#本地改上游-tsclient-rs)。
