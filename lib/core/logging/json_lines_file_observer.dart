import 'dart:async';
import 'dart:collection';
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
    super.time,
    super.title,
    super.key,
  });
}

class JsonLinesFileObserver extends TalkerObserver {
  JsonLinesFileObserver(
    this.logDir, {
    this.minimumLevel = LogLevel.debug,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String logDir;
  final LogLevel minimumLevel;
  final DateTime Function() _now;

  static const int _retentionDays = 7;
  static const int _maxQueuedRecords = 2048;
  static const int _batchSize = 128;

  static final RegExp _logName = RegExp(
    r'^(?:dart|rust)\.(\d{4}-\d{2}-\d{2})\.log$',
  );

  final Queue<_PendingRecord> _queue = Queue<_PendingRecord>();
  Future<void>? _drainFuture;
  DateTime? _lastPruneAt;
  bool _disposed = false;

  @override
  void onError(TalkerError err) => onLog(err);

  @override
  void onException(TalkerException err) => onLog(err);

  @override
  void onLog(TalkerData log) {
    if (_disposed) return;

    final level = log.logLevel ?? LogLevel.info;
    if (!_passes(level)) return;

    final time = log.time.toUtc();
    final record = <String, dynamic>{
      if (log is StructuredTalkerLog && log.fields != null) ...log.fields!,
      'timestamp': time.toIso8601String(),
      'level': level.name.toUpperCase(),
      'message': log.message ?? '',
      'target': log.key ?? log.title ?? '',
      if (log.exception != null) 'error': log.exception.toString(),
      if (log.error != null && log.exception == null)
        'error': log.error.toString(),
      if (log.stackTrace != null) 'stack': log.stackTrace.toString(),
    };

    String line;
    try {
      line = jsonEncode(record);
    } catch (error) {
      line = jsonEncode({
        'timestamp': time.toIso8601String(),
        'level': level.name.toUpperCase(),
        'message': log.message ?? '',
        'target': log.key ?? log.title ?? '',
        'encode_error': error.toString(),
      });
    }

    _queue.add(_PendingRecord(_datePart(time), line, _isError(level)));
    if (_queue.length > _maxQueuedRecords) {
      _queue.removeFirst();
    }
    _scheduleDrain();
  }

  /// 把队列写完；退出前调用。
  Future<void> flush() async {
    while (_queue.isNotEmpty || _drainFuture != null) {
      _scheduleDrain();
      final pending = _drainFuture;
      if (pending != null) {
        await pending;
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await flush();
  }

  /// 清理超过保留期的 `dart.*` 与 `rust.*` 文件。
  Future<void> pruneNow({bool force = false}) => _pruneIfDue(force: force);

  bool _passes(LogLevel level) {
    final minimum = logLevelPriorityList.indexOf(minimumLevel);
    final index = logLevelPriorityList.indexOf(level);
    return minimum >= 0 && index >= 0 && index <= minimum;
  }

  bool _isError(LogLevel level) =>
      level == LogLevel.error || level == LogLevel.critical;

  void _scheduleDrain() {
    if (_drainFuture != null) return;
    _drainFuture = _drain().whenComplete(() {
      _drainFuture = null;
      if (_queue.isNotEmpty && !_disposed) {
        _scheduleDrain();
      }
    });
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final batch = <_PendingRecord>[];
      while (_queue.isNotEmpty && batch.length < _batchSize) {
        batch.add(_queue.removeFirst());
      }

      final byDate = <String, List<_PendingRecord>>{};
      for (final record in batch) {
        byDate.putIfAbsent(record.date, () => []).add(record);
      }

      for (final entry in byDate.entries) {
        final file = File(p.join(logDir, 'dart.${entry.key}.log'));
        try {
          await file.writeAsString(
            '${entry.value.map((record) => record.line).join('\n')}\n',
            mode: FileMode.append,
            flush: entry.value.any((record) => record.flush),
          );
        } catch (error) {
          _reportWriteFailure(error);
        }
      }
    }

    await _pruneIfDue();
  }

  Future<void> _pruneIfDue({bool force = false}) async {
    final now = _now();
    final last = _lastPruneAt;
    if (!force && last != null && now.difference(last).inHours < 12) return;

    try {
      final dir = Directory(logDir);
      if (!await dir.exists()) return;

      final cutoff = now.toUtc().subtract(const Duration(days: _retentionDays));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final match = _logName.firstMatch(p.basename(entity.path));
        if (match == null) continue;

        final date = DateTime.tryParse('${match.group(1)}T00:00:00Z');
        if (date == null || !date.isBefore(cutoff)) continue;
        try {
          await entity.delete();
        } catch (_) {
          // 文件可能被另一个平台的 worker 占用；下次清理再试。
        }
      }
      _lastPruneAt = now;
    } catch (error) {
      _reportWriteFailure(error);
    }
  }

  void _reportWriteFailure(Object error) {
    if (kDebugMode) {
      debugPrint('Failed to write log: $error');
    }
  }

  String _datePart(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

class _PendingRecord {
  const _PendingRecord(this.date, this.line, this.flush);

  final String date;
  final String line;
  final bool flush;
}
