# FlSpeak 开发入口。`just` 列出全部任务；各命令的平台细节见 docs/development.md。

# ── 格式化（cargo 从 plugins/flspeak_ffi/rust 跑，吃锁定工具链）──

# 格式化 Rust + Dart
[group('fmt')]
fmt:
    cd plugins/flspeak_ffi/rust && cargo fmt --all
    dart format lib setup.dart

# 只检查格式，不落盘（CI 同款）
[group('fmt')]
fmt-check:
    cd plugins/flspeak_ffi/rust && cargo fmt --all -- --check
    dart format --output=none --set-exit-if-changed lib setup.dart

# ── Rust（从 plugins/flspeak_ffi/rust 跑，吃锁定工具链）──

[group('rust')]
[working-directory: 'plugins/flspeak_ffi/rust']
rust-clippy:
    cargo clippy --workspace --all-targets --all-features -- -D warnings

[group('rust')]
[working-directory: 'plugins/flspeak_ffi/rust']
rust-test:
    cargo test --workspace --all-features

# 只跑档案/协议测试，不碰音频（Opus）依赖
[group('rust')]
[working-directory: 'plugins/flspeak_ffi/rust']
rust-test-proto:
    cargo test -p server -p proto

# 真实服务器连接测试（手动）：just live-test ts.example.com [昵称]
[group('manual')]
[working-directory: 'plugins/flspeak_ffi/rust']
live-test server nickname='flspeak-probe':
    FLSPEAK_TEST_SERVER={{server}} FLSPEAK_TEST_NICKNAME={{nickname}} cargo test -p session --test live_connect -- --ignored --nocapture

# 保持在线抓消息的探针，Ctrl-C 结束：just probe example.com [昵称] [秒数]
[group('manual')]
[working-directory: 'plugins/flspeak_ffi/rust']
probe server nickname='flspeak-probe' seconds='1800':
    FLSPEAK_TEST_SERVER={{server}} FLSPEAK_TEST_NICKNAME={{nickname}} FLSPEAK_PROBE_SECONDS={{seconds}} cargo run -p session --example live_probe

# ── FFI 绑定 ────────────────────────────────────────────────────────────────

# 改了 plugins/flspeak_ffi/rust/src/api/** 之后重跑
[group('ffi')]
[working-directory: 'plugins/flspeak_ffi']
codegen: pub-get
    flutter_rust_bridge_codegen generate

# 校验生成物与提交一致（CI plugins job 同款，需已装 flutter_rust_bridge_codegen 2.13.0）
[group('ffi')]
[working-directory: 'plugins/flspeak_ffi']
codegen-check: pub-get
    flutter_rust_bridge_codegen generate
    git diff --exit-code --stat -- .

# ── Flutter ─────────────────────────────────────────────────────────────────

[group('flutter')]
pub-get:
    flutter pub get

# 改了 arb/ 之后重新生成本地化（pub get 也会触发）
[group('flutter')]
l10n:
    flutter gen-l10n

[group('flutter')]
analyze:
    flutter analyze --no-fatal-infos

# Dart 单测（用例与实现同目录，跑 lib 而不是 test/）
[group('flutter')]
test:
    flutter test lib

[group('flutter')]
[working-directory: 'plugins/flspeak_ffi']
analyze-plugin:
    flutter analyze

# 桌面运行，按当前平台自动选设备；显式传 -d 会覆盖（flutter 取最后一个 -d）
[group('flutter')]
run *args:
    flutter run -d {{os()}} {{args}}

# ── 发版 ────────────────────────────────────────────────────────────────────

# 内置 flutter build + 归拢产物到 dist/，例：just setup macos arm64 0.2.0
[group('release')]
setup platform arch version:
    dart setup.dart {{platform}} {{arch}} --version {{version}}

# ── 聚合 ────────────────────────────────────────────────────────────────────

# 提交前全量验证（AGENTS.md「验证」一节）
check: fmt rust-clippy rust-test analyze test

# 对齐 CI 的静态检查，只读不落盘；生成物一致性另跑 just codegen-check
ci: fmt-check rust-clippy rust-test analyze analyze-plugin test

# 清理构建产物
clean:
    flutter clean
    cargo clean
