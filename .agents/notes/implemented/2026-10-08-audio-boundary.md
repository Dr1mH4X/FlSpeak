# 决策记录：音频帧不过 FFI

日期：2026-10-08
状态：已实施（2026-10-18 已接进 actor，见 2026-10-18-full-duplex-audio.md）

## 背景

TeamSpeak 语音是 48kHz 立体声、20ms 一帧。一个 8 人频道意味着每秒约 350~400 次编解码，
如果音频数据走 flutter_rust_bridge，每秒会有几百次跨语言调用与拷贝，UI isolate 直接被拖垮，
而且 Dart 侧还需要维护每个说话人的解码器状态与抖动缓冲。

## 决策

- 音频路径完全留在 Rust：`core/audio` 负责采集、Opus 编解码、播放；
  `core/session` 的 actor 负责收发语音包。
- FFI 只暴露 UI 需要的事件（连接状态、频道、成员、文字消息、提示），音频一个字节都不传。
- 编码器单例（出站），解码器按说话人独立（Opus 解码器有状态）。
- 出站按 20ms 节拍送，说话人队列有上限，满了丢最旧的帧，并记 `dropped_frames` 计数。

## 后果

- 界面拿不到波形/电平之类的实时数据。真要做可视化，走“低频（≤10Hz）聚合指标”这一条新
  的轻量事件，而不是搬音频帧。
- `audio` 默认不进产物；2026-10-18 接进 actor 时 `plugins/flspeak_ffi` 已打开
  `audio` feature，应用构建因此需要 Opus 工具链，见 `docs/audio.md`。
- 现在无法做重排序与抖动缓冲：tsclient-rs 的 `VoiceData` 丢掉了包号。候选上游改动见
  `.agents/notes/implemented/2026-10-18-full-duplex-audio.md`。
