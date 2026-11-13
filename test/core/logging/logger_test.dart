import 'dart:io';

import 'package:flspeak/core/logging/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:talker/talker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flspeak_logger_test_');
  });

  tearDown(() async {
    await shutdownLoggingPipeline();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('passes the shared log directory to Rust', () async {
    String? rustDir;
    final setup = await initLoggingPipeline(
      overrideLogDir: tempDir,
      initRust: (dir) async {
        rustDir = dir;
      },
    );

    expect(setup.error, isNull);
    expect(setup.logDir?.path, tempDir.path);
    expect(rustDir, tempDir.path);
    expect(await tempDir.exists(), isTrue);
  });

  test('Rust init failure keeps Dart file logging available', () async {
    final setup = await initLoggingPipeline(
      overrideLogDir: tempDir,
      initRust: (_) async => throw StateError('boom'),
    );

    expect(setup.error, isA<StateError>());
    expect(setup.logDir?.path, tempDir.path);

    logInfo('after rust failure', target: 'test');
    await shutdownLoggingPipeline();

    final files = tempDir
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith('frontend.'))
        .toList();
    expect(files, isNotEmpty);
    expect(files.first.readAsStringSync(), contains('after rust failure'));
  });

  test('directory creation failure falls back to console logging', () async {
    final blocker = File(p.join(tempDir.path, 'blocked'));
    await blocker.writeAsString('x');

    final setup = await initLoggingPipeline(
      overrideLogDir: Directory(p.join(blocker.path, 'logs')),
      initRust: (_) async {},
    );

    expect(setup.error, isA<FileSystemException>());
    expect(setup.logDir, isNull);
    expect(() => logInfo('console only'), returnsNormally);
  });

  test('hot-switches frontend level and forwards rust level id', () async {
    final forwarded = <String>[];
    final setup = await initLoggingPipeline(
      overrideLogDir: tempDir,
      minimumLevel: LogLevel.info,
      initRust: (_) async {},
    );
    expect(setup.error, isNull);

    logDebug('phase-info-debug', target: 'test');
    logInfo('phase-info-info', target: 'test');

    await syncLogLevel(
      LogLevel.debug,
      rustLevelId: 'debug',
      setRust: (level) async => forwarded.add(level),
    );
    logDebug('phase-debug-debug', target: 'test');

    await syncLogLevel(
      LogLevel.error,
      rustLevelId: 'error',
      setRust: (level) async => forwarded.add(level),
    );
    logWarn('phase-error-warn', target: 'test');
    logError('phase-error-error', target: 'test');

    await shutdownLoggingPipeline();

    final files = tempDir
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith('frontend.'))
        .toList();
    expect(files, isNotEmpty);
    final content = files.first.readAsStringSync();
    expect(forwarded, ['debug', 'error']);
    expect(content, isNot(contains('phase-info-debug')));
    expect(content, contains('phase-info-info'));
    expect(content, contains('phase-debug-debug'));
    expect(content, isNot(contains('phase-error-warn')));
    expect(content, contains('phase-error-error'));
  });

  test('PlainLoggerFormatter outputs lines without box borders', () {
    const formatter = PlainLoggerFormatter();
    final pen = AnsiPen()..green();

    final plain = formatter.fmt(
      LogDetails(
        message: '[app] | 0:28:00 368ms | FlSpeak v0.1.12 started',
        level: LogLevel.info,
        pen: pen,
      ),
      TalkerLoggerSettings(enableColors: false),
    );
    expect(plain, '[app] | 0:28:00 368ms | FlSpeak v0.1.12 started');
    expect(
      plain,
      isNot(anyOf(contains('┌'), contains('│'), contains('└'), contains('─'))),
    );

    final colored = formatter.fmt(
      LogDetails(message: 'line1\nline2', level: LogLevel.info, pen: pen),
      TalkerLoggerSettings(enableColors: true),
    );
    expect(colored, '${pen.write('line1')}\n${pen.write('line2')}');
    expect(
      colored,
      isNot(anyOf(contains('┌'), contains('│'), contains('└'), contains('─'))),
    );
  });
}
