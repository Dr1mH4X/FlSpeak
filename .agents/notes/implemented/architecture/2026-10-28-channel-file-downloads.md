# Agent Note: 频道文件下载的暂存发布与跨平台回退

Status: implemented

## Problem

频道文件下载走独立明文 TCP 连接，传输期间可能断线、重连或收到不完整响应，用户也可能在下载进行中切换工作区页签。直接向目标路径流式写入会在传输中断时留下半截文件，也会在调用方重用路径时覆盖已有文件。

用 `hard_link` 从同目录 `.part` 暂存文件发布到目标路径可以在 POSIX 与桌面文件系统上原子地拒绝覆盖已有文件，但 Android 应用沙箱的 SELinux 规则（`untrusted_app` 域禁止 `link(2)`）以及部分 FUSE / FAT 挂载点会以 `PermissionDenied` 或 `Unsupported` 拒绝硬链接，只靠 `hard_link` 会使完整下载在最后一步失败。

## Decision

- `core/session` 的下载任务先在目标同目录创建独占 `.flspeak-<random>.part` 暂存文件，经 `tsclient_rs::downloadFileData` 校验完整声明字节数并 `sync_all` 落盘，并与连接代次取消信号竞争；断线或重连立即中止传输并删除暂存文件。
- 暂存文件发布优先调用 `tokio::fs::hard_link`：硬链接成功时目标路径原子生效且保证不覆盖已有文件，随后删除 `.part` 暂存名；若硬链接因 `AlreadyExists` 失败，直接拒绝覆盖并清理暂存文件。
- 当 `hard_link` 因权限或文件系统不支持（非 `AlreadyExists` 错误）失败时，先用 `try_exists` 复核目标路径不存在，再回退为同目录 `tokio::fs::rename` 原子改名发布；清理阶段对已改名移走的 `.part` 忽略 `NotFound`。
- Dart 侧由 `SessionController.saveChannelFile` 先下载到独立临时子目录，完整落盘后再交由桌面保存对话框或 Android MediaStore 导出，并在 `SessionView.activeFileDownloads` 按 `(connectionEpoch, channelId)` 记录进行中的下载；工作区在消息、媒体、文件页签之间切换不会丢失下载进度或放开重复并发下载。

## Alternatives considered

- **直接向最终导出路径流式写入**：传输中断、断线或声明长度不符时会在用户可见目录留下残缺文件，且无法在导出前做字节完整性校验。
- **只用 `hard_link` 不设回退**：Android SELinux 对应用沙箱文件禁止 `link(2)`，即使下载字节已完整写入临时目录，发布阶段也会恒定报错。
- **一律直接 `rename` 而不先试 `hard_link`**：POSIX 上同目录 `rename` 默认静默覆盖同名目标文件；优先 `hard_link` 能在支持硬链接的桌面文件系统上保留内核级不覆盖保证。
- **把下载状态放在 `ChannelFilesPane` 的局部 `State` 中**：工作区页签通过 `AnimatedSwitcher` 切换时会销毁文件页组件，切回后进度条消失且下载按钮重新可点，允许重复发起同一频道的并发下载。

## Consequences

- 桌面与 Android 共用同一套 Rust 暂存下载实现，Android 沙箱或不支持硬链接的文件系统自动走 `try_exists` + `rename` 回退路径。
- 进行中的下载生命周期归属 `SessionController`，切换页签保持进度显示与按钮禁用状态，断线或换服仍通过连接代次取消底层 TCP 传输并清理临时目录。

## Testing

- `core/session` 的 `downloads::tests` 覆盖完整下载发布、已有目标保护、截断响应清理、连接代次变化取消，以及 `hard_link` 被拒绝时的 `rename` 回退与防覆盖检查。
- `lib/features/workspace/widgets/channel_files_pane_test.dart` 覆盖密码保护目录浏览、页签卸载再挂载期间的下载进度保留、完整导出与临时目录清理。
