library;

import 'src/rust/api/session.dart' as rust_session;
import 'src/rust/frb_generated.dart';
import 'src/rust_library_loader.dart'
    if (dart.library.io) 'src/rust_library_loader_io.dart';

export 'src/rust/api/session.dart'
    hide
        defaultMaxStreamViewers,
        historyLimit,
        maxAvatarBytes,
        maxChatImageBytes,
        streamOfferFitsCommand,
        tsEscapedLen;
export 'src/rust/api/update.dart';
export 'src/rust/frb_generated.dart' show RustLib, RustLibApi;

/// 显式加载 Rust 动态库要用到（非打包环境，例如桌面运行时）。
export 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

bool get isRustLibInitialized => RustLib.instance.initialized;

/// 计算字符串按 TeamSpeak 命令行转义后的字节长度。
int tsEscapedLen({required String text}) {
  ensureRustLibInitializedSync();
  return rust_session.tsEscapedLen(text: text);
}

/// 判断屏幕共享 SDP Offer 转义后是否可放入单条 TeamSpeak 命令（9150 字节预算）。
bool streamOfferFitsCommand({required String sdp}) {
  ensureRustLibInitializedSync();
  return rust_session.streamOfferFitsCommand(sdp: sdp);
}

/// 客户端头像大小安全上限（字节）。
int maxAvatarBytes() {
  ensureRustLibInitializedSync();
  return rust_session.maxAvatarBytes();
}

/// 聊天图片大小安全上限（字节）。
int maxChatImageBytes() {
  ensureRustLibInitializedSync();
  return rust_session.maxChatImageBytes();
}

/// 每个会话在内存与本地历史中保留的最大聊天消息条数。
int historyLimit() {
  ensureRustLibInitializedSync();
  return rust_session.historyLimit();
}

/// 屏幕共享发布端默认最大并发观众数。
int defaultMaxStreamViewers() {
  ensureRustLibInitializedSync();
  return rust_session.defaultMaxStreamViewers();
}
