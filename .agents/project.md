# 项目结构

```text
FlSpeak/
├── Cargo.toml                      # Rust workspace（核心 crate 都在这里）
├── core/
│   ├── server/                     # 服务器档案、地址解析与本地登记
│   ├── proto/                      # SRV、最终连接边界、deny-all 解析器与建连
│   ├── session/                    # 会话 actor：Client 的所有权与并发边界
│   └── audio/                      # 双线程语音：采集/播放/Opus/VAD/jitter（见 docs/audio.md）
├── plugins/flspeak_ffi/            # 唯一 FFI 包（flutter_rust_bridge + native assets）
│   ├── rust/                       # cdylib：api/ 是 frb 唯一解析的模块
│   ├── hook/build.dart             # native assets 钩子：cargo 编译并注册 code asset
│   └── lib/                        # 生成 + 手写的 Dart 入口
├── lib/                            # Flutter 应用：UI 与状态收敛
├── arb/                            # 中英文案
├── .agents/                        # 人机协作约定与决策记录
└── .github/workflows/              # checks.yml / ci.yml / release.yml
```

## 不变量

- **自托管边界只有一个最终检查**。`server::parse_address` 只接受 IP/域名/`localhost`，拒绝裸昵称；
  `proto::client` 在建连前检查一次官方主机清单。SRV 由 `core/proto` 用标准 DNS 解析，
  协议库仍然注入 deny-all 的 `AddrResolver`，tsclient-rs 自带的 discovery 不可达。
- **连接目标只能来自档案**。连接命令只收档案 id，不收地址；档案由用户录入的 IP/域名生成。
- **文件传输主机必须等于会话主机**（`proto::check_transfer_host`）。
- **actor 独占 `Client`**。tsclient-rs 在建连路径上跨 `.await` 持 `std::sync::Mutex`，
  这些 future 不是 `Send`；actor 因此跑在独占线程的 current-thread runtime + `LocalSet` 上。
- **每类事件只注册一个处理器**。tsclient-rs 为每个处理器、每个包 spawn 一个任务。
- **音频不跨 FFI**。Dart 只能通过单一 `Stream<CoreEvent>` 拿 UI 事件；capture/playback
  各自独占 cpal 流，cpal 回调零分配零锁。
- **身份私钥不出 Rust**。`identity.txt` 由 Rust 读写，Dart 只传 store 目录。

## 与 tsclient-rs 的关系

依赖 crates.io 上 `Cargo.toml` 的 `tsclient-rs`。上游是 teamspeak-js 的结构化移植，公共 API
刻意与 JS 对齐，**不要把本项目的连接边界逻辑推回上游**。只有中性的、纯增量的改动才值得提 PR
（候选见 `.agents/notes/implemented/architecture/2026-10-18-full-duplex-audio.md`）。本地调试方式见 [开发流程](../docs/development.md#本地改上游-tsclient-rs)。
