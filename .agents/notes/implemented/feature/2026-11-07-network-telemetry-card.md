# Agent Note: 网络遥测卡片延伸与连接统计

Status: implemented

## Problem

网络遥测从用户卡弹出一张模态卡片，只展示目录探测延迟、抖动和失败率；连接期间没有固定的遥测入口，也看不到协议层的 ping、双向丢包与空闲时长。

## Decision

- 入口保持在用户卡的网络状态行；点击后用户卡向上延伸，网络面板成为同一张卡片的顶部区域，不再弹出第二张浮层。
- 面板只在展开时构建；关闭动画结束后销毁采样定时器、延迟历史和监听。
- 图钉把展开区固定为常开，状态写在 `SessionView.networkPanelPinned`，只随当前连接存在；断开或重连后复位。窄屏抽屉收起会销毁面板与采样定时器，重新打开时按固定状态恢复。
- 面板头部为 `Network status`，左侧不再放 Wi-Fi 图标；四行指标为 `Ping`、`Loss in`、`Loss out`、`Idle time`，空闲时长按 `dd:hh:mm:ss` 显示。
- `Ping`、`Loss in`、`Loss out` 是三个独立指标组件，各自在右侧用 `SignalRibbon` 显示最近 24 个样本；`Idle time` 单独一行，不带动画。
- 卡片宽度就是用户卡在频道栏里的宽度，展开区不跨入聊天区；频道栏变窄时压缩指标值与信号条宽度。
- 动画开启时显示三条迷你轨迹，并用高度因子让卡片从入口处向上展开；减少动效时省略信号条并直接切换高度。
- 数据来源：展开期间每秒发一次 `getconnectioninfo clid=<self>`；`tsclient-rs` 未建模该命令，`core/session` 从原始 `notifyconnectioninfo` 解析 `connection_ping`、`connection_{server2client,client2server}_packetloss_total`、`connection_idle_time`。协议 ping 是权威值，目录探测延迟只在协议字段缺失时兜底。
- 服务器请求本端连接信息时，Actor 用已知协议 ping（缺失时用探测延迟）回答 `setconnectioninfo`；重复请求在一个最小间隔内合并。

## Alternatives considered

- **保留模态卡片**：遮罩打断当前操作，关闭前一直占据焦点。
- **独立浮层贴在入口上方**：入口卡片和浮层各有一套圆角，间距很小时两层圆角并排，视觉上像两张卡。
- **停靠主区域底部**：占用聊天输入区，并把网络状态与语音控制拆到两个区域。
- **只在打开时提高目录探测频率**：目录请求会改动频道树，不适合作为轻量遥测。
- **在 Dart 侧独立轮询**：协议命令必须经 Actor 串行执行，UI 不能直接持有 `Client`。

## Consequences

- 展开区的可见性决定采样是否存在；关闭后不再增加服务器查询。
- 每秒一次查询属于轻量命令，`tsclient-rs` 的令牌桶上限为每秒 4 条命令，常规交互仍有余量。
- `Loss in` 依赖协议字段，部分服务器返回 0 或缺失；缺失时显示「暂无数据」。
- 方向丢包与 idle 来自服务器查询；协议 ping 决定延迟质量，目录探测提供失败率、抖动兜底与无查询权限时的延迟数据。
- 图钉不写入偏好，重启应用后恢复收起。

## Testing

- `core/session` 的 `network::tests` 覆盖字段换算、缺失字段保留与探测历史合并。
- `NetworkStatus` 的 widget 测试覆盖卡片延伸/收起、四行指标、三条迷你轨迹、用户卡宽度、图钉、减少动效、关闭后停止采样。
- 真实服务器上的 `getconnectioninfo` 权限与字段可用性在手动连接中核对。
