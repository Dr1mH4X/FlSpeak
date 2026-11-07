import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:talker/talker.dart';

/// 带有结构化 fields 载荷的 TalkerLog
class StructuredTalkerLog extends TalkerLog {
  final Map<String, dynamic>? fields;

  StructuredTalkerLog(
    super.message, {
    this.fields,
    super.logLevel,
    super.exception,
    super.error,
    super.stackTrace,
    super.title,
    super.key,
  });
}

class JsonLinesFileObserver extends TalkerObserver {
  final String logDir;
  static const int _retentionDays = 7;
  DateTime? _lastPruneDate;

  JsonLinesFileObserver(this.logDir);

  @override
  void onError(TalkerError err) {
    onLog(err);
  }

  @override
  void onException(TalkerException err) {
    onLog(err);
  }

  @override
  void onLog(TalkerData log) {
    final now = DateTime.now();
    // 文件名统一基于 UTC 日期，严格对齐 Rust 的 tracing-appender
    final utc = now.toUtc();
    final dateStr =
        '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';

    final file = File(p.join(logDir, 'dart.$dateStr.log'));
    final level = log.logLevel ?? LogLevel.debug;

    dynamic fields;
    if (log is StructuredTalkerLog) {
      fields = log.fields;
    }

    final record = <String, dynamic>{
      // 内部时间戳保留本地时区与偏移
      'timestamp': now.toIso8601String(),
      'level': level.name,
      'message': log.message ?? '',
      'target': log.key ?? log.title ?? '',
      'fields': ?fields,
      if (log.exception != null) 'error': log.exception.toString(),
      if (log.error != null && log.exception == null)
        'error': log.error.toString(),
      if (log.stackTrace != null) 'stack': log.stackTrace.toString(),
    };

    try {
      file.writeAsStringSync(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: level == LogLevel.error || level == LogLevel.critical,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to write log: $e');
      }
    }

    _maybePruneOldFiles(utc);
  }

  void _maybePruneOldFiles(DateTime utcNow) {
    if (_lastPruneDate != null &&
        utcNow.difference(_lastPruneDate!).inHours < 12) {
      return;
    }
    _lastPruneDate = utcNow;

    final dir = Directory(logDir);
    if (!dir.existsSync()) return;

    final cutoff = utcNow.subtract(const Duration(days: _retentionDays));
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      const prefix = 'dart.';
      const suffix = '.log';
      if (!name.startsWith(prefix) || !name.endsWith(suffix)) continue;

      final datePart = name.substring(
        prefix.length,
        name.length - suffix.length,
      );
      final fileDate = DateTime.tryParse(datePart);
      if (fileDate != null && fileDate.isBefore(cutoff)) {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }
  }
}
