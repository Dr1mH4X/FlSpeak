import 'dart:async';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/identity/avatars.dart';
import 'package:flspeak/core/identity/identity.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';

final _preview = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
]);

final _fresh = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x53,
]);

class _Core extends Fake implements CoreSession {
  _Core({this.avatar});

  final Future<Uint8List?>? avatar;
  final requests = <String>[];
  Uint8List? snapshot;

  @override
  Stream<CoreEvent> events() => const Stream<CoreEvent>.empty();

  @override
  Future<List<ServerProfileView>> listServers() async => const [];

  @override
  Future<List<ServerIconView>> listServerIcons() async => const [];

  @override
  Future<Uint8List?> fetchAvatar({required String uid}) {
    requests.add(uid);
    return (avatar ?? Future.value(null)).then((bytes) {
      if (bytes != null) {
        snapshot = bytes;
      }
      return bytes;
    });
  }

  @override
  Future<Uint8List?> loadSelfAvatarSnapshot() async => snapshot;

  @override
  Future<void> uploadAvatar({required List<int> bytes}) async {
    snapshot = Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteAvatar() async {
    snapshot = null;
  }
}

class _ConnectedSession extends SessionController {
  @override
  SessionView build() => super.build().copyWith(
    state: const CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'server-1',
    clients: const [
      ClientView(id: 1, nickname: 'Self', uid: 'self-uid', channelId: 5),
    ],
  );
}

class _RootListener extends ConsumerWidget {
  const _RootListener();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(selfAvatarBytesProvider);
    ref.listen<Uint8List?>(selfAvatarBytesProvider, (previous, next) {
      if (next != null && next != previous) {
        unawaited(ref.read(identityAvatarPreviewProvider.notifier).refresh());
      }
    });
    return const SizedBox.shrink();
  }
}

ProviderContainer _container({
  required SessionController Function() session,
  required CoreSession core,
  Uint8List? preview,
}) {
  return ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(core),
      sessionViewProvider.overrideWith(session),
      identityAvatarInitialBytesProvider.overrideWithValue(preview),
    ],
  );
}

/// 与 `TsClientApp` 的根级监听保持一致。
ProviderSubscription<Uint8List?> _listenToSelfAvatar(
  ProviderContainer container,
) {
  return container.listen(selfAvatarBytesProvider, (_, bytes) {
    if (bytes != null) {
      unawaited(
        container.read(identityAvatarPreviewProvider.notifier).refresh(),
      );
    }
  }, fireImmediately: true);
}

