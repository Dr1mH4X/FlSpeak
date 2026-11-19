# 音频

## 目标形态

```text
麦克风 ──cpal──> ArrayQueue ──> capture 线程
  设备格式 → 48k 目标声道 → VAD/PTT → 20ms Opus → VoicePacer → actor
actor ──> Client::send_voice(data, codec)          （发送仍由 actor 独占）

on_voice_data ──有界通道──> playback 线程
  每说话人自适应 jitter（40–160ms）→ Opus 解码（20ms normal/FEC/PLC）→ 10ms 混音 → 软削波
  → 48k 立体声 → 设备格式（钳位 [-1, 1]）→ ArrayQueue(120ms) ──cpal──> 扬声器
```

- 48kHz 为内部采样率；codec 4（Opus Voice）上行单声道（VoIP、CVBR 64kbps、开启带内 FEC 与默认 15% 预期丢包、关闭 DTX），codec 5（Opus Music）上行立体声（Audio、CVBR 128kbps、关闭 FEC）；下行统一按立体声解码。
- **频道 codec 决定编码器**：TS3 的 codec 是频道属性，不是客户端全局配置。进 codec 4 频道用单声道 Voip 编码器，进 codec 5 频道重建为立体声 Audio 编码器。Opus 不支持中途切声道数，切频道必须重建 encoder。
- 全双工边界是两条独立线程：采集/编码/发送与接收/解码/混音/播放互不阻塞。cpal 回调只做 `ArrayQueue` 的 push/pop，零分配、零锁；编码、解码、混音都在工作线程。

## 线程

| 线程 | 职责 |
| --- | --- |
| `session` actor | 独占 `Client`；所有协议调用串行；`send_voice` 也在这里 |
| `voice-capture` | cpal 输入流、格式转换、VAD/PTT、20ms 分帧、Opus 编码、发送节拍 |
| `voice-playback` | cpal 输出流、每说话人 jitter/解码/混音、设备格式转换 |
| cpal 回调 | 只搬 `ArrayQueue` 里的 f32 样本 |

控制命令（mute/deafen/设备/codec/PTT）走独立有界通道；语音帧走另一条有界通道，满了就丢，不会把 mute 之类的控制命令挤掉。

## 采集

- 设备回调按设备原生格式写入环形队列；capture 线程每 10ms 排空一次，转成 48kHz 单声道或立体声，追加到采集缓冲。
- 每 20ms 取一帧，能量 VAD（默认采用 `AudioSettings` 持久化配置：阈值 0.015、15 帧即 300ms 尾音）判断是否发送。PTT 模式绕过 VAD，按下才发。VAD 实现是可替换的 `Vad` trait，将来换 RNNoise 不动结构。
- 一段语音开始时重置 Opus 编码状态（保留运行时丢包率配置）；mute/deafen 会清空采集缓冲并停发，解静音后不会补发旧音频。
- `VoicePacer`：空闲复位、稳态每 20ms 一帧、落后超过 200ms 重定位，禁止倾泻。
- Opus 编码与 actor 发送检查共用 484 字节载荷预算（TS 单包上限 500 字节，扣除 tag/头/语音头）。编码器以此限制单帧输出，保留完整可解码的包；64kbps 人声、128kbps 音乐是 CVBR 的目标平均码率。
- 编码包携带单调时钟时间；actor 丢弃等待超过 100ms 的包，并核对连接、频道、codec、采集状态与 mute/deafen/PTT。控制状态或频道变化会使此前排队的包失效。
- PTT 模式与按下状态由 actor 持有；音频线程的采集状态事件只报告设备就绪情况。

## 播放

