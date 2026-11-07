import 'dart:convert';
import 'dart:io';

import 'package:flspeak/core/logging/json_lines_file_observer.dart';
import 'package:flspeak/core/logging/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:talker/talker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flspeak_logging_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('JsonLinesFileObserver writes structured ndjson with UTC file name', () {
    final observer = JsonLinesFileObserver(tempDir.path);
    final now = DateTime.now();
    final utc = now.toUtc();
    final dateStr =
        '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
    final expectedFile = File(p.join(tempDir.path, 'dart.$dateStr.log'));

    expect(expectedFile.existsSync(), isFalse);

    final logData = TalkerLog(
      'User joined channel',
      logLevel: LogLevel.info,
      title: 'channel_manager',
    );

    observer.onLog(logData);

    expect(expectedFile.existsSync(), isTrue);
    final lines = expectedFile.readAsLinesSync();
    expect(lines.length, 1);

    final json = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(json['level'], 'info');
    expect(json['message'], 'User joined channel');
    expect(json['target'], 'channel_manager');
    expect(json['timestamp'], isNotEmpty);

    // Verify timestamp is valid ISO8601
    final parsedTime = DateTime.parse(json['timestamp'] as String);
    expect(parsedTime, isNotNull);
  });

  test('JsonLinesFileObserver supports StructuredTalkerLog with fields', () {
    final observer = JsonLinesFileObserver(tempDir.path);
    final logData = StructuredTalkerLog(
      'Packet received',
      logLevel: LogLevel.debug,
      fields: {'packet_size': 480, 'codec': 'opus'},
      key: 'audio_pipeline',
    );

    observer.onLog(logData);

    final utc = DateTime.now().toUtc();
    final dateStr =
        '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
    final file = File(p.join(tempDir.path, 'dart.$dateStr.log'));

    final lines = file.readAsLinesSync();
    final json = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(json['fields'], {'packet_size': 480, 'codec': 'opus'});
    expect(json['target'], 'audio_pipeline');
  });

  test('JsonLinesFileObserver routes onError and onException to onLog', () {
    final observer = JsonLinesFileObserver(tempDir.path);

    final err = TalkerError(
      ArgumentError('Invalid argument'),
      message: 'Operation failed',
      stackTrace: StackTrace.current,
    );
    observer.onError(err);

    final exc = TalkerException(
      const FormatException('Bad format'),
      message: 'Parse error',
    );
    observer.onException(exc);

    final utc = DateTime.now().toUtc();
    final dateStr =
        '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
    final file = File(p.join(tempDir.path, 'dart.$dateStr.log'));

    final lines = file.readAsLinesSync();
    expect(lines.length, 2);

    final json1 = jsonDecode(lines[0]) as Map<String, dynamic>;
    expect(json1['message'], 'Operation failed');
    expect(json1['error'], contains('Invalid argument'));
    expect(json1['stack'], isNotEmpty);

    final json2 = jsonDecode(lines[1]) as Map<String, dynamic>;
    expect(json2['message'], 'Parse error');
    expect(json2['error'], contains('Bad format'));
  });

  test('JsonLinesFileObserver prunes log files older than 7 days', () {
    final observer = JsonLinesFileObserver(tempDir.path);
    final utc = DateTime.now().toUtc();

    // Create old file (10 days old)
    final oldDate = utc.subtract(const Duration(days: 10));
    final oldDateStr =
        '${oldDate.year.toString().padLeft(4, '0')}-'
        '${oldDate.month.toString().padLeft(2, '0')}-'
        '${oldDate.day.toString().padLeft(2, '0')}';
    final oldFile = File(p.join(tempDir.path, 'dart.$oldDateStr.log'));
    oldFile.writeAsStringSync('{"old": true}\n');

    // Create recent file (2 days old)
    final recentDate = utc.subtract(const Duration(days: 2));
    final recentDateStr =
        '${recentDate.year.toString().padLeft(4, '0')}-'
        '${recentDate.month.toString().padLeft(2, '0')}-'
        '${recentDate.day.toString().padLeft(2, '0')}';
    final recentFile = File(p.join(tempDir.path, 'dart.$recentDateStr.log'));
    recentFile.writeAsStringSync('{"recent": true}\n');

    // Trigger log write which runs _maybePruneOldFiles
    observer.onLog(TalkerLog('trigger prune', logLevel: LogLevel.info));

    expect(oldFile.existsSync(), isFalse);
    expect(recentFile.existsSync(), isTrue);
  });

  test(
    'initLoggingPipeline sets up talker with JsonLinesFileObserver',
    () async {
      await initLoggingPipeline(overrideLogDir: tempDir);

      expect(talker, isNotNull);
      talker.info('Hello from Talker test');

      final utc = DateTime.now().toUtc();
      final dateStr =
          '${utc.year.toString().padLeft(4, '0')}-'
          '${utc.month.toString().padLeft(2, '0')}-'
          '${utc.day.toString().padLeft(2, '0')}';
      final file = File(p.join(tempDir.path, 'dart.$dateStr.log'));

      expect(file.existsSync(), isTrue);
      final lines = file.readAsLinesSync();
      expect(lines.any((l) => l.contains('Hello from Talker test')), isTrue);
    },
  );
}
