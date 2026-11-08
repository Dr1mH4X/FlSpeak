import 'package:flspeak/core/update_check.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _releaseUrl = 'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0';

const _available = UpdateStateView(
  available: true,
  latestVersion: '0.2.0',
  releaseUrl: _releaseUrl,
);

const _upToDate = UpdateStateView(available: false);

void main() {
  test('adopts an available update from Rust', () async {
    final container = ProviderContainer(
      overrides: [
        updateCheckClientProvider.overrideWithValue(() async => _available),
      ],
    );
    addTearDown(container.dispose);

    await container.read(updateProvider.notifier).refresh();

    final state = container.read(updateProvider);
    expect(state.available, isTrue);
    expect(state.latestVersion, '0.2.0');
    expect(state.releaseUrl, _releaseUrl);
  });

  test('adopts an up-to-date state from Rust', () async {
    final container = ProviderContainer(
      overrides: [
        updateCheckClientProvider.overrideWithValue(() async => _upToDate),
      ],
    );
    addTearDown(container.dispose);

    await container.read(updateProvider.notifier).refresh();

    expect(container.read(updateProvider).available, isFalse);
  });

  test('replaces the previous state with the latest Rust result', () async {
    var result = _available;
    final container = ProviderContainer(
      overrides: [
        updateCheckClientProvider.overrideWithValue(() async => result),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(updateProvider.notifier);

    await controller.refresh();
    expect(container.read(updateProvider).available, isTrue);

    result = _upToDate;
    await controller.refresh();
    expect(container.read(updateProvider).available, isFalse);
  });
}
