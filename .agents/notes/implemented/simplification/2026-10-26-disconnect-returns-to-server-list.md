# Agent Note: 断开连接后回到服务器列表

Status: implemented

## Problem

从工作区右键断开服务器后，路由仍停在 `/workspace`：频道栏清空，主区域显示「未连接服务器」占位，用户还要再点一次按钮才回到连接页。占位页只承接这一个中间态，却让「下一步选哪台服务器」这个唯一可做的动作晚一步出现。

## Decision

- `ServerRail` 的断开动作由外壳注入（`onDisconnect`），不再直接调用会话控制器。`SessionController.disconnect` 返回 core 调用的成败，`WorkspaceShell` 只在成功时 `context.go(AppRoutes.connect)`；断开失败时留在工作区并保留提示。导航不读刚被事件改写的 `SessionView.connected`，避免抢在异步广播之前。
- 删除 `WorkspacePage` 的未连接占位页，以及只服务于它的 `workspaceNotConnectedTitle`、`workspaceNotConnectedBody`、`connectTitle` 文案。连接页本身已经承担服务器选择与新建入口。
- 服务端强制掉线、重连失败等路径不经过这里：它们仍按原有的会话状态与提示处理。

## Alternatives considered

- **保留占位页，再自动跳转**：两套入口并存，慢一点的断开路径仍会闪出占位页；页面本身没有独立价值。
- **在路由层按会话状态重定向**：路由不订阅 `sessionViewProvider`，把状态判断塞进 `redirect` 会让连接页的返回与深链也受连接状态影响。
- **让 core 在断开后通知 UI 路由**：路由归属 Flutter 层，core 只广播会话状态；跨层回调会让连接边界的职责变混。

## Consequences

- 显式断开成功即离开工作区，回到服务器列表；失败时工作区保持原样。
- 占位页删除后，工作区在未连接状态下只会短暂存在到导航完成，不再作为一个可停留的页面。
- `ServerRail` 多一个必填回调，新的外壳接入点需要同时提供断开后的去向。

## Testing

- 断开后的去向没有自动回归用例：改这条路径时手动跑 `just run`，右键服务器磁贴与长按磁贴各断开一次，确认路由落到 `AppRoutes.connect`，并确认断开失败时留在工作区。