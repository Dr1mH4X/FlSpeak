import 'package:flspeak/core/update_check.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _releaseUrl = 'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0';

const _available = UpdateStateView(
  available: true,
  latestVersion: '0.2.0',
  releaseUrl: _releaseUrl,
  releaseNotes: '## 新增\n\n- 更新弹窗',
);

const _upToDate = UpdateStateView(available: false);

void main() {
  test('adopts an available update from Rust', () async {
    bool? receivedForce;
    final container = ProviderContainer(
      overrides: [
        updateCheckClientProvider.overrideWithValue(({
          bool force = false,
        }) async {
          receivedForce = force;
          return _available;
        }),
      ],
    );
    addTearDown(container.dispose);

    final next = await container.read(updateProvider.notifier).refresh();

    expect(receivedForce, isFalse);
    expect(next, _available);
    final state = container.read(updateProvider);
    expect(state.available, isTrue);
    expect(state.latestVersion, '0.2.0');
    expect(state.releaseUrl, _releaseUrl);
    expect(state.releaseNotes, '## 新增\n\n- 更新弹窗');
  });

  test('adopts an up-to-date state from Rust', () async {
    final container = ProviderContainer(
      overrides: [
        updateCheckClientProvider.overrideWithValue(
          ({bool force = false}) async => _upToDate,
        ),
      ],
    );
    addTearDown(container.dispose);

    final next = await container.read(updateProvider.notifier).refresh();

    expect(next, _upToDate);
    expect(container.read(updateProvider).available, isFalse);
  });

  test('replaces the previous state with the latest Rust result', () async {
    var result = _available;
    final container = ProviderContainer(
      overrides: [
        updateCheckClientProvider.overrideWithValue(
          ({bool force = false}) async => result,
        ),
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

  test(
    'force refresh forwards force flag and preserves state on failure',
    () async {
      var shouldFail = false;
      bool? receivedForce;
      final container = ProviderContainer(
        overrides: [
          updateCheckClientProvider.overrideWithValue(({
            bool force = false,
          }) async {
            receivedForce = force;
            if (shouldFail) {
              throw StateError('network error');
            }
            return _available;
          }),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(updateProvider.notifier);

      expect(await controller.refresh(), _available);

      shouldFail = true;
      final failed = await controller.refresh(force: true);
      expect(receivedForce, isTrue);
      expect(failed, isNull);
      expect(container.read(updateProvider), _available);
    },
  );
}