- `on_voice_data` 将 `VoiceFrame { client_id, codec, seq, received_at, is_end_of_stream, data }` 塞进有界通道；0 字节结束尾包直达说话人状态机，非空 1 字节控制帧与非 4/5 codec 忽略。
- 每个说话人独立 `OpusDecoder`、基于 `u16` 有符号回绕差值 `diff = seq.wrapping_sub(expected_seq) as i16` 的 `BTreeMap` 重排缓冲（`diff < 0` 或重复丢弃并统计、`0 <= diff <= 50` 重排等待、`diff > 50` 或超时后重同步）、PCM 余量与平滑包络。
- 自适应目标延迟：利用包到达时间 `received_at` 与 `seq * 20ms` 的相对偏差做 RFC 3550 风格 EWMA 估算抖动，在 40ms–160ms 之间抬高快、回落慢地调节 `target_delay`；缓冲深度持续超过 `target_delay + 60ms` 时优先裁剪低能量静音帧并按需带 Cross-fade 跳帧追赶。
- 每 20ms 帧按三层恢复：命中期望序号且为 0 字节尾包时立即结束说话并对尾部做 7.5ms 逐样本平滑淡出（不触发 PLC）；正常帧调用 `decode_normal`；缺失期望帧且下一包非尾包已在缓冲时调用 `decode_fec` 严格恢复单帧 20ms 并保留下一包供后续正常解码；无下一包时调用 `decode_plc` 严格预测单帧 20ms（上限 4 帧即 80ms，自第 2 帧起逐样本指数衰减至静音）；起播、丢包恢复首帧与跳帧边界执行 4ms 逐样本平滑过渡。
- 5ms 轮询水位驱动吐帧：`PlaybackStream` 按输出设备 `sample_rate * channels` 动态分配约 120ms `ArrayQueue` 并在写入时按声道整帧对齐；目标安全垫水位为 25ms，每次唤醒排空 `incoming` 后仅在队列低于水位时调用 `PlaybackPipeline::tick()`（每次 10ms，单次唤醒最多补 2 帧），达到水位即跳过解码等待声卡消费；混音软削波及重采样输出均钳位到 `[-1.0, 1.0]`。
- deafen 清空解码状态并输出静音；mute/deafen 都会阻止上行。
- 播放流重建清空说话人与缓冲，保留 deafen 控制状态。

## 电平

- capture 与 playback 线程各自对采集样本、远端混音算 RMS，经 -60–0dB 映射、噪声门与快速上升、平滑回落处理后，playback 线程每 20ms 合成一次两路电平。
- 电平回调写入独立的最新值缓存，不占用协议广播容量，也不等待 actor。`SessionSubscription` 优先交付状态和消息，再合成当前连接代次的 `SessionEvent::Levels { mic, received }`；慢消费者跳过中间电平。
- 采集与播放的启动命令携带连接代次，共享麦克风值也带生产代次。断开、采集停止和新代次清零，旧采集值、旧播放包络及迟到回调不能作为新连接的读数。
- 事件只带两个 0–1 标量，不携带音频样本；Dart 用独立流接收，50Hz 更新仅重建电平画布。界面直接绘制最新读数，保留约半秒历史，不叠加 UI 插值；切换声源和连接时清空历史。
- 静音、聋听、没有输出流或没有活跃说话人时电平归零。

## 失败语义

- 设备打开失败只发 `Voice` 事件并保持连接；聊天、频道、文件传输继续可用。
- 设备切换只重建受影响的方向；下次 Start 或切换设备时重试。
- 音频线程 panic 不会拖死 actor；actor 侧事件通道断开后语音功能停止，但协议会话仍在。

## 测试

- `convert`：直通、单声道↔立体声、24k↔48k、分块边界连续、重采样过冲钳位。
- `capture`：分帧编码、VAD、PTT、mute/deafen、codec 重建、缓冲水位、pacer、VAD 参数生效。
- `playback`：自适应延迟、乱序重排、`u16` 回绕、迟到/重复包丢弃、0 字节尾包淡出、FEC/PLC 分层恢复、积压追赶、deafen、混音削波。
- `device` / `engine`：120ms 队列动态容量、整帧对齐写入、5ms 水位控制。
- `level`：RMS、dB 映射与噪声门、平滑、50Hz 节拍、调度抖动与延后不补发。
- 设备与真实服务器不在单测里碰；真机/真服务器验证由人工完成。

## 依赖与构建

`audio` feature 拉 `cpal`、`rusty-opus`（纯 Rust 实现）、`crossbeam-queue`；Windows 与 macOS 无需额外系统 Opus 库，Linux 仅需 ALSA 开发包与 pkg-config：

```sh
# Debian/Ubuntu
sudo apt-get install -y libasound2-dev pkg-config
```

`plugins/flspeak_ffi` 打开了 `audio` feature；只跑档案/协议测试时用：

```sh
cd plugins/flspeak_ffi/rust
cargo test -p server -p proto
```

## 已知限制

- 没有回声消除：外放会回授，当前建议耳机。将来做 AEC 时用 playback 回读 ring + 固定延迟，不在 cpal 回调里做。
- 没有降噪、AGC、去混响；VAD 是能量阈值，机械键盘会误触发。
- 界面只收 50Hz 的聚合电平（本端麦克风、远端混音）；不传音频样本或逐帧波形。`Speaking` 只在活跃集合变化时发低频事件。
