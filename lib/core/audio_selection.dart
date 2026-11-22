import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// 设置页选择音频设备弹窗的返回值；`device == null` 代表跟随系统默认。
class AudioDeviceChoice {
  const AudioDeviceChoice(this.device);

  final AudioDeviceView? device;
}

/// 从 Rust 返回的音频设备列表中解析当前生效的输入/输出设备。
extension AudioDevicesViewSelection on AudioDevicesView {
  AudioDeviceView? get currentInput => _findDevice(inputs, currentInputId);

  AudioDeviceView? get currentOutput => _findDevice(outputs, currentOutputId);

  String? get currentInputName => currentInput?.name;

  String? get currentOutputName => currentOutput?.name;

  AudioDevicesView copyWithSelection({
    String? currentInputId,
    String? currentOutputId,
  }) => AudioDevicesView(
    inputs: inputs,
    outputs: outputs,
    currentInputId: currentInputId,
    currentOutputId: currentOutputId,
  );
}

AudioDeviceView? _findDevice(List<AudioDeviceView> devices, String? id) {
  if (id == null) {
    return null;
  }
  for (final device in devices) {
    if (device.id == id) {
      return device;
    }
  }
  return null;
}

/// 向当前挂载的音频设备控制器广播后端回退通知，避免在未打开语音设置时提前加载设备列表。
final audioDeviceResetBusProvider =
    Provider<StreamController<({bool input, bool output})>>((ref) {
      final controller =
          StreamController<({bool input, bool output})>.broadcast(sync: true);
      ref.onDispose(controller.close);
      return controller;
    });

/// 由 Rust 提供并持久化的音频设备列表与当前选择。
final audioDevicesProvider =
    AsyncNotifierProvider.autoDispose<AudioDevicesController, AudioDevicesView>(
      AudioDevicesController.new,
      retry: (retryCount, error) => null,
    );

class AudioDevicesController extends AsyncNotifier<AudioDevicesView> {
  Future<void> _pending = Future<void>.value();

  @override
  Future<AudioDevicesView> build() {
    final subscription = ref
        .read(audioDeviceResetBusProvider)
        .stream
        .listen(
          (event) => resetFallback(input: event.input, output: event.output),
        );
    ref.onDispose(subscription.cancel);
    return ref.read(coreSessionProvider).listAudioDevices();
  }

  Future<void> selectInput(AudioDeviceView? device) =>
      _update(updateInput: true, input: device);

  Future<void> selectOutput(AudioDeviceView? device) =>
      _update(updateOutput: true, output: device);

  /// 音频后端因设备失效回退系统默认时，清除对应的本地展示 ID。
  void resetFallback({required bool input, required bool output}) {
    if (!input && !output) {
      return;
    }
    final current = state.asData?.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(
      current.copyWithSelection(
        currentInputId: input ? null : current.currentInputId,
        currentOutputId: output ? null : current.currentOutputId,
      ),
    );
  }

  Future<void> _serialized(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((_) {});
    return next;
  }

  Future<void> _update({
    bool updateInput = false,
    AudioDeviceView? input,
    bool updateOutput = false,
    AudioDeviceView? output,
  }) => _serialized(() async {
    if (!ref.mounted) {
      return;
    }
    final current = state.asData?.value ?? await future;
    if (!ref.mounted) {
      return;
    }
    final nextInputId = updateInput ? input?.id : current.currentInputId;
    final nextOutputId = updateOutput ? output?.id : current.currentOutputId;
    await ref
        .read(coreSessionProvider)
        .setAudioDevices(input: nextInputId, output: nextOutputId);
    if (!ref.mounted) {
      return;
    }
    final latest = state.asData?.value ?? current;
    state = AsyncData(
      latest.copyWithSelection(
        currentInputId: nextInputId,
        currentOutputId: nextOutputId,
      ),
    );
  });
}