void main() {
  testWidgets('disconnected identity avatar uses the snapshot', (tester) async {
    final core = _Core();
    final container = _container(
      session: SessionController.new,
      core: core,
      preview: _preview,
    );
    final subscription = container.listen(identityAvatarProvider, (_, _) {});
    await tester.pump();

    expect(container.read(identityAvatarProvider), _preview);
    expect(core.requests, isEmpty);

    subscription.close();
    container.dispose();
  });

  testWidgets('loading self avatar falls back to the snapshot', (tester) async {
    final pending = Completer<Uint8List?>();
    final core = _Core(avatar: pending.future);
    final container = _container(
      session: _ConnectedSession.new,
      core: core,
      preview: _preview,
    );
    final subscription = container.listen(identityAvatarProvider, (_, _) {});
    await tester.pump();

    expect(container.read(identityAvatarProvider), _preview);
    expect(core.requests, ['self-uid']);

    pending.complete(_fresh);
    await tester.pump();
    expect(container.read(identityAvatarProvider), _fresh);

    subscription.close();
    container.dispose();
  });

  testWidgets('server-side null overrides the snapshot while connected', (
    tester,
  ) async {
    final core = _Core(avatar: Future.value(null));
    final container = _container(
      session: _ConnectedSession.new,
      core: core,
      preview: _preview,
    );
    final subscription = container.listen(identityAvatarProvider, (_, _) {});
    await tester.pump();

    expect(container.read(identityAvatarProvider), isNull);

    subscription.close();
    container.dispose();
  });

  testWidgets('fetch failure keeps the snapshot', (tester) async {
    final pending = Completer<Uint8List?>();
    final core = _Core(avatar: pending.future);
    final container = _container(
      session: _ConnectedSession.new,
      core: core,
      preview: _preview,
    );
    final subscription = container.listen(identityAvatarProvider, (_, _) {});
    final failure = expectLater(
      container.read(memberAvatarProvider('self-uid').future),
      throwsA(isA<StateError>()),
    );

    pending.completeError(StateError('avatar unavailable'));
    await tester.pump();
    await failure;

    expect(container.read(identityAvatarProvider), _preview);

    subscription.close();
    container.dispose();
  });

  testWidgets('app-root wrapper flushes self avatar updates without a read', (
    tester,
  ) async {
    final pending = Completer<Uint8List?>();
    final core = _Core(avatar: pending.future);
    final container = _container(session: _ConnectedSession.new, core: core);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _RootListener(),
      ),
    );
    await tester.pump();
    expect(container.read(identityAvatarPreviewProvider), isNull);

    pending.complete(_fresh);
    await tester.pump();
    await tester.pump();
    expect(container.read(identityAvatarPreviewProvider), _fresh);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets(
    'root listener writes successful self avatar fetches to the snapshot',
    (tester) async {
      final pending = Completer<Uint8List?>();
      final core = _Core(avatar: pending.future);
      final container = _container(session: _ConnectedSession.new, core: core);
      final subscription = _listenToSelfAvatar(container);
      await tester.pump();

      expect(container.read(identityAvatarPreviewProvider), isNull);
      pending.complete(_fresh);
      await tester.pump();
      container.read(selfAvatarBytesProvider);
      await tester.pump();
      expect(container.read(identityAvatarPreviewProvider), _fresh);

      subscription.close();
      container.dispose();
    },
  );

  testWidgets('root listener records an already cached self avatar', (
    tester,
  ) async {
    final pending = Completer<Uint8List?>();
    final core = _Core(avatar: pending.future);
    final container = _container(session: _ConnectedSession.new, core: core);
    final memberSubscription = container.listen(
      memberAvatarProvider('self-uid'),
      (_, _) {},
    );
    pending.complete(_fresh);
    await tester.pump();
    expect(
      container.read(memberAvatarProvider('self-uid')),
      isA<AsyncData<Uint8List?>>(),
    );

    final subscription = _listenToSelfAvatar(container);
    await tester.pump();
    expect(container.read(identityAvatarPreviewProvider), _fresh);

    subscription.close();
    memberSubscription.close();
    container.dispose();
  });

  testWidgets('root listener keeps the snapshot when the server returns null', (
    tester,
  ) async {
    final core = _Core(avatar: Future.value(null));
    final container = _container(
      session: _ConnectedSession.new,
      core: core,
      preview: _preview,
    );
    final subscription = _listenToSelfAvatar(container);
    await tester.pump();

    expect(container.read(identityAvatarPreviewProvider), _preview);

    subscription.close();
    container.dispose();
  });

  testWidgets('disconnected root listener does not request an avatar', (
    tester,
  ) async {
    final core = _Core();
    final container = _container(session: SessionController.new, core: core);
    final subscription = _listenToSelfAvatar(container);
    await tester.pump();

    expect(core.requests, isEmpty);

    subscription.close();
    container.dispose();
  });

  testWidgets('upload records the bytes and delete clears the snapshot', (
    tester,
  ) async {
    final core = _Core();
    final container = _container(session: _ConnectedSession.new, core: core);
    await tester.pump();
    final controller = container.read(sessionViewProvider.notifier);

    expect(await controller.uploadAvatar(_fresh), isTrue);
    expect(container.read(identityAvatarPreviewProvider), _fresh);

    expect(await controller.deleteAvatar(), isTrue);
    expect(container.read(identityAvatarPreviewProvider), isNull);

    container.dispose();
  });
}
