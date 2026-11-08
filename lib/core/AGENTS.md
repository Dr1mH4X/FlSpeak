# AGENTS.md — 前端核心状态与服务 (lib/core)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/core/`。

## 规则与约束

- **状态唯一来源**：`SessionController` 消费来自 Rust FFI 的 `CoreEvent` 流，派发不可变的 `SessionView`；业务组件一律通过 `sessionViewProvider` 读取，不要维护第二份会话状态。
- **通知中心**：页面级瞬时错误与浮动提醒统一通过 `NoticeCenter` 处理，不使用原生 `SnackBar` 或页面自制横幅。
- **日志管道**：遵循 [docs/defensive-patterns/logging.md](../../docs/defensive-patterns/logging.md)，通过 Talker 收集应用诊断，`JsonLinesFileObserver` 异步串行写入 `frontend.YYYY-MM-DD.log`，错误级别立即 flush，队列溢出丢弃旧记录，按 UTC 日期保留 7 天；非调试构建不记录 DEBUG；前端严禁越权记录连接与会话等后端领域状态。
- **目录调起与降级**：通过 `launchOrCopyDirectory` 调起系统文件管理器，调用必须限制最长 3 秒超时；失败或超时后必须自动降级为向剪贴板写入目录路径并提示用户。
- **单测摆放**：Dart 单测集中放置在根目录 `test/` 下，镜像 `lib/` 源码目录层级（如 `lib/core/directory_launcher.dart` 对应 `test/core/directory_launcher_test.dart`）。
