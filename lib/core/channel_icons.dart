import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// 同一连接内共用图标；重连或切换服务器会销毁旧请求的缓存。
final channelIconProvider = FutureProvider.autoDispose.family<Uint8List, int>((
  ref,
  iconId,
) async {
  final session = ref.watch(
    sessionViewProvider.select(
      (view) => (view.activeServerId, view.connectionEpoch, view.connected),
    ),
  );
  if (!session.$3 || session.$1 == null) {
    throw StateError('Channel icon requires an active connection');
  }
  return ref.read(coreSessionProvider).fetchIcon(iconId: iconId);
}, retry: (retryCount, error) => null);
