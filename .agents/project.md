# 项目结构

```text
FlSpeak/
├── Cargo.toml                      # Rust workspace（核心 crate 都在这里）
├── core/
│   ├── policy/                     # 合规策略：禁连清单 + T1/T2 校验（唯一事实来源）
│   ├── proto/                      # tsclient-rs 的窄封装：deny-all 解析器 + 建连
│   ├── session/                    # 会话 actor：Client 的所有权与并发边界
│   └── audio/                      # 采集/播放/Opus（默认不编进产物，见 docs/audio.md）
├── plugins/flspeak_ffi/            # 唯一 FFI 包（flutter_rust_bridge + native assets）
│   ├── rust/                       # cdylib：api/ 是 frb 唯一解析的模块
│   ├── hook/build.dart             # native assets 钩子：cargo 编译并注册 code asset
│   └── lib/                        # 生成 + 手写的 Dart 入口
├── lib/                            # Flutter 应用：UI 与状态收敛
├── arb/                            # 中英文案
├── tool/                           # 合规闸门、提交信息闸门、版本注入
├── .agents/                        # 人机协作约定与决策记录
└── .github/workflows/              # ci.yml / release.yml
```

## 不变量

- **策略层是合规的唯一出口**。`Client::new` 只接受策略层批准的 `host:port`，且强制注入
  deny-all 的 `AddrResolver`，因此 SRV / TSDNS / 昵称解析路径在结构上不可达。
- **连接目标只能来自档案**。连接命令只收档案 id，不收地址；地址在录入时就通过 T1 校验，
  录入后成为 T2 档案。
- **文件传输主机必须等于会话主机**（`proto::check_transfer_host`）。
- **actor 独占 `Client`**。tsclient-rs 在建连路径上跨 `.await` 持 `std::sync::Mutex`，
  这些 future 不是 `Send`；actor 因此跑在独占线程的 current-thread runtime + `LocalSet` 上。
- **每类事件只注册一个处理器**。tsclient-rs 为每个处理器、每个包 spawn 一个任务。
- **音频不跨 FFI**。Dart 只能通过单一 `Stream<CoreEvent>` 拿 UI 事件。
- **身份私钥不出 Rust**。`identity.txt` 由 Rust 读写，Dart 只传 store 目录。

## 与 tsclient-rs 的关系

依赖 crates.io 上的 `tsclient-rs = "0.1.5"`。上游是 teamspeak-js 的结构化移植，公共 API
刻意与 JS 对齐，**不要把本项目的策略逻辑推回上游**。只有中性的、纯增量的改动才值得提 PR
（候选见 `docs/compliance.md` 末尾）。本地要改上游时用根 `Cargo.toml` 里的
`[patch.crates-io]`，用完删掉，不要提交（CI 上没有那个路径）。