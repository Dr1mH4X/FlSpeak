# AGENTS.md — Cookbook 操作指南

本目录包含仓库常见开发任务的 Step-by-Step 实操指南，每篇指南均包含明确的前置条件、修改步骤与可执行的验证步骤。

## 指南清单

- [新增设置项流程](adding-a-setting.md)：从 Rust `schema.rs` / `manager.rs` 配置模型到 Flutter 设置页 UI 呈现与持久化的端到端全链路操作指南。

## 写作规则

- Cookbook 是指导实操的教程（Tutorial），按序推进，只引入各步骤需要的信息。
- 凡操作必带可执行的验证步骤（包含确切命令或操作途径）。
- 设计决策与取舍原因不写在 Cookbook 中，链接到对应的 `.agents/notes/`。
- 只写当前系统标准操作流程，不叙述历史修改。
