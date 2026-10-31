# AGENTS.md — 业务特性模块 (lib/features)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/features/` 下各业务功能页面。

## 模块结构

- [connect/](connect/AGENTS.md)：服务器连接、历史档案列表与地址录入表单。
- [workspace/](workspace/AGENTS.md)：主会话工作区（频道列表、聊天室、成员树、状态栏与快捷操作）。
- [settings/](settings/AGENTS.md)：设置页两级菜单架构与持久化规范。

## 规则与约束

- 特性模块之间保持低耦合，通过 `lib/core/` 提供的全局状态和导航进行解耦。
- 特性组件只向底层发送语义化动作（如 `connectServer`, `switchChannel`, `sendMessage`），不在组件内处理协议原始字段。
- 所有展示文案必须通过 `AppLocalizations.of(context)` 获取。
