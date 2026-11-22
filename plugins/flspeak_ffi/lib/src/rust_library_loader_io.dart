import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';

import 'rust/frb_generated.dart';

/// 在尚未调用过 `RustLib.init()` 的测试隔离环境里，按需同步打开本地编译好的动态库。
void ensureRustLibInitializedSync() {
  if (RustLib.instance.initialized) {
    return;
  }
  final path = _resolveNativeLibraryPath();
  if (path == null) {
    return;
  }
  // 传入 ExternalLibrary 时，initImpl 会在首个 await 前同步完成 RustLib.instance.api 初始化。
  unawaited(RustLib.init(externalLibrary: ExternalLibrary.open(path)));
}

String _libraryFileName() {
  if (Platform.isWindows) {
    return 'flspeak_ffi.dll';
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return 'libflspeak_ffi.dylib';
  }
  return 'libflspeak_ffi.so';
}

String? _resolveNativeLibraryPath() {
  final libName = _libraryFileName();
  final envDir =
      Platform.environment['FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR'];
  if (envDir != null && envDir.isNotEmpty) {
    final envFile = File(Uri.directory(envDir).resolve(libName).toFilePath());
    if (envFile.existsSync()) {
      return envFile.path;
    }
  }

  final fromNativeAssets = _resolveFromNativeAssetsManifest();
  if (fromNativeAssets != null) {
    return fromNativeAssets;
  }

  final candidates = <String>[
    'build/native_assets/${Platform.operatingSystem}/$libName',
    '../build/native_assets/${Platform.operatingSystem}/$libName',
    '../../build/native_assets/${Platform.operatingSystem}/$libName',
    'plugins/flspeak_ffi/rust/target/release/$libName',
    'rust/target/release/$libName',
    'target/release/$libName',
    '../../target/release/$libName',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  return _resolveFromHooksRunnerCache(libName);
}

String? _resolveFromNativeAssetsManifest() {
  for (final manifestPath in const [
    '.dart_tool/native_assets.yaml',
    '../.dart_tool/native_assets.yaml',
    '../../.dart_tool/native_assets.yaml',
  ]) {
    final file = File(manifestPath);
    if (!file.existsSync()) {
      continue;
    }
    try {
      final raw = file.readAsStringSync();
      final jsonStart = raw.indexOf('{');
      if (jsonStart < 0) {
        continue;
      }
      final decoded = jsonDecode(raw.substring(jsonStart));
      if (decoded is! Map<String, Object?>) {
        continue;
      }
      final nativeAssets = decoded['native-assets'];
      if (nativeAssets is! Map<String, Object?>) {
        continue;
      }
      for (final targetEntry in nativeAssets.values) {
        if (targetEntry is! Map<String, Object?>) {
          continue;
        }
        for (final assetEntry in targetEntry.entries) {
          if (!assetEntry.key.contains('flspeak_ffi')) {
            continue;
          }
          final value = assetEntry.value;
          if (value is List &&
              value.length >= 2 &&
              value[0] == 'absolute' &&
              value[1] is String) {
            final resolved = value[1] as String;
            if (File(resolved).existsSync()) {
              return resolved;
            }
          }
        }
      }
    } on Object {
      // 清单不可读时继续尝试其余候选路径。
    }
  }
  return null;
}

String? _resolveFromHooksRunnerCache(String libName) {
  for (final cacheRoot in const [
    '.dart_tool/hooks_runner/shared/flspeak_ffi/build',
    '../.dart_tool/hooks_runner/shared/flspeak_ffi/build',
    '../../.dart_tool/hooks_runner/shared/flspeak_ffi/build',
  ]) {
    final dir = Directory(cacheRoot);
    if (!dir.existsSync()) {
      continue;
    }
    try {
      final matches = <File>[];
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File &&
            entity.uri.pathSegments.lastOrNull == libName &&
            entity.path.contains('/release/')) {
          matches.add(entity);
        }
      }
      if (matches.isNotEmpty) {
        matches.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
        return matches.first.path;
      }
    } on Object {
      // 忽略缓存遍历异常并交给调用方抛出未初始化错误。
    }
  }
  return null;
}
