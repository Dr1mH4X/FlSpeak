import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// 已选的音频设备。FFI 只返回设备列表、不返回当前选择，所以选择结果由界面记住。
@immutable
class AudioDeviceSelection {
  const AudioDeviceSelection({
    this.inputId,
    this.inputName,
    this.outputId,
    this.outputName,
  });

  final String? inputId;
  final String? inputName;
  final String? outputId;
  final String? outputName;

  AudioDeviceSelection withInput(AudioDeviceView? device) =>
      AudioDeviceSelection(
        inputId: device?.id,
        inputName: device?.name,
        outputId: outputId,
        outputName: outputName,
      );

  AudioDeviceSelection withOutput(AudioDeviceView? device) =>
      AudioDeviceSelection(
        inputId: inputId,
        inputName: inputName,
        outputId: device?.id,
        outputName: device?.name,
      );
}

/// 选择器里「系统默认」也是合法结果，必须和「用户直接关掉对话框」区分开，
/// 因此用一个包装类型表示系统默认，而不是复用 null。
@immutable
class AudioDeviceChoice {
  const AudioDeviceChoice(this.device);

  final AudioDeviceView? device;
}

final audioSelectionProvider =
    NotifierProvider<AudioSelectionController, AudioDeviceSelection>(
      AudioSelectionController.new,
    );

class AudioSelectionController extends Notifier<AudioDeviceSelection> {
  @override
  AudioDeviceSelection build() => const AudioDeviceSelection();

  Future<void> selectInput(AudioDeviceView? device) =>
      _apply(state.withInput(device));

  Future<void> selectOutput(AudioDeviceView? device) =>
      _apply(state.withOutput(device));

  Future<void> _apply(AudioDeviceSelection next) async {
    // Rust 一次同时写入输入与输出，未改动的另一侧必须带上当前值，否则会被重置成系统默认。
    await ref
        .read(coreSessionProvider)
        .setAudioDevices(input: next.inputId, output: next.outputId);
    state = next;
  }
}

/// 设备列表。只在打开设备选择器时枚举：页面进场就调 FFI 没有意义，也避免设置页
/// 仅仅因为渲染就把原生会话拉起来。
///
/// 关闭 Riverpod 3 的自动重试：设备不可用通常是稳定状态（没有声卡、权限被拒），
/// 自动重试只会反复打 FFI；重新打开选择器会得到新的 autoDispose 实例，等于重试。
final audioDevicesProvider = FutureProvider.autoDispose<AudioDevicesView>(
  (ref) => ref.watch(coreSessionProvider).listAudioDevices(),
  retry: (retryCount, error) => null,
);
