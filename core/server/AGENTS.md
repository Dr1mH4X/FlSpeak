# AGENTS.md — 服务器档案与地址解析 (core/server)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `core/server` crate。

## 规则与约束

- **零网络依赖**：严禁在此 crate 引入网络 IO、套接字或外部异步网络库，所有逻辑均为纯数据模型与字符串解析。
- **不维护黑白名单**：本 crate 仅验证语法格式（IPv4、IPv6、域名与端口有效性），不判断是否允许连接，不维护官方主机屏蔽清单。
- **主键去重一致性**：`ServerProfile.id` 必须由规范化的 `join_host_port` 生成，作为唯一主键。
- 完整子系统契约见 [../../docs/subsystems/server.md](../../docs/subsystems/server.md)。
