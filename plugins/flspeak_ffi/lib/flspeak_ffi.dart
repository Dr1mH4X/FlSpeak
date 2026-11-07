library;

import 'src/rust/frb_generated.dart';

export 'src/rust/api/session.dart';
export 'src/rust/frb_generated.dart' show RustLib, RustLibApi;

/// 显式加载 Rust 动态库要用到（非打包环境，例如桌面运行时）。
export 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

bool get isRustLibInitialized => RustLib.instance.initialized;
