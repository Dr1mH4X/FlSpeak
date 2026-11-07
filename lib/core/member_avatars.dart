import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class _AvatarCache {
  final refreshers = <String, void Function()>{};
  bool alive = true;
  final requests = <String, Future<Uint8List>>{};
  final attempts = <String, int>{};
  final timers = <String, Timer>{};
  final cooldowns = <String, ({DateTime expiresAt, bool isTransient})>{};

  void cancelTimer(String uid) {
    timers.remove(uid)?.cancel();
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
      ref.onDispose(cache.dispose);
      return cache;
    });

bool _isTransientAvatarError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('queue is full') ||
      message.contains('interrupted') ||
      message.contains('busy');
}

final memberAvatarProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, uid) {
      final cache = ref.watch(_memberAvatarCacheProvider);
      if (cache == null) {
        throw StateError('Member avatar requires an active connection');
      }
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
        return Future.sync(
          () => ref.read(coreSessionProvider).fetchAvatar(uid: uid),
        ).then(
          (bytes) {
            cache.cancelTimer(uid);
            cache.cooldowns.remove(uid);
            cache.attempts.remove(uid);
            return bytes;
          },
          onError: (Object error, StackTrace stack) {
            if (cache.alive) {
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
