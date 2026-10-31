# 连接边界防御准则

本文定义连接边界、地址解析与网络请求相关的反面模式与守则。

## 官方主机边界与单一出口

- 错误做法：在 UI、FFI 或存储层复制官方主机检查；放宽限制时只改代码不留记录；客户端尝试自动解析或连接 myTeamSpeak 官方服务。
- 正确做法：边界规则与代码位置见 [../connection-boundary.md](../connection-boundary.md)，检查只由 `core/server` 与 `core/proto` 承担；改边界先按 `.agents/notes/AGENTS.md` 写决策记录，放宽限制必须在记录里写清理由与残余风险，并补相似域名和目标重定向的测试。

## 目标主机解析防线

- 错误做法：将 SRV 解析后的目标未经验证直接发起 UDP 连接；接受裸昵称输入；依赖外部不可控的 HTTP 服务进行域名查找。
- 正确做法：只连接用户手动录入的 IP、域名或 localhost；SRV 记录解析得到的主机名在发起连接前必须走 `core/proto` 的 `check_transfer_host` 做一次官方基础设施检查，不在其他层重复审查。
