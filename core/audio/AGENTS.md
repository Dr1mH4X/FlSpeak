# AGENTS.md — 音频处理与编解码 (core/audio)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `core/audio` crate。

## 规则与约束

- **帧不过桥**：原始 PCM 音频帧绝不穿越 FFI 边界进入 Dart/Flutter 进程。
- **无锁实时安全**：音频采集与播放线程回调中禁止加互斥锁、系统 IO 或堆分配，必须使用无锁环形缓冲区。
- **Feature 解耦**：基础逻辑与格式转换在无 `audio` feature 时保持可独立编译与单测。
- 完整子系统契约见 [../../docs/subsystems/audio.md](../../docs/subsystems/audio.md)。
