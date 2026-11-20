import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

typedef UpdateCheckClient = Future<UpdateStateView> Function({bool force});
typedef ExternalUrlOpener = Future<bool> Function(String url);

/// 在系统默认浏览器中打开外部链接。
Future<bool> openExternalUrl(String url) async {
  if (kIsWeb) {
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    return false;
  }
}

/// 可替换的外部链接打开器；测试里可覆盖为内存记录实现。
final externalUrlOpenerProvider = Provider<ExternalUrlOpener>(
  (ref) => openExternalUrl,
);

/// 可替换的更新状态来源；测试里覆盖成不会走 FFI 的实现。
final updateCheckClientProvider = Provider<UpdateCheckClient>(
  (ref) =>
      ({bool force = false}) =>
          force ? forceCheckForUpdates() : checkForUpdates(),
);

/// Rust 返回的最终更新状态；Dart 只保存并渲染。
final updateProvider = NotifierProvider<UpdateController, UpdateStateView>(
  UpdateController.new,
);

class UpdateController extends Notifier<UpdateStateView> {
  @override
  UpdateStateView build() => const UpdateStateView(available: false);

  /// 刷新更新状态；`force` 为 true 时绕过 Rust 6 小时缓存并在失败时保留原状态返回 `null`。
  Future<UpdateStateView?> refresh({bool force = false}) async {
    try {
      final next = await ref.read(updateCheckClientProvider)(force: force);
      if (ref.mounted) {
        state = next;
      }
      return next;
    } on Object {
      return null;
    }
  }
}
