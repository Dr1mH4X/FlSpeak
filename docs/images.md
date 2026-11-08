# 聊天图片与 TS6 富文本

官方附件显示“不支持的图片格式”占位；第三方 URL 图片支持聊天内显示、媒体墙与全屏查看；用户自配 HTTP PUT 图床支持选图、粘贴图片和发送。富文本渲染覆盖 Markdown 的常用子集。

## 格式与传输机制

1. TS6 官方客户端的图片消息不是 URL/BBCode，而是一条 JSON 文本：`{"msg_type":"ts.file.myts", ...}`。
2. 图片数据不在 TeamSpeak 服务器上，而在 myTeamSpeak 的附件服务里；官方客户端通过 `tsclient_internal.tschat_downloadAttachment` 取回。消息里的 `file_id` 只是引用，不是可直接访问的 HTTP 地址。
3. 依据自托管连接边界（不接入 myTeamSpeak 账号体系与官方媒体服务），FlSpeak 解析其元数据并显示文件信息占位，不发起官方附件下载。
4. 发送侧同样不伪造 `ts.file.myts`：官方发图依赖 myTS 上传；FlSpeak 提供用户自配 HTTP PUT 图床与直接发送公开图片 URL 机制。相关决策见 [.agents/notes/implemented/architecture/2026-10-18-ts6-attachments.md](../.agents/notes/implemented/architecture/2026-10-18-ts6-attachments.md)。

## 抓包原始消息示例

探针捕获的 TS6 私聊原文结构：

```json
{"msg_type":"ts.file.myts","file_id":"eGNoenZrcmFxbWxxdG1iYmNud3puamFqeHZnd2VwbnJ3b2FzdWZ6dWt1bnJ3ZHVzanNmZHBsbWZubmFl","chat_user_id":"@ahho4uvek3l5db3mwajlpv26a4ewuddtmlmhkgbxucetz65d7y2eu===:chat-2.tmspk.net","file_name":"image_1792291789378.png","file_size":69244,"body":"image_1792291789378.png","v2":true}
```

| 字段 | 含义 |
| --- | --- |
| `msg_type` | 固定为 `ts.file.myts` |
| `file_id` | myTS 附件标识；Base64 解码后为 60 字符 slug，非直接 HTTP URL |
| `chat_user_id` | 发送者的 myTS 聊天网络身份（形如 `@...:chat-2.tmspk.net`） |
| `file_name` / `file_size` | 文件名与字节长度 |
| `body` | 说明文本/文件名 |
| `v2` | 协议版本标识，当前为 `true` |

官方附件标识 `file_id` 绝不进入 URL 抓取器。

## 图片显示

- 识别 `ts.file.myts` JSON 并提取 `file_name`、`file_size`、`body`；展示“不支持的图片格式”占位卡片与文件尺寸信息，不发出任何网络请求；原始 JSON 完整写入本地聊天历史。
- 识别 TS6 Markdown `![alt](https://...)`、TS3 风格 `[img]https://...[/img]` 以及整行图片链接（扩展名 png/jpg/jpeg/gif/webp/avif）。普通链接保持纯文本样式，不预抓取。
- Dart `MessageContent` 通过 FFI `fetchImage(url)` 请求字节，由 Rust 侧 `core/session/src/images.rs` 执行安全校验与抓取。
- 安全校验：仅允许 http/https 协议；拒绝携带凭据；拒绝 `proto::forbidden_host` 官方主机；拒绝 localhost、私有主机名（.local/.lan/.internal）、私网地址、链路本地与 CGNAT 网段；DNS 解析后固定到公网 IP 发起请求，防御 DNS 重绑定。
- 抓取限制：最多跟随 3 次重定向（逐跳重新执行 SSRF 校验）；15 秒全局超时；20 MiB 响应体积上限；`Content-Type` 必须为 `image/*` 或文件头特征匹配 PNG/JPEG/GIF/WebP/AVIF。
- 代理与透明网关适配：支持系统代理与环境变量代理；检测到代理时交由远端代理进行 DNS 解析以避免本地污染。允许 RFC 2544 保留网段 `198.18.0.0/15`（TUN/fake-IP 网关），满足透明代理抓取需求，同时严格拦截真实局域网与环回私网。
- 聊天缩略图、媒体墙与全屏查看器共享 `remoteImageProvider` 缓存，按 URL 合并并发请求并在全部离开视图后释放内存。

尚未接线能力：磁盘 LRU 缓存、解码后最大像素上限限制与客户端 EXIF 剥离。

## 图片上传与发送

在设置页或聊天输入框菜单中配置 HTTP PUT 上传根地址、公开访问根地址与可选 Bearer token。配置保存在操作系统安全存储（Secure Storage）中，不落盘至普通偏好或聊天历史文件。

- 客户端通过 `PUT <上传根地址>/<随机文件名>` 发起原始图片二进制上传，`Content-Type` 根据图片文件头特征自动推导。配置 token 时自动附带 `Authorization: Bearer <token>` 请求头。
- 服务端响应 2xx 状态码视为上传成功；客户端根据公开访问根地址与同一随机文件名拼装公开访问 URL，不解析服务端响应正文或重定向。
- 上传根地址与公开访问根地址只接受无凭据、查询参数和片段的 HTTPS URL（本地回环开发允许 HTTP），并强制校验官方主机黑名单。上传超时为 60 秒，限制 20 MiB。
- 聊天图片发送流程：选图或粘贴 → 生成缩略预览 → 上传图片 → 提交 `![](<公开 URL>)` 文本消息至服务器 → 确认成功后清空草稿。上传失败保留草稿供重试。

## TS6 富文本支持矩阵

| 语法 | 渲染行为 |
| --- | --- |
| `**bold**` / `*italic*` | 粗体 / 斜体 |
| `~~strike~~` / `++underline++` | 删除线 / 下划线 |
| `==highlight==` | 高亮背景色 |
| `` `code` `` / ` ``` ` 围栏 | 行内等宽代码 / 独立代码块 |
| `[text](url)` / 裸 URL | 链接文本样式 |
| `# heading` / `> quote` | 标题 / 引用块 |
| `- item` / `1. item` | 无序与有序列表 |
| `| a | b |` | Markdown 表格 |
| `:::details` / `:::left` | 折叠展示块 / 左对齐块 |
| `$math$` | 等宽斜体排版 |
| `||spoiler||` | 隐藏防剧透文本 |
| `:+1:` 等 | 基础 Emoji 短码映射 |

原始文本在收到和发送时均原样保留；富文本渲染仅作用于展示层，不破坏聊天历史原文。
