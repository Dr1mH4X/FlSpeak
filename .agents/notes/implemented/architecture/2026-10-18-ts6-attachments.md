# Agent Note: TS6 图片附件与富文本

Status: implemented

## Problem

在真实 TS 服务器上用 `live_probe` 抓到了官方客户端的图片消息。它不是 URL，也不是 TS3
BBCode，而是单行 JSON：

```json
{"msg_type":"ts.file.myts","file_id":"...","chat_user_id":"@...:chat-2.tmspk.net","file_name":"image_....png","file_size":69244,"body":"image_....png","v2":true}
```

官方客户端代码确认：图片字节由 myTeamSpeak 附件服务保存；收图走
`tsclient_internal.tschat_downloadAttachment`，发图先 `myTsFileTransferUpload` 再发这段
JSON。自托管服务器不保存图片字节，`file_id` 不是可直接访问的 HTTP 地址。

富文本格式同样来自真实服务器的抓包样本：`**bold**`、`*italic*`、`~~strike~~`、
`++underline++`、`[link](url)`、`> quote`、`# heading`、`$math$`、`||spoiler||`、
`:::details`、`:::left`、` ```mermaid `、`==highlight==`、表格、`:+1:` 等。它是 Markdown
风格，不是 TS3 BBCode。

## Decision

1. **不接 myTeamSpeak 附件服务**。用户明确不做 myTS token；官方图片不下载、不访问
   `tmspk.net`，只显示「不支持的图片格式」+文件信息。
2. **第三方 URL 独立抓取**。`core/session` 的 `images.rs` 只接受 http/https；拒绝
   `proto::forbidden_host` 命中的主机、localhost/私网/链路本地/CGNAT/IPv4-mapped IPv6；
   DNS 解析后逐个检查并 pin 到公网地址；限制 3 次重定向、15s、20 MiB、`image/*`/magic。
   Dart 通过 FFI `fetchImage` 取字节。
3. **不伪造附件消息**。发送侧不生成 `ts.file.myts`；只支持用户自配图床 + URL。官方客户端
   是否把第三方 URL 渲染成图片仍未验证，不能承诺。
4. **富文本先做安全子集**。解析在 Dart UI 层完成，原始文本不动；暂不支持链接点击、脚注、
   数学排版、mermaid、可揭示 spoiler。

## 自托管上传

用户配置 HTTP PUT 上传根地址与公开访问根地址，两者经过 Rust 的 `validate_image_host` 验证。上传只由选图或粘贴图片后的发送操作发起，聊天内容不能指定上传目标。地址不带凭据、查询参数或片段；两种地址都复用 `proto::forbidden_host`，HTTPS 是常规传输，本机开发允许 loopback HTTP。

`core/session` 的 `upload_image` 生成随机文件名，根据图片字节选择 MIME 与扩展名，限制 20 MiB、60 秒，不使用环境 HTTP 代理，也不跟随重定向。公开 URL 从配置生成，不采用服务端响应里的地址。上传地址、公开地址与可选 Bearer token 一起保存在平台安全存储；普通偏好文件和消息历史不保存令牌。macOS 使用非共享 Keychain，避免分发构建依赖 Keychain Sharing 的配置描述文件。

图片消息使用 Markdown URL。发送结果确认前保留本地草稿，消息发送失败后的重试复用已上传地址；发送闭包核对服务器、连接代次与投递目标，避免上传期间的导航把图片发给另一个目标。应用关闭后不恢复草稿，图床上的孤立文件由服务端保留策略处理。

## Alternatives considered

- **接入 myTeamSpeak 附件服务**：需要 myTS token 与一次连接边界放行；自托管客户端不做
  myTS 账号是仓库级硬规则。
- **发送侧伪造 `ts.file.myts` JSON**：`file_id` 引用的字节只在 myTS 附件服务里，自托管
  服务器与接收端都取不到，伪造引用没有意义。
- **按 TS3 BBCode 解析富文本**：抓到的样本是 Markdown 风格，按 BBCode 处理会渲染错或把
  标记原样丢给用户。

- **从上传响应读取公开 URL**：可能让服务端响应改变后续抓取目标。公开根地址由用户单独配置，避免将响应内容当成地址授权。
- **在普通 JSON 偏好中保存令牌**：偏好会被备份或复制，认证资料保存在平台安全存储。
- **通过官方媒体服务发送本地图片**：仍依赖 myTS 身份与官方上传服务，不符合自托管规则。

## Consequences

- 官方客户端发来的图片在 FlSpeak 里显示「不支持的图片格式」，这是明确的产品限制。
- 第三方 URL 图片可显示；磁盘 LRU、隐私开关、像素上限尚未接线。
- 显示官方附件需要一次连接边界决策与 myTS 鉴权；当前不做。
- 渲染现状与边界细节见 `docs/images.md` 与 `docs/connection-boundary.md`。

## Related

跨收件人的草稿、选图与上传归属见[异步交互的目标与状态归属](../../implemented/architecture/2026-10-29-ui-async-ownership.md)。
