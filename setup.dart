// 打包入口：`dart setup.dart <android|macos|linux|windows> [amd64|arm64] [--version x.y.z]`。
//
// 只做「构建 + 归拢产物」：把平台产物按版本号重命名后放进 dist/。dmg/deb/appimage/msi
// 这类安装包格式需要各自的打包工具，不在骨架范围内（见 docs/ci-cd.md）。
//
// Rust 侧由 plugins/flspeak_ffi 的 native assets 钩子在 `flutter build` 期间自动编译，
// 这里不直接调用 cargo。

import 'dart:io';

import 'package:path/path.dart' as p;

const _platforms = {'android', 'macos', 'linux', 'windows'};

Future<void> main(List<String> args) async {
  final positional = args.where((arg) => !arg.startsWith('--')).toList();
  if (positional.isEmpty || !_platforms.contains(positional.first)) {
    stderr.writeln(
      'Usage: dart setup.dart <${_platforms.join('|')}> [amd64|arm64] [--version x.y.z]',
    );
    exit(2);
  }

  final platform = positional.first;
  final arch = positional.length > 1 ? positional[1] : _hostArch();
  final version = _flagValue(args, '--version') ?? _pubspecVersion();

  _requireHostPlatform(platform);

  final buildNumber = version.contains('+') ? version.split('+').last : '1';
  final buildName = version.split('+').first;

  await _run('flutter', [
    'build',
    platform,
    '--release',
    '--build-name',
    buildName,
    '--build-number',
    buildNumber,
  ]);

  final artifacts = await _collect(platform, buildName, arch);
  if (artifacts.isEmpty) {
    stderr.writeln('没有找到 $platform 的产物，检查 flutter build 的输出。');
    exit(1);
  }

  for (final artifact in artifacts) {
    stdout.writeln('产物：${p.relative(artifact)}');
  }
}

String _hostArch() => Platform.version.contains('arm64') ? 'arm64' : 'amd64';

void _requireHostPlatform(String platform) {
  final host = Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.isWindows
      ? 'windows'
      : null;
  if (platform == 'android') {
    return;
  }
  if (platform != host) {
    stderr.writeln('$platform 只能在 $platform 主机上打包，当前主机是 $host。');
    exit(2);
  }
}

String? _flagValue(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

String _pubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    stderr.writeln('pubspec.yaml 里没有 version。');
    exit(1);
  }
  return match.group(1)!;
}

Future<List<String>> _collect(
  String platform,
  String version,
  String arch,
) async {
  final dist = Directory('dist')..createSync(recursive: true);
  final stem = 'flspeak-$version-$platform-$arch';

  switch (platform) {
    case 'android':
      final apk = File('build/app/outputs/flutter-apk/app-release.apk');
      if (!apk.existsSync()) {
        return const [];
      }
      return [_copy(apk, p.join(dist.path, '$stem.apk'))];
    case 'macos':
      final app = _first(
        Directory('build/macos/Build/Products/Release'),
        '.app',
      );
      if (app == null) {
        return const [];
      }
      return [await _archive(app.path, p.join(dist.path, '$stem.zip'))];
    case 'linux':
      final bundle = _firstBundle(Directory('build/linux'), 'bundle');
      if (bundle == null) {
        return const [];
      }
      return [await _archive(bundle.path, p.join(dist.path, '$stem.tar.gz'))];
    case 'windows':
      final release = _firstRelease(Directory('build/windows'));
      if (release == null) {
        return const [];
      }
      return [await _archive(release.path, p.join(dist.path, '$stem.zip'))];
    default:
      return const [];
  }
}

FileSystemEntity? _first(Directory directory, String suffix) {
  if (!directory.existsSync()) {
    return null;
  }
  final matches = directory.listSync().whereType<FileSystemEntity>().where(
    (entity) => entity.path.endsWith(suffix),
  );
  return matches.isEmpty ? null : matches.first;
}

Directory? _firstBundle(Directory root, String name) {
  if (!root.existsSync()) {
    return null;
  }
  for (final archDir in root.listSync().whereType<Directory>()) {
    final bundle = Directory(p.join(archDir.path, 'release', name));
    if (bundle.existsSync()) {
      return bundle;
    }
  }
  return null;
}

Directory? _firstRelease(Directory root) {
  if (!root.existsSync()) {
    return null;
  }
  for (final archDir in root.listSync().whereType<Directory>()) {
    final release = Directory(p.join(archDir.path, 'runner', 'Release'));
    if (release.existsSync()) {
      return release;
    }
  }
  return null;
}

String _copy(File source, String target) {
  source.copySync(target);
  return target;
}

Future<String> _archive(String source, String target) async {
  if (Platform.isMacOS) {
    // ditto 保留符号链接与扩展属性，dmg/公证之外的场景足够。
    await _run('ditto', [
      '-c',
      '-k',
      '--sequesterRsrc',
      '--keepParent',
      source,
      target,
    ]);
  } else if (Platform.isWindows) {
    await _run('powershell', [
      '-NoProfile',
      '-Command',
      'Compress-Archive -Force -Path "$source" -DestinationPath "$target"',
    ]);
  } else {
    final directory = p.dirname(source);
    final name = p.basename(source);
    await _run('tar', ['-czf', p.absolute(target), '-C', directory, name]);
  }
  return target;
}

Future<void> _run(String executable, List<String> args) async {
  stdout.writeln('> $executable ${args.join(' ')}');
  final result = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await result.exitCode;
  if (code != 0) {
    stderr.writeln('$executable 退出码 $code');
    exit(code);
  }
}
