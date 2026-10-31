import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'bump_version.dart';

void main() {
  group('parseVersion', () {
    test('parses plain semver and defaults build number to 1', () {
      final (semver, buildNumber) = parseVersion('0.2.0');
      expect(semver, '0.2.0');
      expect(buildNumber, '1');
    });

    test('parses semver with explicit build number', () {
      final (semver, buildNumber) = parseVersion('0.3.5+42');
      expect(semver, '0.3.5');
      expect(buildNumber, '42');
    });

    test('parses prerelease version', () {
      final (semver, buildNumber) = parseVersion('1.0.0-rc.1+7');
      expect(semver, '1.0.0-rc.1');
      expect(buildNumber, '7');
    });

    test(
      'uses defaultBuildNumber when provided and input has no build number',
      () {
        final (semver, buildNumber) = parseVersion(
          '0.2.0',
          defaultBuildNumber: '8',
        );
        expect(semver, '0.2.0');
        expect(buildNumber, '8');
      },
    );

    test('throws FormatException on invalid version strings', () {
      expect(() => parseVersion('invalid'), throwsFormatException);
      expect(() => parseVersion('v0.2.0'), throwsFormatException);
      expect(() => parseVersion(''), throwsFormatException);
    });
  });

  group('bumpAllVersions', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('bump_version_test_');

      // 创建根目录 pubspec.yaml
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: flspeak
description: flspeak
publish_to: 'none'
version: 0.1.0+1

dependencies:
  flutter:
    sdk: flutter
''');

      // 创建 plugins/flspeak_ffi/pubspec.yaml
      final ffiDir = Directory(p.join(tempDir.path, 'plugins', 'flspeak_ffi'))
        ..createSync(recursive: true);
      File(p.join(ffiDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: flspeak_ffi
version: 0.0.1
publish_to: none
''');

      // 创建根目录 Cargo.toml
      File(p.join(tempDir.path, 'Cargo.toml')).writeAsStringSync('''
[workspace]
resolver = "3"
members = ["core/proto"]

[workspace.package]
version = "0.0.0"
edition = "2024"

[workspace.dependencies]
serde = "1"
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'synchronizes version across pubspec.yaml, ffi pubspec, and Cargo.toml',
      () {
        final updatedFiles = bumpAllVersions('0.2.0+3', rootDir: tempDir.path);

        expect(updatedFiles, contains('pubspec.yaml'));
        expect(
          updatedFiles,
          contains(p.join('plugins', 'flspeak_ffi', 'pubspec.yaml')),
        );
        expect(updatedFiles, contains('Cargo.toml'));

        // 验证根目录 pubspec.yaml
        final rootPubspec = File(p.join(tempDir.path, 'pubspec.yaml'))
            .readAsStringSync();
        expect(rootPubspec, contains('version: 0.2.0+3'));

        // 验证 plugins/flspeak_ffi/pubspec.yaml
        final ffiPubspec = File(
          p.join(tempDir.path, 'plugins', 'flspeak_ffi', 'pubspec.yaml'),
        ).readAsStringSync();
        expect(ffiPubspec, contains('version: 0.2.0'));

        // 验证 Cargo.toml
        final cargoToml = File(p.join(tempDir.path, 'Cargo.toml'))
            .readAsStringSync();
        expect(cargoToml, contains('version = "0.2.0"'));
      },
    );

    test('returns empty list when files are already at target version', () {
      bumpAllVersions('0.2.0+3', rootDir: tempDir.path);
      final secondRun = bumpAllVersions('0.2.0+3', rootDir: tempDir.path);
      expect(secondRun, isEmpty);
    });
  });
}
