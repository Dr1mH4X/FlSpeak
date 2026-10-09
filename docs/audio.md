# 音频

## 目标形态

```text
麦克风 ──cpal──> f32/i16/u16 交错样本 ──> 20ms 分帧 ──> Opus 编码 ──> 语音包 ──> actor
actor ──> 语音包 ──> 按说话人解码（各自持有 OpusDecoder）──> 说话人队列 ──> 混音 ──> cpal 播放
```

- 采样格式统一到 48kHz 立体声（`OPUS_PCM`），语音帧 20ms = 每声道 960 样本 = 交织 1920 样本。
- 语音包 codec 字段 4（语音）、5（音乐），与 TeamSpeak 的约定一致。
- 编码器单例；解码器**按说话人独立**，因为 Opus 解码器带状态。
- 出站码率 128kbps，出站按 20ms 节拍推送。
- 说话人队列有上限，满了丢最旧帧并累加 `dropped_frames`，避免内存无界增长。

## 已实现

`core/audio`：

| 模块 | 内容 |
| --- | --- |
| `format.rs` | `AudioFormat`、`OPUS_PCM`、帧长常量、codec 常量 |
| `codec.rs` | `OpusEncoder` / `OpusDecoder`（`MAX_PACKET_BYTES = 1500`） |
| `queue.rs` | `TalkerQueues`：每个说话人的有界 FIFO 与丢帧计数 |
| `device.rs` | `input_devices()` / `output_devices()`、`start_capture` / `start_playback`、F32/I16/U16 分派、错误槽 |

单测覆盖编解码往返、丢包隐藏、队列丢帧策略；设备枚举需要在真机上验证。

## 尚未接线

`audio` 现在**没有**接进 `session`：既不发送也不接收语音。达成接线需要：

1. actor 注册唯一的语音处理器，把收到的包按 `client_id` 分发到说话人队列；
2. 启动出站节拍：采集 → 编码 → `Client::send_voice`；
3. 播放侧把各说话人队列混音后写进 `PlaybackHandle`；
4. 在 `plugins/flspeak_ffi/rust/Cargo.toml` 打开 `audio` 的 `audio` feature，
   让 cpal/audiopus 真正进入产物；
5. 补 `docs/` 与 `.agents/notes/implemented/` 的接线记录。

`tsclient-rs` 的 `VoiceData` 丢掉了包号，所以现在无法做重排序与抖动缓冲；这是上游候选
改动（见 `compliance.md`）。

## 保持音频不过 FFI

FFI 只送 UI 事件。8 人频道每秒约 350~400 次编解码，如果音频数据过桥，每秒同样次数的跨
语言调用会直接压垮 UI isolate，并且需要在 Dart 里维护解码器状态。决策记录：
`.agents/notes/implemented/2026-10-08-audio-boundary.md`。

## 依赖与构建

`audio` feature 拉 `cpal` 与 `audiopus`（后者经 `audiopus_sys` 绑定 Opus）：

```sh
# 优先用系统 Opus
brew install opus pkgconf                 # macOS
sudo apt-get install -y libopus-dev libasound2-dev   # Debian/Ubuntu

# 系统没有 Opus 时会源码构建，需要放宽内置 CMakeLists 的版本下限
CMAKE_POLICY_VERSION_MINIMUM=3.5 cargo test -p audio --features audio
```

这套依赖只在打开 feature 时才会编译，所以日常 `flutter build` 与桌面 CI 不需要音频工具链。

## 平台权限

| 平台 | 已经配好的东西 |
| --- | --- |
| macOS | `Info.plist` 的 `NSMicrophoneUsageDescription` / `NSLocalNetworkUsageDescription`；Debug 与 Release entitlements 里的 `audio-input`、`network.client` |
| Android | `RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS`、`INTERNET` |
| Windows / Linux | 无需额外声明 |