import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

final _memberAvatarCacheProvider = Provider<Map<String, Future<Uint8List>>?>((
  ref,
) {
  final session = ref.watch(
    sessionViewProvider.select(
      (view) => (view.activeServerId, view.connectionEpoch, view.connected),
    ),
  );
  return session.$3 && session.$1 != null ? {} : null;
});

final memberAvatarProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, uid) {
      final cache = ref.watch(_memberAvatarCacheProvider);
      if (cache == null) {
        throw StateError('Member avatar requires an active connection');
      }
      // 行销毁后仍保留成功和失败的请求；连接作用域变化时整体清空。
      return cache.putIfAbsent(
        uid,
        () => Future.sync(
          () => ref.read(coreSessionProvider).fetchAvatar(uid: uid),
        ),
      );
    }, retry: (retryCount, error) => null);
