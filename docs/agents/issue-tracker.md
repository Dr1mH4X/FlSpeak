# Issue Tracker：GitHub

本仓库的 issue 与 spec 存放为 GitHub issue，所有操作使用 `gh` CLI。

## 目标仓库

本仓库有两个 remote：`origin` 指向 `Dr1mH4X/FlSpeak`，`zeroblock0` 指向 `ZeroBlock0/FlSpeak`。`gh` 在克隆内以 `origin` 为准；写入前用 `gh repo view --json nameWithOwner` 确认目标仓库是 `Dr1mH4X/FlSpeak`。

## 操作

- **创建 issue**：`gh issue create --title "..." --body "..."`，多行正文用 heredoc。
- **读取 issue**：`gh issue view <number> --json number,title,body,labels,comments`。
- **列出 issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，按需加 `--label` 与 `--state` 过滤。
- **建立子 issue**：`gh issue create --parent <parent> ...`，或事后 `gh issue edit <parent> --add-sub-issue <child>`。
- **建立阻塞关系**：`gh issue create --blocked-by <n>,<n> ...`，或 `gh issue edit <child> --add-blocked-by <blocker>`。
- **统计未关闭的阻塞项**：`gh api repos/Dr1mH4X/FlSpeak/issues/<n> --jq .issue_dependencies_summary.blocked_by`，结果为 0 表示可开工；`gh issue view <n> --json blockedBy` 会包含已关闭的阻塞项，需要自行过滤。
- **评论**：`gh issue comment <number> --body "..."`。
- **加标签 / 移除标签**：`gh issue edit <number> --add-label "..."` / `--remove-label "..."`。
- **关闭**：先用 `gh issue comment <number>` 写下说明，再执行 `gh issue close <number>`。对已关闭的 issue，`gh issue close --comment` 会丢弃评论，且退出码仍为 0。

只在本仓库写 issue。`gh` 在 fork 中可能默认指向上游父仓库，因此每个会话的第一次写入前都要确认目标仓库。

## PR 作为请求入口

**PR 作为请求入口：否。** 本仓库不把外部 PR 当作功能请求，`/triage` 只处理 issue。

## 技能措辞映射

- **「publish to the issue tracker」**：创建一个 GitHub issue。
- **「fetch the relevant ticket」**：按上面的「读取 issue」读取。
- **「apply the triage label」**：本仓库未安装 `triage` 技能，也没有 triage 标签词表；标签沿用仓库现有的 `bug`、`enhancement`、`documentation`、`question`、`wontfix` 等 GitHub 标签。
