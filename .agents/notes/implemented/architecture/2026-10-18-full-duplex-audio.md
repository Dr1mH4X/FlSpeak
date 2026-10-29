# Agent Note: 双线程全双工语音

Status: implemented

## Problem

第一版把采集、编码、接收、解码、混音都放进一个 20ms tick 的音频线程。逻辑上能同时收发，
但播放侧多说话人解码/混音会拖慢采集节拍，而且没有 jitter buffer、没有 VAD，频道 codec
也按全局常量处理。现有结构参考 Mumble 的 AudioInput/AudioOutput 两条独立线程与
TeamSpeakClaw 的 `VoicePacer`。

## Decision

- **两条独立线程**：`voice-capture` 与 `voice-playback`，各自 10ms/20ms 节拍；cpal 回调
  只做 `ArrayQueue` 的 push/pop，零分配、零锁。编码/解码/混音都在工作线程。
- **actor 仍是唯一协议出口**：capture 线程只产出 `AudioEvent::Outbound`，actor 串行调用
  `Client::send_voice`；`on_voice_data` 只把包塞进 playback 的有界通道。
- **频道 codec 跟随**：TS3 的 codec 是频道属性。codec 4 用单声道 Voip 编码器，codec 5 用
  立体声 Audio 编码器；切 codec 重建 encoder。不把 4/5 做成客户端全局配置。
- **VAD + PTT**：默认能量 VAD（0.012、250ms 尾音），PTT 可切换；VAD 是 `Vad` trait，
  将来换 RNNoise 不动结构。
- **无 seq 的 jitter**：tsclient-rs 0.1.5 丢弃语音包序号，因此只做 60ms 固定目标延迟 +
  有界队列 + PLC，不做重排序。接口保留 `VoiceFrame`，将来拿到 seq 只替换 jitter buffer。
- **不做 AEC/降噪/AGC**：建议耳机；将来 AEC 用 playback 回读 ring + 固定延迟，不在 cpal
  回调里做。
- **软削波**：混音后 `|x|<=0.5` 线性，超过用 tanh 压缩，替代硬 clamp。
- **重连**：1/2/4/15/30/60/120/300s 退避；首轮成功前最多 5 次，成功后不限次；不自动回
  原频道，Dart 保存 `lastChannelId` 并提供「回到上次频道」按钮。
- **身份提升**：连续 3 次握手超时后 +5 级（上限 29），独立线程挖矿、可取消，身份文件用
  临时文件 + fsync + rename 原子写。
- **文件传输**：TCP 发送原始 `ftkey` 后收发明文字节，下载严格校验声明大小；传输与图标的理由见[频道图标](../../implemented/architecture/2026-10-28-channel-icons.md)。

## Alternatives considered

- **单线程 20ms tick**：实现简单，但播放解码/混音会拖慢采集，不能算真正的全双工。
- **在 cpal 回调里编码/混音**：回调要求零分配零锁，这条路径天然做不到。
- **fork tsclient-rs 暴露 seq**：fork 成本高；先提上游 PR，被合并后零 fork 成本，接口侧
  预留 `VoiceFrame`。
- **做回声消除**：需要额外依赖、回读延迟对齐和 UI 开关，收益/成本不如先把双线程与
  jitter 做稳。

## Consequences

- cpal 设备流被限制在各自线程；`VoiceEngine` Drop 时发 Shutdown 并 join，避免设备泄漏。
- 音频事件与控制命令分离；语音帧满即丢，不会挤掉 mute/deafen。
- 没有 seq 时 UDP 乱序无法纠正；上游候选改动是给 `VoiceData` 加 `packet_id`。
- 频道 codec 读取依赖 `channellist -codec` / `channelinfo`；读不到时停采集并提示，不猜
  codec 发包。
- 身份挖矿可能占用一个核心几十秒到几分钟；UI 有取消入口。
- 链路与已知限制的细节见 `docs/audio.md`。

## Related

发送包的新鲜度与 PTT 状态归属见[语音发送的新鲜度与控制状态](../../implemented/architecture/2026-10-29-voice-egress-gate.md)；保存失败时的身份保留见[保存失败时保留持久化数据](../../implemented/bug-fix/2026-10-29-preserve-persistent-data.md)。
