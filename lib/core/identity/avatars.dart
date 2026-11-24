import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

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

const _avatarTypeGroup = XTypeGroup(
  extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
  mimeTypes: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
  uniformTypeIdentifiers: [
    'public.png',
    'public.jpeg',
    'com.compuserve.gif',
    'org.webmproject.webp',
  ],
);

enum AvatarInputFailure { tooLarge }

class AvatarInputException implements Exception {
  const AvatarInputException(this.failure);

  final AvatarInputFailure failure;
}

final avatarInputProvider = Provider<AvatarInput>((ref) => const AvatarInput());

void ensureAvatarSize(int length) {
  if (length > maxAvatarBytes()) {
    throw const AvatarInputException(AvatarInputFailure.tooLarge);
  }
}

class AvatarInput {
  const AvatarInput();

  /// 先读文件长度，超过上限的文件不会进入内存。
  Future<Uint8List?> pick() async {
    final file = await openFile(acceptedTypeGroups: const [_avatarTypeGroup]);
    if (file == null) return null;
    ensureAvatarSize(await file.length());
    final bytes = await file.readAsBytes();
    ensureAvatarSize(bytes.length);
    return bytes;
  }
}
