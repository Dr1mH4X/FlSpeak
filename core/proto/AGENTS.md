# AGENTS.md — 协议边界与解析 (core/proto)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `core/proto` crate。

## 规则与约束

- **唯一出口检查**：官方主机清单 `FORBIDDEN_HOST_SUFFIXES` 独占定义于此，所有建连前与重定向主机必须在此做唯一一次合法性检查。
- **阻断官方昵称回退**：`DenyResolver` 必须拦截所有地址解析请求，严禁向 `named.myteamspeak.com` 发起查询。
- **SRV 规范**：仅允许针对域名的标准 DNS SRV（`_ts3._udp.<domain>`）查询。
- 完整子系统契约见 [../../docs/subsystems/proto.md](../../docs/subsystems/proto.md)。
