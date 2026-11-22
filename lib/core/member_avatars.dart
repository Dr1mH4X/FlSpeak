import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class _AvatarCache {
  bool alive = true;
  final requests = <String, Future<Uint8List?>>{};
  final revisions = <String, int>{};

  void invalidate(String uid, {int? revision}) {
    requests.remove(uid);
    if (revision != null) {
      revisions[uid] = revision;
    }
  }

  void syncRevision(String uid, int revision) {
    if ((revisions[uid] ?? 0) != revision) {
      invalidate(uid, revision: revision);
    }
  }

  void dispose() {
    alive = false;
    requests.clear();
    revisions.clear();
  }
}

final Provider<_AvatarCache?> _memberAvatarCacheProvider =
    Provider<_AvatarCache?>((ref) {
      final session = ref.watch(
        sessionViewProvider.select(
          (view) => (view.activeServerId, view.connectionEpoch, view.connected),
        ),
      );
      if (!session.$3 || session.$1 == null) return null;
      final cache = _AvatarCache();
      final subscription = ref
          .read(sessionViewProvider.notifier)
          .avatarUpdates
          .listen((uid) {
            final currentRev =
                ref.read(memberAvatarRevisionsProvider)[uid] ?? 0;
            // 在通知订阅组件重建前先清掉缓存，避免重建瞬间命中旧 Future。
            cache.invalidate(uid, revision: currentRev + 1);
            ref.read(memberAvatarRevisionsProvider.notifier).bump(uid);
          });
      ref.onDispose(() {
        subscription.cancel();
        cache.dispose();
      });
      return cache;
    });

class MemberAvatarRevisionsController extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const <String, int>{};

  void bump(String uid) {
    if (uid.isEmpty) return;
    final next = (state[uid] ?? 0) + 1;
    state = Map.unmodifiable({...state, uid: next});
  }
}

final memberAvatarRevisionsProvider =
    NotifierProvider<MemberAvatarRevisionsController, Map<String, int>>(
      MemberAvatarRevisionsController.new,
    );

final memberAvatarProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, uid) {
      final cache = ref.watch(_memberAvatarCacheProvider);
      if (cache == null) {
        throw StateError('Member avatar requires an active connection');
      }
      final revision = ref.watch(
        memberAvatarRevisionsProvider.select((revs) => revs[uid] ?? 0),
      );
      cache.syncRevision(uid, revision);

      return cache.requests.putIfAbsent(uid, () {
        late final Future<Uint8List?> request;
        request =
            Future.sync(
              () => ref.read(coreSessionProvider).fetchAvatar(uid: uid),
            ).then(
              (bytes) => (bytes == null || bytes.isEmpty) ? null : bytes,
              onError: (Object error, StackTrace stack) {
                // 失败后释放本地占位，下次挂载或失效时重新向 Rust 询问（冷却由 Rust 裁决）。
                if (cache.alive && identical(cache.requests[uid], request)) {
                  cache.requests.remove(uid);
                }
                Error.throwWithStackTrace(error, stack);
              },
            );
        return request;
      });
    }, retry: (retryCount, error) => null);

/// 连接页身份卡与身份对话框共用的头像来源。
///
/// 未连接、加载中或加载失败时回退到本机快照；服务器明确返回 `null` 时
/// 返回 `null`，由界面显示缩写圆。
final identityAvatarProvider = Provider<Uint8List?>((ref) {
  final preview = ref.watch(identityAvatarPreviewProvider);
  final (:connected, :uid) = ref.watch(
    sessionViewProvider.select(
      (view) => (connected: view.connected, uid: view.selfClient?.uid ?? ''),
    ),
  );
  if (!connected || uid.isEmpty) {
    return preview;
  }
  final avatar = ref.watch(memberAvatarProvider(uid));
  if (avatar is AsyncData<Uint8List?>) {
    return avatar.value;
  }
  return preview;
});

/// 当前连接下自头像拉取到的字节；加载中、失败或服务器无头像时为 `null`。
final selfAvatarBytesProvider = Provider<Uint8List?>((ref) {
  final uid = ref.watch(
    sessionViewProvider.select(
      (view) => view.connected ? view.selfClient?.uid ?? '' : '',
    ),
  );
  if (uid.isEmpty) {
    return null;
  }
  final avatar = ref.watch(memberAvatarProvider(uid));
  return avatar is AsyncData<Uint8List?> ? avatar.value : null;
});
