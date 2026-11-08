# 平台权限与访问边界

本文定义 FlSpeak 在各操作系统宿主层的系统权限声明、运行时授权时机与最小权限原则。

## 权限清单与平台声明

客户端严格遵循最小权限原则（Principle of Least Privilege），仅在提供实时音频、网络通信与文件交互必需时声明并请求系统权限。

| 权限类别 | macOS | Android | Linux / Windows | 说明 |
| --- | --- | --- | --- | --- |
| **音频录制** | `NSMicrophoneUsageDescription`、`com.apple.security.device.audio-input` | `android.permission.RECORD_AUDIO` | 系统音频设备访问（PulseAudio/PipeWire/ALSA/WASAPI） | 仅在用户进入语音频道并启动麦克风推流时按需使用 |
| **网络通信** | `com.apple.security.network.client`（App Sandbox） | `android.permission.INTERNET` | 标准系统套接字 | 用于连接自托管 TeamSpeak 服务器（UDP 语音/命令与 TCP 文件传输） |
| **文件读写** | `com.apple.security.files.user-selected.read-write` | Android 10+ 范围化存储（MediaStore API） | 操作系统标准文件选择器 | 导出频道文件或保存下载内容时通过用户主动选择的文件/目录进行交互 |

## 运行时请求与访问边界

- **按需索取**：应用启动时不强制预先索取麦克风硬件权限；只有当用户触发需要麦克风输入的操作（如首次连接进入需要语音发送的频道或测试麦克风）时，才触发系统级权限弹框。
- **探针与无音频隔离**：自动化集成测试、网络探针以及真实图标渲染探测等无语音场景，必须通过 FFI 构造器显式关闭音频采集（`with_audio: false`），严禁触发系统麦克风权限请求。
- **存储权限降级**：Android 端避免声明全盘文件访问权限（如 `MANAGE_EXTERNAL_STORAGE`），一律使用 MediaStore API 导出文件至下载目录，保障用户隐私与合规性。
- **权限拒绝处理**：用户拒绝授予麦克风权限时，仅禁用音频采集发送，接收端播放与文字聊天、频道浏览功能保持正常可用，并通过应用内通知中心（NoticeCenter）提示权限缺失。
