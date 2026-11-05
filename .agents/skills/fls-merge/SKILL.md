---
name: fls-merge
description: >-
  仅在用户明确要求将改动合并到 FlSpeak 的 main 分支时使用，包括选择 Merge Change 操作或调用 /merge、/fls-merge；评审、准备、检查通过或安装技能本身不触发此技能。
disable-model-invocation: true
metadata:
  delta-action: land
---

# 合并改动

## 依据来源

- [docs/development.md](../../../docs/development.md)：项目命令、测试范围与开发约定。
- [docs/testing.md](../../../docs/testing.md)：本地测试选择与 CI 测试覆盖。
- [docs/ci-cd.md](../../../docs/ci-cd.md)：CI 工作流、触发排除项与检查。
- [justfile](../../../justfile)：受支持的本地验证任务。
- [.github/workflows/ci.yml](../../../.github/workflows/ci.yml) 与 [.github/workflows/checks.yml](../../../.github/workflows/checks.yml)：当前 CI 触发规则与必需作业定义。
- [docs/defensive-patterns/review.md](../../../docs/defensive-patterns/review.md)：审查规范。

## 工作流

1. 本技能或 Merge Change 操作的调用即表示用户明确要求合并；无需再次询问是否授权。评审、准备、检查通过或安装技能本身都不构成合并请求。
2. 检查 `git status --short --branch`、当前分支与提交、远端以及相对 `main` 的差异。确认合并范围，并保留无关或未提交的改动；绝不丢弃、暂存或纳入无关改动。目标或范围不明确时停止并询问。
3. 用 `git fetch origin` 更新远端状态。确认目标为 `origin/main`，检查当前分支保护与合并设置，并确认对应 PR。尚无 PR 时，只准备用户要求的改动及其必要提交，再用 GitHub CLI 创建目标为 `main` 的 PR；不直接推送到 `main`。新建提交遵循项目 Conventional Commits 约定，不添加代理的 `Co-authored-by` 尾注。
4. 按改动路径与行为选择本地检查。优先使用 `justfile` 中适用的任务：`just fmt-check`、`just rust-clippy`、`just rust-test`、`just analyze`、`just analyze-plugin`、`just test`、`just codegen-check` 与 `just website-check`。Rust 任务从 `plugins/flspeak_ffi/rust` 执行，FFI 代码生成从 `plugins/flspeak_ffi` 执行。改动要求全量验证或没有可靠的窄范围检查时运行 `just check`；对照工作流确认其他适用的构建检查。纯文档改动不要求无关的全量测试。
5. 用 `gh pr view <number> --json state,baseRefName,headRefName,reviewDecision,statusCheckRollup` 与 `gh pr checks <number>` 检查 PR 的评审状态和适用的 CI 状态。CI 作业包括 Rust、Dart、Dart 测试与插件检查、桌面构建和 Android 构建。`ci.yml` 排除纯 Markdown 与 `LICENSE` 改动，这类改动可能没有 CI 状态；不得把缺失状态说成通过。根据当前仓库设置与策略确认必需检查；缺少必需覆盖时安排适用验证，或在策略确有歧义时停止。所有必需检查必须在待合并的确切 PR 版本上通过，必需评审必须完成。合并前立即重新检查；待处理、失败、缺失或无法验证的必需检查都构成阻塞。
6. PR 落后于 `main` 时，按仓库当前合并设置使用非交互式 GitHub CLI 操作更新 PR。只有在目标结果明确且冲突仅涉及预期改动时才自动解决；含义不明确，或可能覆盖、丢弃无关改动时暂停并询问用户。报告冲突及处理结果，或说明暂停原因。冲突解决或更新 PR 后重跑受影响的本地检查，并等待更新后确切 PR 版本的必需检查通过。
7. 仅在适用评审与检查通过后通过 GitHub 合并 PR。使用仓库配置的合并方式；未配置或设置不明确时停止询问，不自行猜测。不得绕过分支保护、失败检查或评审要求。
8. 确认 PR 已合并至 `main`，再 fetch 并确认 `origin/main` 包含合并提交。任何阻塞导致无法完成时，明确说明尚未合并及剩余事项。

## 验证命令

从仓库根目录运行 `justfile` 定义的适用任务：

```sh
just fmt-check
just rust-clippy
just rust-test
just analyze
just analyze-plugin
just test
just codegen-check
just website-check
just check
```

用以下命令检查并验证 PR 与目标分支：

```sh
gh pr view <number> --json state,baseRefName,headRefName,reviewDecision,statusCheckRollup
gh pr checks <number>
git fetch origin
git rev-parse origin/main
```

## 报告要求

说明改动是否已合并。报告 PR 与目标分支、合并成功时的提交、适用评审与检查、本地运行的命令及结果，以及未运行或不可用的检查和原因。报告冲突及其解决情况；未合并时指出阻塞项，并确认没有发生合并。
