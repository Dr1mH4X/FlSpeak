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

设置 `FLSPEAK_TEST_ICON_DIR` 时，真实连接测试还会通过 actor 下载非零频道图标，并把原始图片和 `channels.json` 保存到该目录；此模式要求目标服务器至少有一个自定义频道图标。

本机 Flutter 渲染验证可显式运行 `lib/live_channel_icons_test.dart`，用 `--dart-define=FLSPEAK_LIVE_SERVER=<地址>` 与 `--dart-define=FLSPEAK_NATIVE_LIBRARY=<本机动态库绝对路径>` 指定目标。该测试关闭音频，用真实 actor、FFI、Provider 和 Flutter 图片解码链路；未设置这两个值时默认跳过。可另设 `FLSPEAK_CAPTURE_DIR` 保存界面截图。

`lib/live_messaging_test.dart` 使用同样的两个 `--dart-define` 参数，建立两个临时测试身份，验证私聊选择与回复、戳一下双向通知、历史保存和离线目标拒绝；只向这两个测试身份发送消息。未配置目标与动态库时默认跳过，不进入 CI 的真实网络测试。仅设置动态库路径时，可独立运行其中的本机 HTTP PUT 图床夹具，无需真实服务器。

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

## 受控频道、权限与文件测试

`session` 的 `live_channel_files_and_permissions` 默认忽略，通过 `FLSPEAK_CONTROLLED_FIXTURE` 指向仅本机保存的 JSON 夹具。夹具包含 `server`、`channel_id`、`channel_group_id`、`server_group_id` 与临时频道 `password`；所有对象由测试管理员预先创建，不使用现有用户或业务频道。

在 `plugins/flspeak_ffi/rust` 执行 `cargo test -p session --lib live_channel_files_and_permissions -- --ignored --nocapture`。测试在夹具同目录生成 `ready.json`，控制端只为其中两个临时 UID 授权后创建 `authorized` 文件。测试覆盖密码拒绝与修正、有权身份免密进入、权限组授予/回读/恢复、普通身份被拒，以及小文件上传、目录查询、精确下载和已有文件保护。控制端负责在测试结束后删除专用频道、测试权限组和临时身份；Query 凭据不进入夹具。
