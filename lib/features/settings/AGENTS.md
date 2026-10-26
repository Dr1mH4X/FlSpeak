# AGENTS.md — 设置页

这些规则补充根 [AGENTS.md](../../../AGENTS.md) 与 [lib/AGENTS.md](../../AGENTS.md)，只覆盖
`lib/features/settings/`。

- 设置行只放标题、当前值和操作。标题说明「调什么」，`subtitle` 放当前值；不加解释性灰字。
- `SettingsRow` 不提供 `description`。需要说明的约束写进代码注释或文档，不占设置页版面。
- 不为设置项写「这是做什么的」副文案，例如「底部电平条跟随的来源」「服务器档案与偏好文件位置」。