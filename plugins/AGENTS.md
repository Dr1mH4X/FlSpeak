# AGENTS.md — Flutter 插件层

本目录包含仓库专有的 Flutter 插件包，连接 Flutter 与系统/原生能力。

## 规则与约束

- 插件边界：插件仅承担跨语言类型桥接与运行时适配职责，不在此承载核心业务状态或协议逻辑。
- 现有插件 `plugins/flspeak_ffi` 规则参见 [flspeak_ffi/AGENTS.md](flspeak_ffi/AGENTS.md)。
- 涉及代码生成的插件必须在各自说明中记录确切的生成命令与生成产物范围，严禁手改生成物。
