// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/providers.dart';
import 'settings_state.dart';

class _Core extends Fake implements CoreSession {
  final firstStarted = Completer<void>();
  final firstReply = Completer<void>();
  final calls = <({String? input, String? output})>[];

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
  const microphone = AudioDeviceView(
    id: 'mic',
    name: 'Microphone',
    isDefault: false,
  );
  const speakers = AudioDeviceView(
    id: 'out',
    name: 'Speakers',
    isDefault: false,
  );
  for (final failFirst in [false, true]) {
    test(
      'concurrent input/output changes merge the latest successful choice, fail=$failFirst',
      () async {
        final core = _Core();
        final container = ProviderContainer(
          overrides: [coreSessionProvider.overrideWithValue(core)],
        );
        addTearDown(container.dispose);
        final controller = container.read(audioSelectionProvider.notifier);
        final input = controller.selectInput(microphone);
        await core.firstStarted.future;
        final output = controller.selectOutput(speakers);
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
        final selected = container.read(audioSelectionProvider);
        expect(selected.inputId, failFirst ? null : 'mic');
        expect(selected.outputId, 'out');
      },
    );
  }

  test('disposed settings do not apply a queued hardware change', () async {
    final core = _Core();
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    final controller = container.read(audioSelectionProvider.notifier);
    final input = controller.selectInput(microphone);
    await core.firstStarted.future;
    final output = controller.selectOutput(speakers);
    container.dispose();
    core.firstReply.complete();
    await Future.wait([input, output]);
    expect(core.calls, [(input: 'mic', output: null)]);
  });
}
