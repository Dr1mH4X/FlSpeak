# 编码约定

## 通用

- 结论先行，不寒暄，不写没信息量的注释。
- **FAILFAST**：错误当场暴露，不吞异常、不写兜底默认值来掩盖失败。
- **YAGNI**：不写没人调用的抽象、不写 TODO 占位、不留“以后可能用得上”的代码。
- **DRY**：同一知识只写一遍。官方域名清单只有一份，版本号只有一处来源。
- 严禁 `#[allow(...)]` / `// ignore:` 压制告警。告警是信号，改代码。
- 注释只写“为什么”，不写“是什么”。标识符与字符串用 ASCII；注释可以用中文。

## Rust

- edition 2024；核心 crate 在 `core/`，唯一进桥的 crate 是 `plugins/flspeak_ffi/rust`。
- 错误用 `thiserror`，每层一个错误类型；跨层用 `#[from]` 转换，不要 `unwrap`。
- 公共类型字段默认 `pub`，与 tsclient-rs 的风格保持一致；内部细节才收窄。
- 单测写在模块内 `#[cfg(test)] mod tests`，不依赖网络与真实服务器。
- 需要官方域名做测试夹具时，从 `policy::FORBIDDEN_HOST_SUFFIXES` 拼，
  不要写字面量（`tool/audit_policy.sh` 会拦）。

## Dart / Flutter

- 单一状态源：`SessionController` 消费 `Stream<CoreEvent>`，页面只读 `sessionViewProvider`。
- 业务逻辑不进 UI 层；UI 只做展示与转发。
- 文案全部走 `arb/`，不在 widget 里硬编码中文或英文。
- `lib/src/rust/**`、`lib/l10n/**` 是生成物，不手改。
- `dart format` 与 `flutter analyze --no-fatal-infos` 必须干净。

## 提交信息

Conventional Commits，标题 ≤100 字符，描述小写开头、结尾不加句号，中文可用：

```text
feat(session): 增加频道切换命令
fix(policy): reject look-alike official domains
docs(compliance): 记录 SRV 与 TSDNS 的取舍
```

闸门：`tool/check_commit_msg.sh`（自测 `tool/check_commit_msg_test.sh`）。不要写
`Co-authored-by:` 署名编码代理。破坏性改动用 `!` 加 `BREAKING CHANGE:` 页脚。

## 改合规策略

策略变更要走流程，见 `.agents/skills/policy-change/SKILL.md`：先写决策记录到
`.agents/notes/implemented/`，再改 `core/policy`，最后确认
`tool/audit_policy.sh` 仍然通过。