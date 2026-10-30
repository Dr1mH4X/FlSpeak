import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 核心偏好与档案文件：`<应用支持目录>/preferences.json`。
///
/// 身份私钥由 Rust 侧写在同一目录的 `identity.json`，不经过 Dart。
Future<String> resolveStorePath() async {
  final directory = await getApplicationSupportDirectory();
  if (!await Directory(directory.path).exists()) {
    await Directory(directory.path).create(recursive: true);
  }
  return p.join(directory.path, 'preferences.json');
}
