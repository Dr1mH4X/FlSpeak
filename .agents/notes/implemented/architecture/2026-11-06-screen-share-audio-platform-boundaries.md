# Agent Note: 屏幕共享音频传输平台边界与 macOS 暂时排除

Status: implemented

## Problem

TeamSpeak 6 官方客户端在接收屏幕共享时，通过 WebRTC 协商获取远端音视频轨道。屏幕共享时将音频一并传输能够提供完整的直播或协作体验，但各操作系统底层音频捕获接口与 `flutter_webrtc` 原生实现的能力差异极大：

1. **macOS 限制**：macOS 13+ 的 `ScreenCaptureKit` 虽原生支持音频录制与 `excludesCurrentProcessAudio`，但 `flutter_webrtc` 的 Darwin 原生捕获层（`FlutterScreenCaptureKitCapturer.m`）仅实现了视频采集，未实现音频样本回调与音轨转发，导致通过 `getDisplayMedia` 无法捕获任何音轨。
2. **Android 限制**：Android 虽在系统层支持 `AudioPlaybackCapture`，但 `flutter_webrtc` 的 Android 原生层在 `getDisplayMedia` 中未实现音频流捕获，音轨列表硬编码返回空。
3. **Linux 现状**：编译支持 `libpulse` 时，可通过 PulseAudio / PipeWire 的 monitor source 实现全系统内录，但不支持按进程/窗口隔离音频，也无法排除当前应用本身。
4. **Windows 现状**：内置 `ApplicationLoopbackCapturer`，支持基于窗口 HWND 转换为目标 PID 捕获单应用音频，亦支持全系统内录。

若在全平台上盲目暴露无差别的系统声音捕获开关，会导致在不支持的平台上产生虚假承诺，或在缺少真实音轨时发送空载 WebRTC 轨道触发官方客户端异常。

## Decision

- **明确平台支持边界**：仅在 Windows 与 Linux 上启用屏幕共享声音捕获能力；macOS、Android、iOS 等平台暂不启用音频采集，自适应降级为纯视频共享。
- **默认行为与零额外开关**：屏幕共享传输声音作为开箱即用的默认行为，UI 弹窗不增加多余的手动开关，保持源选择交互简洁；发起共享时由客户端根据当前运行平台自动决定是否请求音频内录约束。
- **协议兼容占位**：当屏幕共享未启用音频（例如在 macOS/Android 平台运行时），`stream_publisher` 保持严格 MID 顺序，向 TS6 观众端发送空的 `SendOnly` 音频 transceiver 占位，满足 TS6 对 SDP 结构（`MID 0 = video, MID 1 = audio`）的严格协商规范，同时上报 `audio: false`，避免接收端等待不存在的音频流。
- **macOS 后续推进前置条件**：若未来要在 macOS 上启用屏幕共享音频，需在插件层或原生扩展中实现 `SCStreamOutputTypeAudio` 监听，将 PCM 音频帧输入到 WebRTC 的 `RTCAudioSource`，并在配置中启用 `excludesCurrentProcessAudio = YES` 以防止频道语音回声回路。当前阶段不修改 `flutter_webrtc` 源码，维持外部依赖整洁。

## Alternatives considered

- **在弹窗中增加显式音频开关**：屏幕共享传送应用或系统声音属于绝大多数用户的预期默认行为，额外增加设置项增加了决策负担，且在不支持的平台上展示开关会产生虚假预期；将其定为默认行为由底层自适应更符合整体体验。
- **修改 `plugins/flutter_webrtc` 原生源码补充 macOS SCK Audio 实现**：维护自定义 fork 会显著增加 upstream 升级维护成本，且在 iOS/macOS 双端构建工具链带来额外复杂度。
- **将麦克风与系统内录混流后送入 WebRTC**：TeamSpeak 语音通话已通过 `core/audio` 的独立 UDP 链路传输，屏幕共享音频若混入麦克风会导致频道内所有用户听到重复且带有延迟的双重语音。

## Consequences

- Windows 与 Linux 端在用户发起屏幕共享时默认尝试捕获并传输音频（Windows 单窗口精准内录，Linux 默认监听内录）。
- macOS 与 Android 端自动保持静音纯视频共享，WebRTC 协商与信令优雅兼容，不崩溃且不抛出未决音轨。
- WebRTC 协商保持对 TeamSpeak 6 官方原生客户端的一致兼容性。
