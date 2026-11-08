import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef UpdateCheckClient = Future<UpdateStateView> Function();

/// 可替换的更新状态来源；测试里覆盖成不会走 FFI 的实现。
final updateCheckClientProvider = Provider<UpdateCheckClient>(
  (ref) => checkForUpdates,
);

/// Rust 返回的最终更新状态；Dart 只保存并渲染。
final updateProvider = NotifierProvider<UpdateController, UpdateStateView>(
  UpdateController.new,
);

class UpdateController extends Notifier<UpdateStateView> {
  @override
  UpdateStateView build() => const UpdateStateView(available: false);

  Future<void> refresh() async {
    final next = await ref.read(updateCheckClientProvider)();
    if (ref.mounted) {
      state = next;
    }
  }
}
