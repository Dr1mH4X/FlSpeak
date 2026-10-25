# Agent Note: 音频帧不过 FFI

Status: implemented

## Problem

TeamSpeak 语音是 48kHz 立体声、20ms 一帧。一个 8 人频道意味着每秒约 350~400 次编解码，
如果音频数据走 flutter_rust_bridge，每秒会有几百次跨语言调用与拷贝，UI isolate 直接被
拖垮，而且 Dart 侧还需要维护每个说话人的解码器状态与抖动缓冲。

## Decision

- 音频路径完全留在 Rust：`core/audio` 负责采集、Opus 编解码、播放；`core/session` 的
  actor 负责收发语音包。
- FFI 只暴露 UI 需要的事件（连接状态、频道、成员、文字消息、提示），音频一个字节都不传。
- 编码器单例（出站），解码器按说话人独立（Opus 解码器有状态）。
- 出站按 20ms 节拍送，说话人队列有上限，满了丢最旧的帧，并记 `dropped_frames` 计数。

## Alternatives considered

- **音频帧过 FFI，在 Dart 解码与混音**：每秒几百次跨语言调用与拷贝拖垮 UI isolate，每个
  说话人的解码器状态与抖动缓冲还要在 Dart 侧再养一份。
- **可视化时把原始帧作为例外传过 FFI**：在边界上开口子，「音频不过 FFI」就不再是不变量；
  波形/电平要做也走低频（≤10Hz）聚合指标这种新的轻量事件。

## Consequences

- 界面拿不到波形/电平之类的实时数据。
- `audio` 默认不进产物；`plugins/flspeak_ffi` 打开 `audio` feature 后，应用构建需要 Opus
  工具链，见 `docs/audio.md` 与 `docs/development.md` 的 macOS 构建细节。
- 重排序与抖动缓冲受限：tsclient-rs 的 `VoiceData` 丢掉了包号。后续取舍见
  [双线程全双工语音](../../implemented/architecture/2026-10-18-full-duplex-audio.md)。
