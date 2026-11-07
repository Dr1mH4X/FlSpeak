import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:talker/talker.dart';

import 'json_lines_file_observer.dart';

/// 生产路径在 `initLoggingPipeline` 里替换成带文件观察器的实例；
/// 测试与初始化前的日志落在这个不写盘的控制台实例上。
Talker talker = Talker(
  settings: TalkerSettings(useConsoleLogs: false, maxHistoryItems: 1000),
);

JsonLinesFileObserver? _fileObserver;

class LoggingSetup {
  const LoggingSetup({required this.logDir, this.error});

  final Directory? logDir;
  final Object? error;
}

/// 日志目录与 `preferences.json` 同级，设置页展示的就是这个路径。
Directory logDirectoryFor(String storePath) =>
    Directory(p.join(p.dirname(storePath), 'logs'));

Future<Directory> resolveLogDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'logs'));
}

/// 初始化日志管道。任何一步失败都退回控制台日志并继续启动，
/// 失败原因交给启动提示与设置页处理。
Future<LoggingSetup> initLoggingPipeline({
  Directory? overrideLogDir,
  Future<void> Function(String logDir)? initRust,
  DateTime Function()? now,
}) async {
  Directory? logDir;
  Object? error;

  try {
    logDir = overrideLogDir ?? await resolveLogDirectory();
  } catch (e) {
    error = e;
  }

  JsonLinesFileObserver? observer;
  if (logDir != null) {
    try {
      await logDir.create(recursive: true);
      observer = JsonLinesFileObserver(
        logDir.path,
        minimumLevel: kDebugMode ? LogLevel.debug : LogLevel.info,
        now: now,
      );
      unawaited(observer.pruneNow());
    } catch (e) {
      error ??= e;
      logDir = null;
    }
  }

  if (observer != null) {
    try {
      final dir = logDir!;
      if (initRust != null) {
        await initRust(dir.path);
      } else if (isRustLibInitialized) {
        await initLogging(logDir: dir.path);
      }
    } catch (e) {
      // Rust 文件日志不可用时，Dart 侧仍写自己的文件。
      error ??= e;
    }
  }

  final previous = _fileObserver;
  _fileObserver = observer;
  if (previous != null) {
    await previous.dispose();
  }

  talker = Talker(
    settings: TalkerSettings(useConsoleLogs: kDebugMode, maxHistoryItems: 1000),
    observer: observer,
  );

  return LoggingSetup(logDir: logDir, error: error);
}

/// 退出前把两边队列写完；只用于正常退出路径。
Future<void> shutdownLoggingPipeline() async {
  final observer = _fileObserver;
  _fileObserver = null;
  if (observer != null) {
    try {
      await observer.dispose();
    } catch (e) {
      debugPrint('flush log failed: $e');
    }
  }

  try {
    if (isRustLibInitialized) {
      await shutdownLogging();
    }
  } catch (e) {
    debugPrint('shutdown logging failed: $e');
  }
}

void logDebug(
  String message, {
  String target = 'app',
  Map<String, dynamic>? fields,
  Object? error,
  StackTrace? stackTrace,
}) {
  _log(message, LogLevel.debug, target, fields, error, stackTrace);
}

void logInfo(
  String message, {
  String target = 'app',
  Map<String, dynamic>? fields,
  Object? error,
  StackTrace? stackTrace,
}) {
  _log(message, LogLevel.info, target, fields, error, stackTrace);
}

void logWarn(
  String message, {
  String target = 'app',
  Map<String, dynamic>? fields,
  Object? error,
  StackTrace? stackTrace,
}) {
  _log(message, LogLevel.warning, target, fields, error, stackTrace);
}

void logError(
  String message, {
  String target = 'app',
  Map<String, dynamic>? fields,
  Object? error,
  StackTrace? stackTrace,
}) {
  _log(message, LogLevel.error, target, fields, error, stackTrace);
}

void _log(
  String message,
  LogLevel level,
  String target,
  Map<String, dynamic>? fields,
  Object? error,
  StackTrace? stackTrace,
) {
  talker.logCustom(
    StructuredTalkerLog(
      message,
      fields: fields,
      logLevel: level,
      exception: error,
      stackTrace: stackTrace,
      title: target,
    ),
  );
}
