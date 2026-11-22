import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class _AvatarCache {
  final refreshers = <String, void Function()>{};
  bool alive = true;
  final requests = <String, Future<Uint8List?>>{};
  final attempts = <String, int>{};
  final timers = <String, Timer>{};
  final cooldowns = <String, ({DateTime expiresAt, bool isTransient})>{};
  final generations = <String, int>{};
  final revisions = <String, int>{};

  int generationOf(String uid) => generations[uid] ?? 0;

  void cancelTimer(String uid) {
    timers.remove(uid)?.cancel();
  }

  void invalidate(String uid, {int? revision}) {
    generations[uid] = (generations[uid] ?? 0) + 1;
    cancelTimer(uid);
    requests.remove(uid);
    cooldowns.remove(uid);
    attempts.remove(uid);
    if (revision != null) {
      revisions[uid] = revision;
    }
  }

  void syncRevision(String uid, int revision) {
    if ((revisions[uid] ?? 0) != revision) {
      invalidate(uid, revision: revision);
    }
  }

  void scheduleCooldown({
    required String uid,
    required Duration duration,
    required bool isTransient,
    required int attempt,
  }) {
    if (!alive) return;
    cancelTimer(uid);
    final expiresAt = DateTime.now().add(duration);
    cooldowns[uid] = (expiresAt: expiresAt, isTransient: isTransient);

    final timer = Timer(duration, () {
      timers.remove(uid);
      cooldowns.remove(uid);
      requests.remove(uid);
      if (!isTransient && attempt >= 3) {
        attempts.remove(uid);
      } else {
        refreshers[uid]?.call();
      }
    });
    timers[uid] = timer;
  }

  void dispose() {
    alive = false;
    for (final timer in timers.values) {
      timer.cancel();
    }
    timers.clear();
    cooldowns.clear();
    attempts.clear();
    requests.clear();
    generations.clear();
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
            // 在通知订阅组件重建前先清掉缓存与冷却，避免重建瞬间命中旧 Future。
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

bool _isTransientAvatarError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('queue is full') ||
      message.contains('interrupted') ||
      message.contains('busy');
}

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

      void refresh() => ref.invalidateSelf();
      cache.refreshers[uid] = refresh;
      ref.onDispose(() {
        if (identical(cache.refreshers[uid], refresh)) {
          cache.refreshers.remove(uid);
        }
        cache.cancelTimer(uid);
      });
      final cooldown = cache.cooldowns[uid];
      if (cooldown != null) {
        final remaining = cooldown.expiresAt.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          cache.cooldowns.remove(uid);
          cache.requests.remove(uid);
          if (!cooldown.isTransient && (cache.attempts[uid] ?? 0) >= 3) {
            cache.attempts.remove(uid);
          }
        } else if (!cache.timers.containsKey(uid)) {
          cache.scheduleCooldown(
            uid: uid,
            duration: remaining,
            isTransient: cooldown.isTransient,
            attempt: cache.attempts[uid] ?? 1,
          );
        }
      }
      return cache.requests.putIfAbsent(uid, () {
        final generation = cache.generationOf(uid);
        return Future.sync(
          () => ref.read(coreSessionProvider).fetchAvatar(uid: uid),
        ).then(
          (bytes) {
            final normalized = (bytes == null || bytes.isEmpty) ? null : bytes;
            if (cache.alive && cache.generationOf(uid) == generation) {
              cache.cancelTimer(uid);
              cache.cooldowns.remove(uid);
              cache.attempts.remove(uid);
            }
            return normalized;
          },
          onError: (Object error, StackTrace stack) {
            if (cache.alive && cache.generationOf(uid) == generation) {
              final isTransient = _isTransientAvatarError(error);
              if (isTransient) {
                cache.scheduleCooldown(
                  uid: uid,
                  duration: const Duration(milliseconds: 500),
                  isTransient: true,
                  attempt: 0,
                );
              } else {
                final attempt = cache.attempts.update(
                  uid,
                  (n) => n + 1,
                  ifAbsent: () => 1,
                );
                cache.scheduleCooldown(
                  uid: uid,
                  duration: const Duration(seconds: 30),
                  isTransient: false,
                  attempt: attempt,
                );
              }
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
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
