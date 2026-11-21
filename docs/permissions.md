# 平台权限与访问边界

本文定义 FlSpeak 在各操作系统宿主层的系统权限声明、运行时授权时机与最小权限原则。

## 权限清单与平台声明

客户端严格遵循最小权限原则（Principle of Least Privilege），仅在提供实时音频、网络通信、文件交互与桌面全局按住说话必需时声明并请求系统权限。

| 权限类别 | macOS | Android | Linux / Windows | 说明 |
| --- | --- | --- | --- | --- |
| **音频录制** | `NSMicrophoneUsageDescription`、`com.apple.security.device.audio-input` | `android.permission.RECORD_AUDIO` | 系统音频设备访问（PulseAudio/PipeWire/ALSA/WASAPI） | 仅在用户进入语音频道并启动麦克风推流时按需使用 |
| **网络通信** | `com.apple.security.network.client`、`com.apple.security.network.server`（App Sandbox，授权出站连接与本地 UDP 端口 `bind`） | `android.permission.INTERNET` | 标准系统套接字 | 用于连接自托管 TeamSpeak 服务器（UDP 语音/命令与 TCP 文件传输） |
| **文件读写** | `com.apple.security.files.user-selected.read-write` | Android 10+ 范围化存储（MediaStore API） | 操作系统标准文件选择器 | 导出频道文件或保存下载内容时通过用户主动选择的文件/目录进行交互 |
| **全局快捷键（输入监控）** | App Sandbox 下以 Listen-Only `CGEventTap` 监听物理键码，依赖「输入监控」（Input Monitoring）运行时授权 | 不支持全局监听，仅应用内按键与触控按住说话 | 纯 X11 使用 XInput2 被动原始按键监听；Wayland / XWayland 通过 `org.freedesktop.portal.GlobalShortcuts` 请求桌面全局快捷键（不可用时退回应用内）；Windows 使用低级键盘钩子 `WH_KEYBOARD_LL` | 只观察目标按住说话键；未授权或平台受限时自动降级为应用内监听 |

## 运行时请求与访问边界

- **按需索取**：应用启动时不强制预先索取麦克风硬件权限；只有当用户触发需要麦克风输入的操作（如首次连接进入需要语音发送的频道或测试麦克风）时，才触发系统级权限弹框。
- **探针与无音频隔离**：自动化集成测试、网络探针以及真实图标渲染探测等无语音场景，必须通过 FFI 构造器显式关闭音频采集（`with_audio: false`），严禁触发系统麦克风权限请求。
- **存储权限降级**：Android 端避免声明全盘文件访问权限（如 `MANAGE_EXTERNAL_STORAGE`），一律使用 MediaStore API 导出文件至下载目录，保障用户隐私与合规性。
- **权限拒绝处理**：用户拒绝授予麦克风权限时，仅禁用音频采集发送，接收端播放与文字聊天、频道浏览功能保持正常可用，并通过应用内通知中心（`NoticeCenter`）提示权限缺失。
- **macOS 输入监控按需授权与探测**：`macos/Runner/MainFlutterWindow.swift` 在保留 `com.apple.security.app-sandbox` 的前提下通过 `CGEvent.tapCreate(..., options: .listenOnly, ...)` 注册全局按键观察，不吞掉其他应用的按键输入；注册及切回前台或打开设置页重试时直接试探 `CGEvent.tapCreate`（仅在返回 `nil` 后用 `CGPreflightListenEventAccess()` 区分 `permissionDenied` 与其他失败，避免进程内 TCC 缓存短路导致用户在系统设置授权后无法立即生效）。系统不会在应用启动时主动弹窗请求输入监控权限，仅在用户主动开启按住说话或点击设置页授权按钮时调用 `CGRequestListenEventAccess()`，并支持通过 `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` 跳转系统设置「输入监控」面板；未授权期间全局按住说话自动降级为应用内按键兜底，并在状态展示区与 `NoticeCenter` 提示授权状态。
