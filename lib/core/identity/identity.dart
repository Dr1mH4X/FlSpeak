import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/logger.dart';
import '../preferences.dart';
import '../providers.dart';
import 'avatars.dart';

/// 当前激活身份。后端目前只有一份身份，它同时是默认身份；问候与身份卡共用这一入口。
@immutable
class ActiveIdentity {
  const ActiveIdentity({
    required this.nickname,
    required this.hasExplicitNickname,
  });

  /// 连接与身份卡使用的昵称。未设置时是持久化层的占位昵称。
  final String nickname;

  /// 问候语是否可以对昵称署名。
  final bool hasExplicitNickname;
}

final activeIdentityProvider = Provider<ActiveIdentity>((ref) {
  final (:nickname, :hasExplicitNickname) = ref.watch(
    preferencesProvider.select(
      (prefs) => (
        nickname: prefs.nickname,
        hasExplicitNickname: prefs.hasExplicitNickname,
      ),
    ),
  );
  final trimmed = nickname.trim();
  return ActiveIdentity(
    nickname: trimmed.isEmpty ? SessionPreferences.fallbackNickname : trimmed,
    hasExplicitNickname: hasExplicitNickname,
  );
});

/// 启动时由 `main()` 通过 FFI 预加载的自头像快照。
final identityAvatarInitialBytesProvider = Provider<Uint8List?>((ref) => null);

/// 本机保留的最近一次自头像。离线、加载中或加载失败时由界面读取。
class IdentityAvatarPreviewController extends Notifier<Uint8List?> {
  int _request = 0;

  @override
  Uint8List? build() => ref.watch(identityAvatarInitialBytesProvider);

  /// 通过 FFI 重新读取 Rust 侧快照；并发调用时只有最后一次结果生效。
  Future<void> refresh() async {
    final request = ++_request;
    Uint8List? bytes;
    try {
      bytes = await ref.read(coreSessionProvider).loadSelfAvatarSnapshot();
    } on Object catch (error) {
      logWarn('failed to load the self avatar snapshot over FFI', error: error);
      return;
    }
    if (!ref.mounted || request != _request) {
      return;
    }
    final current = state;
    if (current == null && bytes == null) {
      return;
    }
    if (current != null && bytes != null && listEquals(current, bytes)) {
      return;
    }
    state = bytes;
  }
}

final identityAvatarPreviewProvider =
    NotifierProvider<IdentityAvatarPreviewController, Uint8List?>(
      IdentityAvatarPreviewController.new,
    );

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
