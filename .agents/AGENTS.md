# AGENTS.md — Agent 上下文与规范

本目录保存面向编码代理（Coding Agent）的上下文配置、决策记录与专属技能。

## 子树分工

- [project.md](project.md)：仓库核心不变量、分层架构与依赖边界总览。
- [notes/](notes/AGENTS.md)：不可变技术决策记录（ADR），分为 active (`notes/`)、已落地 (`implemented/`) 与历史归档 (`archived/`)。
- [skills/](skills/AGENTS.md)：Agent 自有复用工作流与自动化操作标准（`SKILL.md`）。

## 写作规则

- 本目录仅面向编码代理，禁止混入面向终端用户的操作文档（用户操作文档归 `docs/`）。
- 技能与决策记录严格遵守一事一议原则，不直接修改代码或运行期逻辑。
