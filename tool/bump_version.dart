import 'dart:io';

import 'package:path/path.dart' as p;

/// 验证语义化版本格式（允许附带构建号，如 0.2.0 或 0.2.0+1 或 0.2.0-beta.1）。
final _versionRegex = RegExp(
  r'^(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?:\+(\d+))?$',
);

/// 解析版本字符串为 `(semver, buildNumber)`。
(String semver, String buildNumber) parseVersion(
  String input, {
  String? defaultBuildNumber,
}) {
  final trimmed = input.trim();
  final match = _versionRegex.firstMatch(trimmed);
  if (match == null) {
    throw FormatException('无效的版本格式: "$input"。请使用标准语义化版本，如 0.2.0 或 0.2.0+1。');
  }
  final semver = match.group(1)!;
  final buildNumber = match.group(2) ?? defaultBuildNumber ?? '1';
  return (semver, buildNumber);
}

/// 统一更新全仓版本文件：
/// 1. 根目录 `pubspec.yaml`
/// 2. `plugins/flspeak_ffi/pubspec.yaml`
/// 3. 根目录 `Cargo.toml`
List<String> bumpAllVersions(String inputVersion, {String rootDir = '.'}) {
  final (semver, buildNumber) = parseVersion(inputVersion);
  final fullDartVersion = '$semver+$buildNumber';
  final updatedFiles = <String>[];

  // 1. 根目录 pubspec.yaml
  final rootPubspecFile = File(p.join(rootDir, 'pubspec.yaml'));
  if (rootPubspecFile.existsSync()) {
    final content = rootPubspecFile.readAsStringSync();
    final updated = content.replaceFirst(
      RegExp(r'^version:\s*.*$', multiLine: true),
      'version: $fullDartVersion',
    );
    if (updated != content) {
      rootPubspecFile.writeAsStringSync(updated);
      updatedFiles.add(p.relative(rootPubspecFile.path, from: rootDir));
    }
  }

  // 2. plugins/flspeak_ffi/pubspec.yaml
  final ffiPubspecFile = File(
    p.join(rootDir, 'plugins', 'flspeak_ffi', 'pubspec.yaml'),
  );
  if (ffiPubspecFile.existsSync()) {
    final content = ffiPubspecFile.readAsStringSync();
    final updated = content.replaceFirst(
      RegExp(r'^version:\s*.*$', multiLine: true),
      'version: $semver',
    );
    if (updated != content) {
      ffiPubspecFile.writeAsStringSync(updated);
      updatedFiles.add(p.relative(ffiPubspecFile.path, from: rootDir));
    }
  }

  // 3. 根目录 Cargo.toml ([workspace.package] 下的 version)
  final cargoFile = File(p.join(rootDir, 'Cargo.toml'));
  if (cargoFile.existsSync()) {
    final content = cargoFile.readAsStringSync();
    final updated = _updateWorkspaceCargoVersion(content, semver);
    if (updated != content) {
      cargoFile.writeAsStringSync(updated);
      updatedFiles.add(p.relative(cargoFile.path, from: rootDir));
    }
  }

  return updatedFiles;
}

String _updateWorkspaceCargoVersion(String content, String semver) {
  final lines = content.split('\n');
  var inWorkspacePackage = false;
  var replaced = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      inWorkspacePackage = (line == '[workspace.package]');
    } else if (inWorkspacePackage && !replaced) {
      if (line.startsWith('version') && line.contains('=')) {
        lines[i] = 'version = "$semver"';
        replaced = true;
      }
    }
  }

  return lines.join('\n');
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart tool/bump_version.dart <version>');
    stderr.writeln('例如: dart tool/bump_version.dart 0.2.0');
    stderr.writeln('      dart tool/bump_version.dart 0.2.0+2');
    exit(1);
  }

  final version = args.first;
  try {
    final (semver, buildNumber) = parseVersion(version);
    stdout.writeln('正在同步全仓版本: $semver (构建号: $buildNumber)...');
    final updated = bumpAllVersions(version);
    if (updated.isEmpty) {
      stdout.writeln('所有文件版本已是最新，无须更新。');
    } else {
      stdout.writeln('已成功更新以下文件：');
      for (final file in updated) {
        stdout.writeln('  - $file');
      }
    }
  } catch (e) {
    stderr.writeln('更新版本失败: $e');
    exit(1);
  }
}
