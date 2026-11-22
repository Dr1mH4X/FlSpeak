// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/settings/settings_state.dart';

const _microphone = AudioDeviceView(
  id: 'mic',
  name: 'Microphone',
  isDefault: false,
);
const _speakers = AudioDeviceView(
  id: 'out',
  name: 'Speakers',
  isDefault: false,
);

class _Core extends Fake implements CoreSession {
  _Core({this.initialInputId, this.initialOutputId});

  final String? initialInputId;
  final String? initialOutputId;
  final firstStarted = Completer<void>();
  final firstReply = Completer<void>();
  final calls = <({String? input, String? output})>[];

  @override
  Future<AudioDevicesView> listAudioDevices() async => AudioDevicesView(
    inputs: const [_microphone],
    outputs: const [_speakers],
    currentInputId: initialInputId,
    currentOutputId: initialOutputId,
  );

  @override
  Future<void> setAudioDevices({String? input, String? output}) async {
    calls.add((input: input, output: output));
    if (calls.length == 1) {
      firstStarted.complete();
      await firstReply.future;
    }
  }
}

void main() {
  for (final failFirst in [false, true]) {
    test(
      'concurrent input/output changes merge the latest successful choice, fail=$failFirst',
      () async {
        final core = _Core();
        final container = ProviderContainer(
          overrides: [coreSessionProvider.overrideWithValue(core)],
        );
        addTearDown(container.dispose);
        final sub = container.listen(audioDevicesProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(audioDevicesProvider.future);
        final controller = container.read(audioDevicesProvider.notifier);
        final input = controller.selectInput(_microphone);
        await core.firstStarted.future;
        final output = controller.selectOutput(_speakers);
        final firstResult = expectLater(
          input,
          failFirst ? throwsA(isA<CoreError>()) : completes,
        );
        if (failFirst) {
          core.firstReply.completeError(
            const CoreError.internal(message: 'input unavailable'),
          );
        } else {
          core.firstReply.complete();
        }
        await firstResult;
        await output;
        expect(core.calls.last, (
          input: failFirst ? null : 'mic',
          output: 'out',
        ));
        final selected = container.read(audioDevicesProvider).asData!.value;
        expect(selected.currentInputId, failFirst ? null : 'mic');
        expect(selected.currentInputName, failFirst ? null : 'Microphone');
        expect(selected.currentOutputId, 'out');
        expect(selected.currentOutputName, 'Speakers');
      },
    );
  }

  test('disposed settings do not apply a queued hardware change', () async {
    final core = _Core();
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    container.listen(audioDevicesProvider, (_, _) {});
    await container.read(audioDevicesProvider.future);
    final controller = container.read(audioDevicesProvider.notifier);
    final input = controller.selectInput(_microphone);
    await core.firstStarted.future;
    final output = controller.selectOutput(_speakers);
    container.dispose();
    core.firstReply.complete();
    await Future.wait([input, output]);
    expect(core.calls, [(input: 'mic', output: null)]);
  });

  test('initial listAudioDevices populates saved current device IDs and names from Rust', () async {
    final core = _Core(initialInputId: 'mic', initialOutputId: 'out');
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    addTearDown(container.dispose);
    final devices = await container.read(audioDevicesProvider.future);
    expect(devices.currentInputId, 'mic');
    expect(devices.currentInputName, 'Microphone');
    expect(devices.currentOutputId, 'out');
    expect(devices.currentOutputName, 'Speakers');
  });
}
