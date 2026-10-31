# 子系统契约 — core/server

本文定义 `core/server` 的职责、关键调用序列与不变量。

## 职责

- 管理用户显式录入的服务器档案 `ServerProfile` 与内存/持久化集合 `ServerRegistry`。
- 提供纯地址解析 `parse_address` 与主机/端口归一化拼接 `join_host_port`。
- 本子系统保持零网络 IO、零协议依赖与零异步运行时依赖；不判断是否允许连接，不维护官方主机屏蔽清单。

## 关键路径与序列

1. **地址录入与解析**：
   调用方传入原始字符串 `input` → `parse_address` 清除前后空白并校验非空 → 解析 IPv6/IPv4/域名与可选端口（默认端口 `9987`） → 产出强类型 `ServerTarget`。
2. **档案生成与持久化**：
   从 `ServerTarget` 构造 `ServerProfile`，以规范化的 `host:port` 作为唯一主键 `id` → 保存至 `ServerRegistry`。
3. **连接前校验提取**：
   连接发起时调用 `ServerProfile::target()` 重新解析，验证主键一致性后交付下游 `core/proto`。

## 不变量

- `core/server` 不包含网络套接字或 DNS 解析调用，所有解析仅为纯字符串语法级判定。
- `ServerProfile.id` 始终精确等于 `join_host_port(&self.host, self.port)`，天然实现同目标去重。
- 不在此层对 myTeamSpeak 或官方域名做屏蔽拦截，拦截职责完全由下游 `core/proto` 独占。
