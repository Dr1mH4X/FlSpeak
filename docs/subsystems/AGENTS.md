# AGENTS.md — 子系统契约文档

本目录每个文件对应一个底层模块或独立 crate 的契约归属地：架构文档只做拓扑索引，跨文件契约、核心调用序列与不变量写在这里。

## 子系统清单

- [core/server](server.md)：服务器档案、配置与纯地址解析契约。
- [core/proto](proto.md)：DNS SRV 解析、最终连接边界与官方主机名单校验契约。
- [core/session](session.md)：Session actor 串行调度、tsclient-rs 独占交互与生命周期契约。
- [core/audio](audio.md)：双线程无锁环形缓冲区、Opus 编解码与设备管理契约。
- [plugins/flspeak_ffi](ffi.md)：FFI 桥、类型映射、事件广播通道与安全生命周期契约。

## 归属边界与写作规则

一个子系统是一块有明确契约的代码（如 `core/server`、`core/proto`、`core/session`、`core/audio`、FFI 桥）；划分跟着代码归属走，不跟着功能特性走。横跨多个子系统的链路不建子系统页，写进 `docs/` 顶层的主题文档（`audio.md`、`backend.md`、`connection-boundary.md`、`images.md`），其他地方只链接。

写作规则继承 [../AGENTS.md](../AGENTS.md)：只写当前状态与契约，不写变更史、不写 PR 与 commit 编号、禁 emoji、一段一物理行。另外三条界限：

- 不誊写源码里能直接读到的实现细节（逐行逻辑、私有函数、常量表），也不写决策的理由与取舍——后者的归属地是 `.agents/notes/`，每篇末尾用「相关决策」链过去。
- 不复述面向使用者的安装与操作说明（归根 `README.md`），也不复述目录级规则（归该目录的 `AGENTS.md`）。
- 每篇固定四节且按序：职责、关键路径与序列、不变量、相关决策；没有相关决策记录时整节省略，不要写「无」。

## 新增与拆分

新增一篇的条件是那块代码有独立契约、且在 [../architecture.md](../architecture.md) 的目录职责表里占一行。一篇文件同时讲了两件不相关的事就是拆分信号：按契约边界拆开，同步更新索引表，并让旧位置留下指向新文件的链接。
