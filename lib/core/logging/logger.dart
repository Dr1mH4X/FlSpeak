import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:talker/talker.dart';

import 'json_lines_file_observer.dart';

late Talker talker;

Future<Directory> resolveLogDirectory() async {
  final support = await getApplicationSupportDirectory();
  final logDir = Directory(p.join(support.path, 'logs'));
  if (!await logDir.exists()) {
    await logDir.create(recursive: true);
  }
  return logDir;
}

Future<Directory> initLoggingPipeline({Directory? overrideLogDir}) async {
  final logDir = overrideLogDir ?? await resolveLogDirectory();

  // 1. 异步注入 Rust 侧
  if (isRustLibInitialized) {
    await initLogging(logDir: logDir.path);
  }

  // 2. 初始化全局 Talker 单例
  talker = Talker(
    settings: TalkerSettings(
      useConsoleLogs: kDebugMode, // Debug 下打印控制台，Release 自动静默
      maxHistoryItems: 1000,
    ),
    observer: JsonLinesFileObserver(logDir.path),
  );

  return logDir;
}
