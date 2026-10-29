# 聊天图片与 TS6 富文本

状态：官方附件显示“不支持的图片格式”占位；第三方 URL 图片支持聊天内显示、媒体墙与全屏查看；用户自配 HTTP PUT 图床支持选图、粘贴图片和发送。富文本渲染覆盖 Markdown 的常用子集。

## 结论先行

1. TS6 官方客户端的图片消息**不是 URL/BBCode**，而是一条 JSON 文本：
   `{"msg_type":"ts.file.myts", ...}`。
2. 图片字节不在自托管服务器上，而在 myTeamSpeak 的附件服务里；官方客户端通过
   `tsclient_internal.tschat_downloadAttachment` 取回。消息里的 `file_id` 只是引用，
   不是可直接访问的 HTTP 地址。
3. 按当前连接边界（不使用 myTeamSpeak 账号体系/官方媒体服务），FlSpeak **不能下载**
   这类图片。现在的实现只解析元数据，显示文件信息占位，不伪造图片。
4. 发送侧同样不能伪造 `ts.file.myts`：官方客户端的发图流程是先上传到 myTS，再发这个
   JSON。FlSpeak 只支持用户自配图床 + URL；官方客户端收到第三方 URL 是否渲染成图片
   仍未验证，见文末互操作门禁。

## 已验证的原始消息

探针抓到的私聊原文（为可读性加了换行，实际是单行）：

```json
{"msg_type":"ts.file.myts","file_id":"eGNoenZrcmFxbWxxdG1iYmNud3puamFqeHZnd2VwbnJ3b2FzdWZ6dWt1bnJ3ZHVzanNmZHBsbWZubmFl","chat_user_id":"@ahho4uvek3l5db3mwajlpv26a4ewuddtmlmhkgbxucetz65d7y2eu===:chat-2.tmspk.net","file_name":"image_1792291789378.png","file_size":69244,"body":"image_1792291789378.png","v2":true}
```

字段：

| 字段 | 含义 |
| --- | --- |
| `msg_type` | 固定 `ts.file.myts` |
| `file_id` | myTS 附件 id；Base64 后是一段 60 字符 slug，不是 URL |
| `chat_user_id` | 发送者的 myTS/聊天身份，形如 `@...:chat-2.tmspk.net` |
| `file_name` / `file_size` | 文件名与字节数 |
| `body` | 官方客户端显示的说明/文件名 |
| `v2` | 当前为 `true` |

官方客户端代码里的对应路径：

```text
收：parse "ts.file.myts" -> attachment
    -> file_cache.download -> tsclient_internal.tschat_downloadAttachment
发：file_cache.upload -> tsclient_internal.myTsFileTransferUpload
    -> sendFile -> 发出同样的 JSON
```

所以“对方发来的图片”与“我们发图”都绕不开 myTeamSpeak 服务，除非改连接边界。

## 边界决策

| 方案 | 行为 | 代价 |
| --- | --- | --- |
| A. 官方图片只占位（当前） | `ts.file.myts` 显示“不支持的图片格式”+文件信息，不下载 | 官方客户端图片看不到；边界不变 |
| B. 只读官方附件 | 为显示官方图片接入 myTS 附件下载 | 需要 myTS 身份/鉴权与官方协议；违反当前“不使用官方媒体服务” |
| C. 第三方 URL/图床 | 用户发 URL；FlSpeak 安全抓取并显示 | 官方客户端是否渲染第三方 URL 仍未验证 |

当前实现选择 A + C：不做 myTS token，不访问官方附件服务；URL 图片独立抓取。官方 `file_id`
永远不进入 URL 抓取器。

## 图片显示

已实现：

- 识别 `ts.file.myts` JSON，解析 `file_name`、`file_size`、`body`、`file_id`；
- 官方附件显示 **“不支持的图片格式”** 卡片和文件信息，不发网络请求；
- 解析失败或普通文本时按原文显示，不吞消息；
- 原始 JSON 仍原样进历史。

URL 图片已实现：

- 识别 TS6 Markdown `![alt](https://...)`、TS3 风格 `[img]https://...[/img]`、整行裸图片
  URL（扩展名 png/jpg/jpeg/gif/webp/avif）；普通链接不抓取。
- Dart `MessageContent` 通过 FFI `fetchImage(url)` 取字节，Rust 侧
  `core/session/src/images.rs` 做校验与抓取。
- 校验：只允许 http/https、拒绝凭据、拒绝 `proto::forbidden_host` 命中的官方主机、
  拒绝 localhost/私网/链路本地/组播/CGNAT/IPv4-mapped IPv6；DNS 解析后逐个检查并
  固定到选中的公网地址（降低 DNS rebinding）。
- 限制：最多 3 次重定向，每一跳重新校验；15s 超时；20 MiB 上限；content-type 必须
  `image/*` 或字节 magic 命中 PNG/JPEG/GIF/WebP/AVIF；失败显示“图片加载失败”和 URL。
