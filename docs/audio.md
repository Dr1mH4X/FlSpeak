# 音频

## 目标形态

```text
麦克风 ──cpal──> ArrayQueue ──> capture 线程
  设备格式 → 48k 目标声道 → VAD/PTT → 20ms Opus → VoicePacer → actor
actor ──> Client::send_voice(data, codec)          （发送仍由 actor 独占）

on_voice_data ──有界通道──> playback 线程
  每说话人 jitter buffer → Opus 解码（120ms 缓冲）→ 10ms 混音 → 软削波
  → 48k 立体声 → 设备格式 → ArrayQueue ──cpal──> 扬声器
```

- 48kHz 为内部采样率；codec 4（Opus Voice）上行单声道，codec 5（Opus Music）
  上行立体声；下行统一按立体声解码。
- **频道 codec 决定编码器**：TS3 的 codec 是频道属性，不是客户端全局配置。进 codec 4
  频道用单声道 Voip 编码器，进 codec 5 频道重建为立体声 Audio 编码器。Opus 不支持
  中途切声道数，切频道必须重建 encoder。
- 全双工边界是两条独立线程：采集/编码/发送与接收/解码/混音/播放互不阻塞。cpal 回调
  只做 `ArrayQueue` 的 push/pop，零分配、零锁；编码、解码、混音都在工作线程。

## 线程

| 线程 | 职责 |
| --- | --- |
| `session` actor | 独占 `Client`；所有协议调用串行；`send_voice` 也在这里 |
| `voice-capture` | cpal 输入流、格式转换、VAD/PTT、20ms 分帧、Opus 编码、发送节拍 |
| `voice-playback` | cpal 输出流、每说话人 jitter/解码/混音、设备格式转换 |
| cpal 回调 | 只搬 `ArrayQueue` 里的 f32 样本 |

控制命令（mute/deafen/设备/codec/PTT）走独立有界通道；语音帧走另一条有界通道，
满了就丢，不会把 mute 之类的控制命令挤掉。

## 采集

- 设备回调按设备原生格式写入环形队列；capture 线程每 10ms 排空一次，转成 48kHz
  单声道或立体声，追加到采集缓冲。
- 每 20ms 取一帧（不足补零），能量 VAD（默认阈值 0.012、250ms 尾音）判断是否发送。
  PTT 模式绕过 VAD，按下才发。VAD 实现是可替换的 `Vad` trait，将来换 RNNoise 不动结构。
- 一段语音开始时重置 Opus 熵编码状态；mute/deafen 会清空采集缓冲并停发，解静音后
  不会补发旧音频。
- `VoicePacer`：空闲复位、稳态每 20ms 一帧、落后超过 200ms 重定位，禁止倾泻。
- 发送前 actor 再检查一次包长：Opus 载荷上限 484 字节（TS 单包上限 500 字节，
  扣除 tag/头/语音头）。64kbps 人声、128kbps 音乐都在安全范围内。

## 播放

- `on_voice_data` 只把 `VoiceFrame { client_id, codec, data }` 塞进有界通道；
  1 字节控制帧和非 4/5 codec 直接忽略。
- 每个说话人独立 `OpusDecoder`、jitter buffer、PCM 余量、增益包络。Opus 单包最长
  120ms，解码缓冲按 5760 样本/声道准备。
- 由于 tsclient-rs 的语音回调未提供包序号，播放侧只能按到达时间做固定目标延迟
  （60ms），不能真正重排序；队列超过 200ms 或 12 帧时丢最旧。缺包先做最多 3 帧
  PLC，再静音；说话人 500ms 无包后淡出并移除。
- 10ms 混音 tick；所有说话人相加后用三段软削波（`|x|<=0.5` 线性，以上 tanh 压缩），
  避免多人同时说话硬削顶。
- deafen 清空解码状态并输出静音；mute/deafen 都会阻止上行。

## 电平

- capture 与 playback 线程各自对采集样本、远端混音算 RMS，经 -60–0dB 映射、噪声门与快速上升、平滑回落处理后，playback 线程每 20ms 合成一次两路电平。
- 电平回调直接发布 `SessionEvent::Levels { mic, received }`，与协议 actor 的音频事件队列分开；协议命令等待网络时仍能更新指标。actor 根据连接状态启停发布，Dart 丢弃断开后的在途读数。
- 事件只带两个 0–1 标量，不携带音频样本；Dart 用独立流接收，50Hz 更新仅重建电平画布。界面直接绘制最新读数，保留约半秒历史，不叠加 UI 插值；切换声源和连接时清空历史。
- 静音、聋听、没有输出流或没有活跃说话人时电平归零。

## 失败语义

- 设备打开失败只发 `Voice` 事件并保持连接；聊天、频道、文件传输继续可用。
- 设备切换只重建受影响的方向；下次 Start 或切换设备时重试。
- 音频线程 panic 不会拖死 actor；actor 侧事件通道断开后语音功能停止，但协议会话仍在。

## 测试

- `convert`：直通、单声道↔立体声、24k↔48k、分块边界连续。
- `capture`：分帧编码、VAD、PTT、mute/deafen、codec 重建、缓冲水位、pacer。
- `playback`：目标延迟、突发预缓冲、PLC、deafen、坏包、混音削波、说话人淡出。
- `level`：RMS、dB 映射与噪声门、平滑、50Hz 节拍、调度抖动与延后不补发。
- 设备与真实服务器不在单测里碰；真机/真服务器验证由人工完成。

## 依赖与构建

`audio` feature 拉 `cpal`、`audiopus`、`crossbeam-queue`：

```sh
# macOS
brew install opus pkgconf
# Debian/Ubuntu
sudo apt-get install -y libopus-dev libasound2-dev
```

仓库根 `.cargo/config.toml` 设置了 `CMAKE_POLICY_VERSION_MINIMUM=3.5`，覆盖
`audiopus_sys` 内置 Opus 的旧 CMake 下限；CI 也使用同一变量。`plugins/flspeak_ffi`
打开了 `audio` feature，因此应用构建需要 Opus 工具链；只跑档案/协议测试时用：

```sh
cd plugins/flspeak_ffi/rust
cargo test -p server -p proto
```

## 已知限制

- 没有回声消除：外放会回授，当前建议耳机。将来做 AEC 时用 playback 回读 ring +
  固定延迟，不在 cpal 回调里做。
- 没有降噪、AGC、去混响；VAD 是能量阈值，机械键盘会误触发。
- 没有真正的语音重排序/去重/精确丢包检测。上游候选改动是给 `VoiceData` 加
  `packet_id`；拿到序号后只需替换 jitter buffer，不动混音层。
- 界面只收 50Hz 的聚合电平（本端麦克风、远端混音）；不传音频样本或逐帧波形。
  `Speaking` 只在活跃集合变化时发低频事件。
