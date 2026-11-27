---
name: fls-release-log
description: 发版前写 docs/release/<tag>.md、补写或改写某个版本的 Release 正文时使用；按 git 提交归纳这一版面向终端用户的变化结果，并把它作为 GitHub Release 正文与应用内更新说明发布。
---

# 发版日志

发版日志是仓库里的一个文件：`docs/release/<tag>.md`，文件名与本版 git tag 完全一致（tag `v0.2.0` 对应 `v0.2.0.md`）。`.github/workflows/release.yml` 在打 tag 时直接以它为 GitHub Release 正文、以 `Release v<版本>` 为标题，文件缺失或首行不合格式就直接失败。

## Sources of truth

- [docs/release/AGENTS.md](../../../docs/release/AGENTS.md)：文件格式、分类顺序、写法判据与生命周期的唯一归属地，动笔前先读，本技能不复述。
- [docs/ci-cd.md](../../../docs/ci-cd.md)：发布流程、发布矩阵与 `setup.dart` 的已知简化。
- [docs/development.md](../../../docs/development.md)：发版打包命令与版本号推导。
- git：上一个 tag、范围内的提交主题与正文、merge commit 里的 PR 号、提交作者。

## 工作流步骤

1. **定 tag 与范围**：tag 由用户指定；未指定时按 semver 从上一个 tag 推断，范围里有 `feat` 或破坏性变更进 minor/major，否则进 patch。`git fetch --tags` 后取 `git describe --tags --abbrev=0` 作为上一版，范围是它到 `HEAD`；仓库还没有 tag 时由用户定首版版本号，不要自己发明。
2. **读全部提交并提炼用户结果**：逐条看主题与正文，把每个 `Merge pull request #N` 与它带进的改动对应起来，这样条目能附上 `（#N）`；直接提交到主干的提交没有 PR 号，省略即可。判断不准某条改动的用户可见结果时，用 `git show <sha>` 看它实际改了什么；无用户可感知影响的内部重构、测试或文档改动合并精简或省略。
3. **写正文并自查术语与腔调**：首行、分类顺序与写法判据见 [docs/release/AGENTS.md](../../../docs/release/AGENTS.md)。成稿后逐条通读，确认每条都像写给普通用户的说明：剔除函数名、类名、内部事件/FFI 符号、控件名与底层机制，并把「补齐」「接线」「落盘」「钻取」「退避」「遥测」「链路」等内部工程词改成自然直白的结果描述。
4. **写升级注意**：检查范围内是否有需要终端用户手动处理的变更（如签名更换需卸载重装、新增系统权限要求、配置迁移、安装包形态或支持平台变更）；有人需要动手才写，没有就删掉整节。
5. **写贡献者**：`git log <range> --pretty=%an` 取人类作者，机器人账号（如 `dependabot[bot]`）不计，写成 `@handle`。
6. **落盘**：写 `docs/release/<tag>.md`，与该版改动同一个 PR 提交。tag 打完后冻结，只有事实写错才回头修改，并在提交信息里说明改的是哪一处。
7. **发布**：tag 推送后 CI 自动把该文件作为 Release 正文公开发布（带 `-beta`、`-rc`、`-dev` 时自动标为预发布）；需要手工补发或改写时用下面的 `gh` 命令。未知 tag 不要发明版本号，先与用户确认。

## 验证命令

```sh
git fetch --tags
git describe --tags --abbrev=0
git log --oneline "$(git describe --tags --abbrev=0)"..HEAD

# 文件与 tag 必须同名
test -f "docs/release/<tag>.md" && echo ok

# 格式自查：首行的版本、日期与简述，分类节名与顺序
head -n 1 "docs/release/<tag>.md"
grep -n '^## ' "docs/release/<tag>.md"

# 复核或手工修改 Release 标题与正文
gh release view <tag> --json name,body
gh release edit <tag> --title "Release <tag>" --notes-file "docs/release/<tag>.md"
```

## 报告要求

给出：目标 tag、Release 标题（`Release v<版本>`）、正文首行（版本、发布日期、主要更新简述）、提交范围与提交数、每个分类的条目数、升级注意的条目（没有就说没有）、贡献者、写出的文件路径。拿不准用户可见性的改动单独列出并说明判断依据，不要为了凑齐分类而写条目。
