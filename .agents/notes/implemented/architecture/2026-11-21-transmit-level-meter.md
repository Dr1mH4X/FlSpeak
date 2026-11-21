# Agent Note: 发送侧电平

Status: implemented

## Problem

用户卡的电平条跟随本端麦克风时，读数来自设备原始 PCM，位于重采样、RNNoise 降噪与 PTT/VAD 门控之前。PTT 未按下、VAD 判定静音、或已连接但未进入频道时，波形仍随环境声跳动；这些声音没有发往服务器。界面需要表达「现在有什么声音被发出去」。

## Decision

- `core/audio` 的采集线程只在非 EOS 语音包离开时更新发送电平，样本取自 `CapturePipeline::last_encoded_pcm`，因此包含降噪、PTT/VAD 门控、淡入淡出、pre-roll 与收尾尾帧。
- `TransmitMeter` 保存最近一次发包时刻与平滑后的电平。采集线程为 10ms tick、Opus 为 20ms 帧，帧间没有产包的 tick 保持读数；超过 `TRANSMIT_METER_HOLD`（一个 20ms 帧加一个 10ms tick）没有新包、收到 EOS、停采、静音或聋听时立即归零。
- `SharedMeter` 继续只跨 FFI 传 0–1 标量；播放线程按 20ms 节拍合成两路电平。电平发布仍然不等待协议 actor。
- Dart 的 `VoiceActivityRibbon` 在麦克风源上增加「已进入频道」门槛；未进频道或进出频道时清空历史并显示平直。接收源保持原行为。
- 设置项文案改为「发送音频 / Outgoing audio」，枚举 `VoiceMeterSource.microphone` 不变。

## Alternatives considered

- **持续显示降噪后的输入**：能看到麦克风是否工作，但 PTT 松开与 VAD 静音时仍会出现未发送的波形，与本决策目标冲突。
- **由 actor 确认每包发送后再更新电平**：最贴近服务器实际收到的内容，但 actor 或网络繁忙时电平会停住，破坏既有的「电平不等待 actor」投递决策；未进频道已经在界面层排除。
- **继续测原始输入并在界面按 PTT/VAD 状态遮盖**：门控状态由 Rust 掌握，界面复制一份会漂移，也绕过了降噪后的真实发送内容。
- **为发送电平另开 FFI 流**：两个标量继续复用既有事件流即可，独立接口没有对应收益。

## Consequences

- 波形与发送内容一致：门打开且降噪后有底噪时显示底噪，门关闭、无包或超过帧周期时显示平直。
- PTT 短按不会因立即清屏而闪断；电平归零后，界面约 480ms 的历史自然滑出。
- 不再提供原始输入监视；检查麦克风是否工作需要在门打开的发送路径下观察。
- 未进频道时发送源恒为平直，接收源仍按连接状态显示。

## Testing

- `core/audio` 的 `level` 测试覆盖帧间保持、超过帧周期归零、EOS 立即归零与连续说话不闪烁。
- `core/audio` 的 `engine` 测试覆盖发送包驱动电平、PTT 松开后无包时原始输入不再影响读数。
- `VoiceActivityRibbon` 的像素测试覆盖未进频道时发送源平直、接收源继续渲染，以及进出频道清空历史。

## Related

[实时电平发布](2026-10-29-realtime-voice-levels.md)持有刷新节拍与投递方式；[用户卡电平条与可选声源](../feature/2026-10-26-voice-meter-ribbon.md)持有界面取舍；[音频帧不过 FFI](2026-10-08-audio-boundary.md)持有样本隔离规则。
