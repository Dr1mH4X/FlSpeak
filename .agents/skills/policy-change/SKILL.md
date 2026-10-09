---
name: policy-change
description: 修改合规策略（禁连清单、地址校验规则、登记流程）时必须走的流程。用于放宽或收紧 T1/T2 规则、调整审计闸门、或用户要求“允许连某个官方地址”时。
---

# 变更合规策略

合规是硬约束，改它要留下决策记录，并且只有一处可以改。

## 步骤

1. **先写决策记录**：`.agents/notes/implemented/YYYY-MM-DD-<主题>.md`，包含背景、决策、
   被否决的方案、后果。放宽限制必须写清理由与残余风险。
2. **改单一事实来源**：禁连域名与官方服务端点只改
   `core/policy/src/official_infra.rs`（`FORBIDDEN_HOST_SUFFIXES` /
   `OFFICIAL_SERVICE_URLS`）。
3. **同步校验逻辑**：只在 `core/policy/src/lib.rs` 里调整
   `validate_address` / `assert_transfer_host` / `normalize_host` 等规则。
4. **补测试**：至少覆盖“新允许的样例通过”“相邻的相似域名仍被拒”（防止
   `teamspeak.com.evil.net`、`notteamspeak.com` 这类绕过）。
5. **更新文档**：`docs/compliance.md` 与根 `AGENTS.md` 的硬规则章节。
6. **跑闸门**：

   ```sh
   bash tool/audit_policy.sh
   cd plugins/flspeak_ffi/rust && cargo test -p policy -p proto
   ```

## 禁止

- 在策略层之外写字面官方域名（CI 会拦）。测试需要时从
  `policy::FORBIDDEN_HOST_SUFFIXES` 拼。
- 为了“更方便”而恢复裸昵称或 SRV/TSDNS：那会重新接通官方解析服务。
- 把策略逻辑提给 tsclient-rs 上游：上游要求与 JS 参考结构对齐，不接受这类改动。
- 只改文档不改代码，或者只改代码不写决策记录。