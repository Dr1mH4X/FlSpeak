/// 两路音频的聚合电平，取值 0–1。
///
/// 由 Rust 侧每 20ms 推送一次；这里只保存响度，不携带音频样本。
class VoiceLevels {
  const VoiceLevels({this.mic = 0, this.received = 0});

  static const silent = VoiceLevels();

  /// 本端麦克风。
  final double mic;

  /// 远端语音混音。
  final double received;

  VoiceLevels copyWith({double? mic, double? received}) =>
      VoiceLevels(mic: mic ?? this.mic, received: received ?? this.received);
}
