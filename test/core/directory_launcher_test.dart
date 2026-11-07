import 'dart:async';
import 'dart:io';

import 'package:flspeak/core/directory_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens the directory through the platform runner', () async {
    final dir = await Directory.systemTemp.createTemp('flspeak_launcher_test_');
    addTearDown(() => dir.delete(recursive: true));

    final opened = <String>[];
    final result = await openSystemDirectory(
      dir.path,
      guiAvailable: true,
      isTest: false,
      processRunner: (executable, arguments) async {
        opened.add(executable);
        expect(arguments, [dir.path]);
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(result, isTrue);
    expect(opened, isNotEmpty);
  });

  test('returns false when the platform opener hangs', () async {
    final dir = await Directory.systemTemp.createTemp('flspeak_launcher_test_');
    addTearDown(() => dir.delete(recursive: true));

    final result = await openSystemDirectory(
      dir.path,
      guiAvailable: true,
      isTest: false,
      timeout: const Duration(milliseconds: 10),
      processRunner: (executable, arguments) =>
          Completer<ProcessResult>().future,
    );

    expect(result, isFalse);
  });
}