- 聊天缩略图、媒体墙与全屏查看器共用 `remoteImageProvider`，通过 Rust 抓取图片，按 URL 合并可见视图的请求；视图全部离开后释放字节。失败状态提供原地重试，普通重建不自动重试。
- 图片请求不使用环境 HTTP 代理，DNS 校验后的全部公网地址用于连接重试；DNS、重定向与读取合计受 15s 超时限制。透明网卡代理可继续使用。
- fake-IP DNS 返回的 `198.18.0.0/15` 地址仍被拒绝；使用 FlClash 等代理时，在其 fake-IP 过滤列表中加入需要加载的图片域名，使其返回真实地址。重定向后的图片域名也需满足同一条件。
- 全屏查看器支持打开、前后翻页和关闭；图片文件名按 URL 路径规则解码一次。

未实现：

- 磁盘 LRU 缓存、隐私开关、查看器缩放与保存；
- 解码后像素上限（目前只有 20 MiB 传输上限，仍有解压炸弹风险）；
- EXIF 清理（显示的是原始字节，未写回磁盘）；

## 图片上传与发送

在设置页的“图片上传”，或聊天输入框图片菜单里，填写 HTTP PUT 上传根地址、公开访问根地址与可选 Bearer token。三个值保存在平台安全存储，普通偏好与消息历史不保存令牌。没有图床时仍可手动发送公网图片 URL。

上传接口接收 `PUT <上传根地址>/<随机文件名>`，请求体是原始图片字节，`Content-Type` 按 PNG/JPEG/GIF/WebP/AVIF 的字节特征确定。配置 token 时附加 `Authorization: Bearer <token>`。服务端返回任意 2xx 即为成功；客户端从公开根地址和相同文件名生成图片 URL，不读取响应正文或重定向地址。

例如上传根地址 `https://images.example.com/upload/`、公开根地址 `https://images.example.com/images/`：图床把 `/upload/<文件名>` 的 PUT 内容保存为 `/images/<文件名>`，并允许接收方通过 GET 访问公开路径。S3 签名、multipart 表单与返回 JSON URL 的接口尚未接线，需要由自托管服务适配上述 PUT 接口。

上传根地址与公开根地址只接受无凭据、查询参数和片段的 HTTPS URL；本机开发允许 loopback HTTP。两者都检查官方主机清单。上传使用随机文件名、20 MiB 上限与 60 秒超时，不使用环境 HTTP 代理，不跟随重定向。图床配置由用户直接填写；聊天消息不能更改上传目标。

聊天图片菜单提供选图、粘贴图片和图床配置。选图或粘贴后显示预览，可移除，再与文字一起发送。发送顺序是上传图片、发送 `![](<公开 URL>)`、等待服务器确认。消息发送失败会保留草稿，重试复用已上传地址；上传期间切换服务器、连接代次或投递目标会中止发送并保留草稿。粘贴图片通过菜单操作，普通文本粘贴不受影响。

接收方仍按图片抓取规则校验公开 URL，因此私网公开地址无法在聊天中显示。图床需向接收方提供公网 HTTPS 地址；loopback HTTP 仅用于接口开发测试。客户端不部署图床、不清理孤立上传文件，也不伪造官方 `ts.file.myts` 附件。

## TS6 富文本

用户实测的 TS6 消息是 Markdown 风格，不是 TS3 BBCode。已支持的子集：

| 语法 | 渲染 |
| --- | --- |
| `**bold**` / `*italic*` | 粗体 / 斜体 |
| `~~strike~~` / `++underline++` | 删除线 / 下划线 |
| `==highlight==` | 高亮背景 |
| `` `code` `` / ``` 围栏 | 行内/块级等宽 |
| `[text](url)` / 裸 URL | 链接样式（暂不打开） |
| `# heading` / `> quote` | 标题 / 引用 |
| `- item` / `1. item` | 列表 |
| `| a | b |` | 表格 |
| `:::details` / `:::left` | 折叠块 / 左对齐块 |
| `$math$` | 等宽斜体（不计算） |
| `||spoiler||` | 隐藏文本（暂不能点击揭示） |
| `:+1:` 等 | 少量 emoji 短码 |

未支持/降级：脚注 `[^x]`、完整数学排版、mermaid 渲染、嵌套复杂列表、链接点击。
原始文本仍完整保留；渲染器只影响 UI，不影响历史与转发。

## 互操作门禁

- [x] TS6 原始图片消息格式；
- [x] 官方附件元数据解析 + “不支持的图片格式”占位；
- [x] 第三方 URL 图片抓取（Rust 校验 + FFI）；
- [ ] 官方附件实际下载（不做 token，已放弃）；
- [ ] 第三方 URL 磁盘缓存/隐私开关/像素上限；
- [ ] 官方客户端收到第三方 URL 后是否渲染为图片；
- [ ] 官方客户端发图时 `file_id` 是否有过期/权限语义；
- [x] HTTP PUT 图床配置、平台安全存储、选图与粘贴发送。

## 后台门禁

格式门禁已关闭。用户已明确不走 myTS token：官方附件只显示“不支持的图片格式”，
URL 图片走独立抓取，发送使用用户配置的自托管 HTTP PUT 图床。
