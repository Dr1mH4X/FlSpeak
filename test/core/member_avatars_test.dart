import 'dart:async';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/member_avatars.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';

class _Core extends Fake implements CoreSession {
  final requests = <Completer<Uint8List>>[];
  @override
  Future<Uint8List> fetchAvatar({required String uid}) {
    final reply = Completer<Uint8List>();
    requests.add(reply);
    return reply.future;
  }
}

class _Controller extends SessionController {
  @override
  SessionView build() => const SessionView(
    activeServerId: 'a',
    connectionEpoch: 1,
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
  );
  void switchServer() =>
      state = state.copyWith(activeServerId: 'b', connectionEpoch: 2);
  void reconnect() =>
      state = state.copyWith(connectionEpoch: state.connectionEpoch + 1);
  void simulateDisconnect() => state = state.copyWith(
    state: const CoreSessionState.disconnected(),
    activeServerId: null,
  );
}

void main() {
  testWidgets('timeouts retry with a cooldown and stop after three attempts', (
    tester,
  ) async {
    final core = _Core();
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_Controller.new),
      ],
    );
    final provider = memberAvatarProvider('uid');
    final subscription = container.listen(provider, (_, _) {});
    for (var attempt = 1; attempt <= 3; attempt++) {
      expect(core.requests, hasLength(attempt));
      final failure = expectLater(
        container.read(provider.future),
        throwsA(isA<TimeoutException>()),
      );
      core.requests.last.completeError(TimeoutException('temporary'));
      await tester.pump();
      await failure;
      await tester.pump(const Duration(seconds: 29));
      expect(core.requests, hasLength(attempt));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(core.requests, hasLength(3));
    await tester.pump(const Duration(minutes: 2));
    expect(core.requests, hasLength(3));
    container.invalidate(provider);
    final refreshed = container.read(provider.future);
    expect(core.requests, hasLength(4));
    core.requests.last.complete(Uint8List.fromList([9]));
    await tester.pump();
    expect(await refreshed, [9]);
    subscription.close();
    container.dispose();
    await tester.pump();
  });

  testWidgets(
    'transient queue-full and interrupted errors retry promptly within 500ms without consuming attempt count',
    (tester) async {
      final core = _Core();
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          sessionViewProvider.overrideWith(_Controller.new),
        ],
      );
      final provider = memberAvatarProvider('uid-transient');
      final subscription = container.listen(provider, (_, _) {});

      // 1. 模拟队列满错误（transient）
      expect(core.requests, hasLength(1));
      final failure1 = expectLater(
        container.read(provider.future),
        throwsA(isA<StateError>()),
      );
      core.requests.last.completeError(
        StateError('image request queue is full'),
      );
      await tester.pump();
      await failure1;

      // 400ms 时尚未重试
      await tester.pump(const Duration(milliseconds: 400));
      expect(core.requests, hasLength(1));

      // 500ms 时触发快速重试
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(core.requests, hasLength(2));

      // 2. 模拟被控制操作打断（transient）
      final failure2 = expectLater(
        container.read(provider.future),
        throwsA(isA<StateError>()),
      );
      core.requests.last.completeError(
        StateError('image negotiation interrupted'),
      );
      await tester.pump();
      await failure2;

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(core.requests, hasLength(3));

      // 3. 此时发生一次真实超时（attempt 1），应当进入 30s 冷却而非 500ms
      final failure3 = expectLater(
        container.read(provider.future),
        throwsA(isA<TimeoutException>()),
      );
      core.requests.last.completeError(
        TimeoutException('real network timeout'),
      );
      await tester.pump();
      await failure3;

      // 500ms 时不应重试
      await tester.pump(const Duration(milliseconds: 500));
      expect(core.requests, hasLength(3));

      // 29s 后仍未重试，30s 后重试
      await tester.pump(const Duration(seconds: 29));
      expect(core.requests, hasLength(3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(core.requests, hasLength(4));

      core.requests.last.complete(Uint8List.fromList([42]));
      await tester.pump();
      expect(await container.read(provider.future), [42]);

      subscription.close();
      container.dispose();
      await tester.pump();
    },
  );

  for (final hasAvatar in [true, false]) {
    test(
      'recycled rows retain cached avatars and missing results, present=$hasAvatar',
      () async {
        final core = _Core();
        final container = ProviderContainer(
          overrides: [
            coreSessionProvider.overrideWithValue(core),
            sessionViewProvider.overrideWith(_Controller.new),
          ],
        );
        addTearDown(container.dispose);
        final provider = memberAvatarProvider('uid');
        final first = container.listen(provider, (_, _) {});
        final initial = container.read(provider.future);
        if (hasAvatar) {
          core.requests.single.complete(Uint8List.fromList([1]));
          await initial;
        } else {
          core.requests.single.completeError(StateError('no avatar'));
          await expectLater(initial, throwsStateError);
        }
        first.close();
        await container.pump();
        final second = container.listen(provider, (_, _) {});
        if (hasAvatar) {
          expect(await container.read(provider.future), [1]);
        } else {
          await expectLater(container.read(provider.future), throwsStateError);
        }
        expect(core.requests, hasLength(1));
        second.close();
        await container.pump();
        final controller =
            container.read(sessionViewProvider.notifier) as _Controller;
        controller.reconnect();
        await container.pump();
        expect(core.requests, hasLength(1));
        final third = container.listen(provider, (_, _) {});
        addTearDown(third.close);
        core.requests.last.complete(Uint8List.fromList([2]));
        expect(await container.read(provider.future), [2]);
        expect(core.requests, hasLength(2));
        controller.simulateDisconnect();
        await expectLater(container.read(provider.future), throwsStateError);
        expect(core.requests, hasLength(2));
      },
    );
  }
  test('avatar requests are shared and old-server bytes cannot replace a new avatar', () async {
    final core = _Core();
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_Controller.new),
      ],
    );
    addTearDown(container.dispose);
    final first = container.listen(memberAvatarProvider('uid'), (_, _) {});
    final second = container.listen(memberAvatarProvider('uid'), (_, _) {});
    addTearDown(first.close);
    addTearDown(second.close);
    await Future<void>.delayed(Duration.zero);
    expect(core.requests, hasLength(1));
    (container.read(sessionViewProvider.notifier) as _Controller)
        .switchServer();
    await Future<void>.delayed(Duration.zero);
    core.requests.first.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(memberAvatarProvider('uid')).hasValue, isFalse);
    core.requests.last.complete(Uint8List.fromList([2]));
    expect(await container.read(memberAvatarProvider('uid').future), [2]);
  });
}
