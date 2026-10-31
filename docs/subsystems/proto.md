# 子系统契约 — core/proto

本文定义 `core/proto` 的职责、关键调用序列与不变量。

## 职责

- 对用户输入的域名执行异步 DNS SRV（`_ts3._udp.<domain>`）记录解析，将逻辑服务地址解析为目标主机与端口。
- 维护全仓唯一的官方基础设施屏蔽清单 `FORBIDDEN_HOST_SUFFIXES`，在最终连接前执行唯一出口防御。
- 提供 `DenyResolver` 彻底阻断 `tsclient-rs` 内部对 `named.myteamspeak.com` 的默认回退查找。
- 封装客户端工厂 `client()` 与文件传输主机检查 `check_transfer_host()`。

## 关键路径与序列

1. **SRV 记录解析与重定向提取**：
   收到 `ServerTarget` → 若为 IP 字面量或 localhost 直接透传 → 若为域名，调用 `hickory_resolver` 查询 `_ts3._udp.<host>` → 命中 SRV 时提取目标主机与端口。
2. **唯一出口连接防御**：
   解析后产出最终目标主机名 → 调用 `ensure_allowed_target` 匹配 `FORBIDDEN_HOST_SUFFIXES` → 若匹配官方后缀则直接返回 `ConnectError::Blocked` 熔断连接。
3. **安全 Client 实例构建**：
   通过 `proto::client()` 创建 `tsclient_rs::Client`，注入 `DenyResolver`，确保内部任何隐式域名查找均被直接拦截报错。

## 不变量

- `FORBIDDEN_HOST_SUFFIXES` 是全仓唯一的官方主机屏蔽名单；UI、FFI、图片抓取与会话层均不得复制维护私有后缀列表。
- `DenyResolver` 恒定拒绝任何解析请求，彻底根除通过官方昵称查询接口泄露用户网络行为的可能。
- 任何发往 TeamSpeak UDP 端口的建连操作前，必须通过本子系统的单一出口校验。

## 相关决策

- [连接边界架构设计](../../.agents/notes/implemented/architecture/2026-10-25-connection-boundary.md)
