---
name: fls-pre-push-checks
description: 推送、强推、把 PR 标为可评审或声称检查通过之前使用：按即将推出的 diff 选出覆盖它的最小检查集，而不是反射式地跑全量套件。
---

# 推送前的检查

本技能只决定「跑哪些命令」。命令全集与平台细节在 [docs/development.md](../../../docs/development.md)，聚合入口是仓库根 justfile 的 `just check`，CI 门禁见 [docs/ci-cd.md](../../../docs/ci-cd.md)，这里不重述。

## Sources of truth

- [docs/development.md](../../../docs/development.md)：Rust/FFI/Flutter 的原始命令、macOS 的 Opus 构建细节。
- [docs/testing.md](../../../docs/testing.md)：单测摆放、测试范围选择、真实服务器手动测试、CI 测试门。
- [docs/defensive-patterns.md](../../../docs/defensive-patterns.md)：编码反面与连接边界改动的自查要求。
- [docs/ci-cd.md](../../../docs/ci-cd.md)：CI 各作业与发布矩阵、本地复现方法。
- [.github/workflows/ci.yml](../../../.github/workflows/ci.yml)：PR 的实际门禁。

## 工作流步骤

1. **确认分支与范围**：

```sh
git status --short --branch
git diff --stat origin/main...HEAD
```

2. **按改动面选最小证据**（每个行为改动都要有「回归时会失败」的那条测试或检查）：
   - `core/` 某个 crate 的行为：从 `plugins/flspeak_ffi/rust` 定向跑拥有它的测试，例如 `cargo test -p server -p proto`；改动共享 crate 时再补相邻 crate 的测试。
   - 连接边界（`core/proto`、`core/server`、`FORBIDDEN_HOST_SUFFIXES`、`check_transfer_host`）：先按 [docs/defensive-patterns.md](../../../docs/defensive-patterns.md) 的连接边界一节自查——决策记录先行，放宽限制必须写清理由与残余风险——再补相似域名与目标重定向的测试。
   - `plugins/flspeak_ffi/rust/src/api/**` 或其中的类型：重跑 `flutter_rust_bridge_codegen generate`，确认生成物一起提交。
   - `lib/`、`arb/`：`dart format lib setup.dart`、`flutter analyze --no-fatal-infos`；改了 `arb/` 先 `flutter gen-l10n`。界面行为没有自动回归，改动面向用户时手动跑 `just run` 走一遍相关路径。
   - `docs/`、`.agents/`、`AGENTS.md`：仓库内相对链接与路径是否解析（见验证命令），笔记还要按[核查清单](../../../.agents/notes/AGENTS.md#核查清单)过一遍。
   - `.github/workflows/`、`setup.dart`、native assets 钩子：本机无法复现发布矩阵的，推到 PR 后看 `gh pr checks`，不要在本地假装验证过。
3. **只在必要时做全量排练**：用户明确要求、正在诊断 CI 失败、或改动跨到没有更窄集合可信时才跑 `just check`。不要因为「反正要提交」重复一遍刚通过的检查。
4. **保护重写历史的推送**：重写前先取远端分支的确切 OID，用 `git push --force-with-lease=<branch>:<observed-oid>` 发布，绝不用裸 `--force`。重写后重新取远端 head，重新审查评审线程、批准与检查状态。
5. **失败处置**：相关检查失败就停下修掉，不要先推再看 CI。怀疑是环境差异时，记录确切命令、失败的测试与平台差异，先确认与平台无关的证据全部通过，再决定是否绕过。
6. **推送后**：`git rev-parse HEAD origin/$(git branch --show-current)` 确认远端 ref 与本地一致，然后看 `gh pr checks`；pending 就报 pending，失败先看日志再归因。

## 验证命令

```sh
# 改动面
git status --short --branch
git diff --stat origin/main...HEAD

# 定向测试（从 plugins/flspeak_ffi/rust 跑；示例）
cargo test -p server -p proto

# 文档与笔记的链接核查
grep -rn "](.*\.md" docs/ .agents/ AGENTS.md | grep -v "http"
find .agents/notes -name "*.md" | sort

# 全量门禁（按需）
just check

# 推送与远端状态
git rev-parse HEAD origin/$(git branch --show-current)
gh pr checks
```

## 报告要求

报告：改动范围（哪些路径）、选了哪些检查及理由、每条命令的结果、跳过了哪些检查以及为什么、远端 ref 与本地是否一致、`gh pr checks` 的当前状态。pending 一律报 pending，不要写成通过。
