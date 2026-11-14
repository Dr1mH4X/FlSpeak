# Agent Note: PluginCommand 开放身份互认与 Bot 斜杠命令协议

Status: implemented

## Problem

TeamSpeak 服务端与客户端标准协议不区分第三方客户端实现与机器人节点，也不提供结构化的私信命令发现机制；如果机器人节点在进出频道时广播完整命令清单，会触发 TeamSpeak 单条 `plugincmd` 约 1024 字节载荷限制以及服务端 Anti-Flood 积分桶踢出机制。

## Decision

- 采用两阶段分层插件命令协议：第一阶段 `tsclient:identity` 仅交换客户端类型、软件名、版本号与能力标签（`capabilities`）；第二阶段 `tsclient:commands` 仅在打开支持 `"chat:slash_commands"` 的私信窗口或键入 `/` 时通过单播按需拉取命令清单。
- 所有 `plugincmd` 的收发、防刷冷却与会话缓存统一收敛在 `core/session` 的 `Actor` 内串行调度，不向 Dart 暴露原始插件命令通道。
- 入站报文执行版本号校验（仅处理 `v = 1`）与严格的长度、数量截断：`app_name` 与 `app_version` 截断至 32 字符，`capabilities` 最多保留 16 项且单项截断至 32 字符；命令清单最多保留 16 条，单条命令的 `name`、`args`、`desc` 分别截断至 24、32、64 字符；`BotCommandView` 的 `args` 与 `desc` 标记 `#[serde(default)]`，容忍省略空字段的精简 JSON 报文；出站 `tsclient:identity` JSON 载荷严格限制小于 1024 字节。
- 防刷频与去重冷却：
  - 本端进房或切换频道触发的 `announce` 频道广播通过 `announce_state` 强制去抖至少 2 秒（`SELF_ANNOUNCE_DEBOUNCE`），窗口内连续切房会调度去重后的尾随广播，首次发送失败时回滚去抖时间并在 500 毫秒后单次重试。
  - 忽略 `invoker_id` 等于本端 `self_client_id` 的回显广播。
  - 通过 `ack_limiter` 按 `(peer, action)` 维护独立冷却（收到 `announce` 在 10 秒内、定向 `query` 在 5 秒内最多单播回复一次 `announce_ack`）并自动清理过期记录，叠加全局出站令牌桶限制洪峰；先校验连接存活与载荷体积再扣减配额，发送失败时回滚该对端冷却。
  - 按对端 UID 维护 `peer_commands` 缓存与 `commands_fetching` 在途集合：同一连接周期内每个 UID 最多发起一次 `list_req` 单播查询，在途期间忽略重复触发，收到 `list_ack` 或断线重置时清理在途标记。
- 频道树成员行在昵称右侧为 `ClientType.bot` 渲染机器人徽标（`Icons.smart_toy_rounded`），为 `ClientType.flSpeak` 渲染闪电徽标（`Icons.electric_bolt_rounded`），通过 `Semantics` 提供读屏标签，不使用任何悬停提示。
- 成员详情弹窗对非标准客户端展示客户端软件名、版本号与能力标签 Chip。
- 私信输入区（`ChatScope.direct`）在以 `/` 开头且不含空格时，在输入框上方内联展示匹配的斜杠命令补全列表；点击补全项自动填入 `/${cmd.name} ` 并将光标移至末尾，一旦输入包含空格进入参数阶段即自动收起补全列表。

## 协议规格

### 1. 身份互认子协议：`tsclient:identity`

- **Plugin Name**：`tsclient:identity`
- **TargetMode**：`0 (CurrentChannel)` 用于进房广播 `announce`；`2 (Client)` 用于单播回执 `announce_ack` 与跨频道定向探测 `query`。
- **JSON 载荷**：

```json
{
  "v": 1,
  "action": "announce",
  "client_type": "flspeak",
  "app_name": "FlSpeak",
  "app_version": "0.1.12",
  "capabilities": ["audio:stereo", "chat:slash_commands"]
}
```

### 2. 命令拉取子协议：`tsclient:commands`

- **Plugin Name**：`tsclient:commands`
- **TargetMode**：固定为 `2 (Client)` 单播。
- **查询报文（`list_req`）**：`{"v": 1, "action": "list_req"}`
- **响应报文（`list_ack`）**：

```json
{
  "v": 1,
  "action": "list_ack",
  "commands": [
    {
      "name": "play",
      "args": "<url|歌名>",
      "desc": "点播指定歌曲或音频流"
    },
    {
      "name": "skip"
    }
  ]
}
```

## 第三方 Bot 接入参考

基于 `tsclient-rs` 的外部 Bot 接入该协议时，需过滤自身广播回显并对 `announce` 与 `query` 统一施加单播回复冷却：

