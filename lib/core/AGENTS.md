# AGENTS.md — 前端核心状态与服务 (lib/core)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/core/`。

## 规则与约束

- **状态唯一来源**：`SessionController` 消费来自 Rust FFI 的 `CoreEvent` 流，派发不可变的 `SessionView`；业务组件一律通过 `sessionViewProvider` 读取，不要维护第二份会话状态。
- **通知中心**：页面级瞬时错误与浮动提醒统一通过 `NoticeCenter` 处理，不使用原生 `SnackBar` 或页面自制横幅。
- **单测摆放**：单元测试严格与被测文件位于同一目录（如 `foo.dart` 与 `foo_test.dart`）。
