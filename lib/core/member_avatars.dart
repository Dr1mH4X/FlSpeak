import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class _AvatarCache {
  final refreshers = <String, void Function()>{};
  bool alive = true;
  final requests = <String, Future<Uint8List>>{};
  final attempts = <String, int>{};
  final timers = <Timer>{};

  void dispose() {
    alive = false;
    for (final timer in timers) {
      timer.cancel();
    }
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
      });
      return cache.requests.putIfAbsent(uid, () {
        final attempt = cache.attempts.update(
          uid,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
        return Future.sync(
          () => ref.read(coreSessionProvider).fetchAvatar(uid: uid),
        ).then(
          (bytes) {
            cache.attempts.remove(uid);
            return bytes;
          },
          onError: (Object error, StackTrace stack) {
            if (cache.alive) {
              late final Timer timer;
              timer = Timer(const Duration(seconds: 30), () {
                cache.timers.remove(timer);
                cache.requests.remove(uid);
                if (attempt < 3) cache.refreshers[uid]?.call();
              });
              cache.timers.add(timer);
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
      });
    }, retry: (retryCount, error) => null);