```rust
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tsclient::plugin::{PluginCommand, PluginTargetMode};
use tsclient::{Client, ClientId};

pub fn register_bot_open_protocol(client: &Client, bot_self_id: ClientId) {
    let client_weak = client.downgrade();
    let ack_cooldowns: Arc<Mutex<HashMap<String, Instant>>> = Arc::new(Mutex::new(HashMap::new()));

    client.on_plugin_command(move |event| {
        if event.invoker_id == bot_self_id {
            return;
        }
        let Some(c) = client_weak.upgrade() else { return };

        match event.name.as_str() {
            "tsclient:identity" => {
                let Ok(req) = serde_json::from_str::<serde_json::Value>(&event.data) else {
                    return;
                };
                let action = req.get("action").and_then(|v| v.as_str()).unwrap_or("");
                if action != "announce" && action != "query" {
                    return;
                }

                let cooldown = if action == "query" {
                    Duration::from_secs(5)
                } else {
                    Duration::from_secs(10)
                };
                if ! event.invoker_uid.is_empty() {
                    let mut guard = ack_cooldowns.lock().unwrap();
                    let now = Instant::now();
                    if let Some(&last) = guard.get(&event.invoker_uid) {
                        if now.duration_since(last) < cooldown {
                            return;
                        }
                    }
                    guard.insert(event.invoker_uid.clone(), now);
                }

                let target_id = event.invoker_id;
                let ack = serde_json::json!({
                    "v": 1,
                    "action": "announce_ack",
                    "client_type": "bot",
                    "app_name": "MusicBot",
                    "app_version": "2.1.0",
                    "capabilities": ["audio:stereo", "chat:slash_commands"]
                });
                tokio::spawn(async move {
                    let cmd = PluginCommand::new("tsclient:identity", ack.to_string())
                        .with_target_mode(PluginTargetMode::Client)
                        .with_target_clients(vec![target_id]);
                    let _ = c.send_plugin_command(&cmd).await;
                });
            }
            "tsclient:commands" => {
                let Ok(req) = serde_json::from_str::<serde_json::Value>(&event.data) else {
                    return;
                };
                if req.get("action").and_then(|v| v.as_str()) == Some("list_req") {
                    let target_id = event.invoker_id;
                    let ack = serde_json::json!({
                        "v": 1,
                        "action": "list_ack",
                        "commands": [
                            { "name": "play", "args": "<歌名|链接>", "desc": "点播音乐并加入队列" },
                            { "name": "skip", "args": "", "desc": "跳过当前播放曲目" },
                            { "name": "stop", "args": "", "desc": "停止播放并清空队列" },
                            { "name": "volume", "args": "<1-100>", "desc": "调整机器人输出音量" }
                        ]
                    });
                    tokio::spawn(async move {
                        let cmd = PluginCommand::new("tsclient:commands", ack.to_string())
                            .with_target_mode(PluginTargetMode::Client)
                            .with_target_clients(vec![target_id]);
                        let _ = c.send_plugin_command(&cmd).await;
                    });
                }
            }
            _ => {}
        }
    });
}
```

## Alternatives considered

- **在 `tsclient:identity` 进房广播中直接携带完整命令数组**：每个支持多条命令的 Bot 在进出房间或回应广播时都会发送接近 1 KB 的载荷，容易触及 TeamSpeak `plugincmd` 长度上限并消耗 Anti-Flood 配额。
- **使用 `TargetMode::Server (1)` 全服广播身份信息**：大型服务器下全服广播插件命令需要高阶权限且易触发服务端洪水保护，改为同频道广播加跨频道私聊单播 `query` 探测。
- **每次打开私信窗或每次输入 `/` 都重新请求 `list_req`**：造成无意义的单播往返；在 `Actor` 内通过 `peer_commands` 与 `commands_fetching` 做会话级缓存与在途防重，同一连接周期内对同一 UID 只拉取一次。
- **在徽标上使用 `Tooltip` 展示软件名与版本**：违反全仓无悬停提示约束，客户端软件版本与能力标签统一归入成员详情弹窗。

## Consequences

- 同频道成员通过一次轻量频道广播与单播回执完成身份识别；跨频道成员在打开私信窗口时按需完成单播探测。
- 斜杠命令清单仅在与声明 `"chat:slash_commands"` 的私信对象交互时拉取一次，命令执行仍走标准私信文本 `sendtextmessage`，兼容服务端日志与既有 Bot 指令解析器。
- 断线或重连（`invalidate_handlers`）会清空 `peer_identities`、`peer_commands`、`commands_fetching` 并重置 `ack_limiter` 与 `announce_state`，确保新会话重新协商。

## Related

- [会话 Actor 调度与 tsclient-rs 所有权](../../implemented/architecture/2026-10-08-session-actor.md)

## Testing

- `core/session` 的 `actor::tests` 覆盖 `BotCommandView` 缺省字段反序列化、`v = 1` 版本校验、身份与命令报文超长截断与 `< 1024` 字节载荷上限、忽略自身回显、按 `(peer, action)` 隔离 `announce`（10 秒）与 `query`（5 秒）冷却、过期清理、全局令牌桶、失败回滚、切房尾随广播与单次重试、在途防重标记清理以及断线状态重置。
- `test/core/providers_test.dart` 覆盖打开未识别私信对象触发 `queryPeerIdentity`、收到含 `"chat:slash_commands"` 的成员快照后自动拉取命令、以及成员移动或更新事件保持已识别元数据。
- `test/features/workspace/widgets/member_details_dialog_test.dart` 与 `test/features/workspace/widgets/chat_pane_test.dart` 覆盖频道树徽标读屏语义、成员详情软件与能力 Chip 展示、私信 `/` 命令按需拉取、前缀过滤、点击补全带空格以及输入空格进入参数阶段后自动收起补全列表。
