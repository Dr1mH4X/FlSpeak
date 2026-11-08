import 'dart:convert';
import 'dart:io';

import 'package:flspeak/core/logging/json_lines_file_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:talker/talker.dart';

void main() {
  late Directory tempDir;
  final now = DateTime.utc(2026, 11, 7, 12);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flspeak_observer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  JsonLinesFileObserver observer({LogLevel minimumLevel = LogLevel.debug}) =>
      JsonLinesFileObserver(
        tempDir.path,
        minimumLevel: minimumLevel,
        now: () => now,
      );

  test(
    'writes ndjson with UTC timestamp, uppercase level and fields',
    () async {
      final file = File(p.join(tempDir.path, 'frontend.2026-11-07.log'));

      final logObserver = observer();
      logObserver.onLog(
        StructuredTalkerLog(
          'joined channel',
          logLevel: LogLevel.info,
          fields: {'answer': 42, 'channel': 'lobby'},
          key: 'session',
          time: now,
        ),
      );
      await logObserver.flush();

      final json =
          jsonDecode(file.readAsLinesSync().single) as Map<String, dynamic>;
      expect(json['timestamp'], '2026-11-07T12:00:00.000Z');
      expect(json['level'], 'INFO');
      expect(json['message'], 'joined channel');
      expect(json['target'], 'session');
      expect(json['answer'], 42);
      expect(json['channel'], 'lobby');
    },
  );

  test('routes onError and onException to the same file', () async {
    final logObserver = observer();

    logObserver.onError(
      TalkerError(
        ArgumentError('invalid'),
        message: 'operation failed',
        stackTrace: StackTrace.current,
      ),
    );
    logObserver.onException(
      TalkerException(
        const FormatException('bad format'),
        message: 'parse error',
      ),
    );
    await logObserver.flush();

    final files = tempDir
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith('frontend.'))
        .toList();
    expect(files, hasLength(1));
    final lines = files.single.readAsLinesSync();
    expect(lines, hasLength(2));
    final first = jsonDecode(lines[0]) as Map<String, dynamic>;
    expect(first['message'], 'operation failed');
    expect(first['error'], contains('invalid'));
    expect(first['stack'], isNotEmpty);

    final second = jsonDecode(lines[1]) as Map<String, dynamic>;
    expect(second['message'], 'parse error');
    expect(second['error'], contains('bad format'));
  });

  test(
    'prunes both frontend and backend files older than seven days',
    () async {
      final old = now.subtract(const Duration(days: 10));
      final recent = now.subtract(const Duration(days: 2));
      String date(DateTime value) =>
          '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';

      final oldFrontend = File(
        p.join(tempDir.path, 'frontend.${date(old)}.log'),
      )..writeAsStringSync('{}\n');
      final oldBackend = File(p.join(tempDir.path, 'backend.${date(old)}.log'))
        ..writeAsStringSync('{}\n');
      final oldDart = File(p.join(tempDir.path, 'dart.${date(old)}.log'))
        ..writeAsStringSync('{}\n');
      final oldRust = File(p.join(tempDir.path, 'rust.${date(old)}.log'))
        ..writeAsStringSync('{}\n');
      final recentFrontend = File(
        p.join(tempDir.path, 'frontend.${date(recent)}.log'),
      )..writeAsStringSync('{}\n');
      final recentBackend = File(
        p.join(tempDir.path, 'backend.${date(recent)}.log'),
      )..writeAsStringSync('{}\n');

      await observer().pruneNow(force: true);

      expect(oldFrontend.existsSync(), isFalse);
      expect(oldBackend.existsSync(), isFalse);
      expect(oldDart.existsSync(), isFalse);
      expect(oldRust.existsSync(), isFalse);
      expect(recentFrontend.existsSync(), isTrue);
      expect(recentBackend.existsSync(), isTrue);
    },
  );

  test('prune failures do not escape', () async {
    final blocker = File(p.join(tempDir.path, 'not-a-directory'))
      ..writeAsStringSync('x');

    final logObserver = JsonLinesFileObserver(blocker.path, now: () => now);
    logObserver.onLog(TalkerLog('ignored', time: now));

    await expectLater(logObserver.flush(), completes);
  });

  test('drops records below the configured level', () async {
    final file = File(p.join(tempDir.path, 'frontend.2026-11-07.log'));
    final logObserver = observer(minimumLevel: LogLevel.info);

    logObserver.onLog(
      TalkerLog('debug detail', logLevel: LogLevel.debug, time: now),
    );
    logObserver.onLog(
      TalkerLog('warning detail', logLevel: LogLevel.warning, time: now),
    );
    await logObserver.flush();

    final lines = file.readAsLinesSync();
    expect(lines, hasLength(1));
    expect(lines.single, contains('warning detail'));
  });

  test('frontend records expose the same keys as backend records', () async {
    final file = File(p.join(tempDir.path, 'frontend.2026-11-07.log'));

    final logObserver = observer();
    logObserver.onLog(
      TalkerLog('unified', logLevel: LogLevel.info, key: 'session', time: now),
    );
    await logObserver.flush();

    final frontendRecord =
        jsonDecode(file.readAsLinesSync().single) as Map<String, dynamic>;
    final backendRecord = jsonDecode(
      '{"timestamp":"2026-11-07T12:00:00Z","level":"INFO",'
      '"message":"unified","target":"session"}',
    ) as Map<String, dynamic>;

    expect(frontendRecord.keys.toSet(), backendRecord.keys.toSet());
  });
}
