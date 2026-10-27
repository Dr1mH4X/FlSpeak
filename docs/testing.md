# 测试约定

## 单测摆放

Rust 单测与实现同文件，为 `#[cfg(test)] mod tests { use super::*; }` 块，同 Rust 惯例：紧贴被测代码，可访问私有项。测试名称用描述性的英文 snake_case。

- 同步测试用 `#[test]`，异步测试用 `#[tokio::test]`
- 断言只用 `assert!` / `assert_eq!`
- 不依赖网络与真实服务器；需要官方域名做测试夹具时，从 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES` 拼，不要写字面量

Dart 单测与被测文件同目录，命名 `<被测文件>_test.dart`（`lib/core/channel_display.dart` 对 `lib/core/channel_display_test.dart`）。`flutter test` 默认只扫 `test/`，所以路径显式指到 `lib`：`just test` 就是 `flutter test lib`。

`lib/` 下的用例文件顶部要写 `// ignore_for_file: depend_on_referenced_packages`：`flutter_test` 是 dev 依赖，而 analyzer 无法从代码看出这些文件不被应用入口引用。

## 测试范围选择

提交改动时按「变更面」选最小测试集，不默认全量运行：改动所在 crate 及其直接依赖跑通即可，只改文档/配置时不重跑整套测试。定向示例（从 `plugins/flspeak_ffi/rust` 跑）：

```sh
cargo test -p server -p proto
```

按需全量验证或交给 CI：本地全量门禁是 `just check`，CI 各作业见 [ci-cd.md](ci-cd.md)。

## 真实服务器测试（手动，不走 CI）

`core/session/tests/live_connect.rs` 默认 `#[ignore]`，只在显式指定时运行；它关闭音频，
不会申请麦克风/扬声器权限：

```sh
cd plugins/flspeak_ffi/rust
FLSPEAK_TEST_SERVER=ts.example.com \
FLSPEAK_TEST_NICKNAME=flspeak-probe \
cargo test -p session --test live_connect -- --ignored --nocapture
```

注意：tsclient-rs 走 UDP 9987。`proto::resolve_target` 会先查标准 DNS 的
`_ts3._udp.<domain>` SRV；最终目标由 `proto::client` 检查一次，DNS 查询失败时回退到档案字面地址。
TSDNS 尚未实现。服务器对访客关闭 `channellist` 时，测试只验证连接与状态，列表调用
会打印权限拒绝而不判失败。

### 最小消息探针（后台等消息）

`core/session/examples/live_probe.rs` 会保持在线，把收到的文本消息**原文**写到 stdout 和
`/tmp/flspeak-probe.log`，用于抓 TS6 图片消息的 BBCode/URL 格式：

```sh
cd plugins/flspeak_ffi/rust
FLSPEAK_TEST_SERVER=example.com \
FLSPEAK_TEST_NICKNAME=flspeak-probe \
FLSPEAK_PROBE_SECONDS=1800 \
cargo run -p session --example live_probe
```

访客身份可能没有服务器广播权限（`insufficient client permissions`）；连接、收消息不受影响。
停止用 Ctrl-C，或把 `FLSPEAK_PROBE_SECONDS` 设小。

## CI 测试门

本地提交前的聚合门禁是 `just check`。CI 的 `rust` 作业运行 `cargo fmt --check`、
`cargo clippy -D warnings` 与 `cargo test --all-features`，`dart` 作业覆盖格式与分析，
`dart-test` 作业覆盖单测、插件分析与 FFI 生成物一致性，见 [ci-cd.md](ci-cd.md)。
测试用例本身不写入本文档。
