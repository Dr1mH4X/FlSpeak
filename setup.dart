// 打包入口：`dart setup.dart <android|macos|linux|windows> [amd64|arm64] [--version x.y.z] [--targets ...]`.
//
// 执行 `flutter build <platform> --release` 并按版本号归拢或打包产物到 `dist/`：
// - macOS：通过 `appdmg` 与 `macos/packaging/dmg/make_config.json` 生成 `.dmg`；
// - Windows：通过 Inno Setup (`ISCC.exe`) 与 `windows/packaging/exe/` 生成 `-setup.exe` 安装包与便携 `.zip`；
// - Linux：归拢为 `.tar.gz`；
// - Android：按 ABI 归拢为 `.apk`。
//
// Rust 侧由 plugins/flspeak_ffi 的 native assets 钩子在 `flutter build` 期间自动编译，
// 这里不直接调用 cargo。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tool/bump_version.dart';

const _platforms = {'android', 'macos', 'linux', 'windows'};

const _defaultTargets = <String, List<String>>{
  'android': ['apk'],
  'macos': ['dmg'],
  'linux': ['tar.gz'],
  'windows': ['exe', 'zip'],
};

const _supportedTargets = <String, Set<String>>{
  'android': {'apk'},
  'macos': {'dmg', 'zip'},
  'linux': {'tar.gz'},
  'windows': {'exe', 'zip'},
};

const _flSpeakAppId = 'D4F8E2A1-6C3B-4A9E-8F12-7B5C9D0E3A41';

const _iconsetFiles = <String, String>{
  'icon_16x16.png': 'app_icon_16.png',
  'icon_16x16@2x.png': 'app_icon_32.png',
  'icon_32x32.png': 'app_icon_32.png',
  'icon_32x32@2x.png': 'app_icon_64.png',
  'icon_128x128.png': 'app_icon_128.png',
  'icon_128x128@2x.png': 'app_icon_256.png',
  'icon_256x256.png': 'app_icon_256.png',
  'icon_256x256@2x.png': 'app_icon_512.png',
  'icon_512x512.png': 'app_icon_512.png',
  'icon_512x512@2x.png': 'app_icon_1024.png',
};

/// 解析后的打包命令行参数。
class SetupArgs {
  const SetupArgs({
    required this.platform,
    required this.arch,
    required this.version,
    required this.targets,
  });

  final String platform;
  final String arch;
  final String? version;
  final List<String> targets;
}

/// 解析 `setup.dart` 命令行参数；参数非法时抛出 [FormatException]。
SetupArgs parseSetupArgs(List<String> args, {String? hostArch}) {
  final positional = <String>[];
  String? version;
  String? rawTargets;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--version') {
      if (i + 1 >= args.length) {
        throw const FormatException('--version 缺少版本号参数');
      }
      version = args[++i];
    } else if (arg.startsWith('--version=')) {
      version = arg.substring('--version='.length);
    } else if (arg == '--targets') {
      if (i + 1 >= args.length) {
        throw const FormatException('--targets 缺少目标格式参数');
      }
      rawTargets = args[++i];
    } else if (arg.startsWith('--targets=')) {
      rawTargets = arg.substring('--targets='.length);
    } else if (arg.startsWith('--')) {
      throw FormatException('未知参数: $arg');
    } else {
      positional.add(arg);
    }
  }

  if (positional.isEmpty || !_platforms.contains(positional.first)) {
    throw FormatException(
      'Usage: dart setup.dart <${_platforms.join('|')}> [amd64|arm64] '
      '[--version x.y.z] [--targets ...]',
    );
  }

  final platform = positional.first;
  final arch = positional.length > 1
      ? positional[1]
      : (hostArch ?? _hostArch());
  final targets = resolvePackageTargets(platform, rawTargets);

  return SetupArgs(
    platform: platform,
    arch: arch,
    version: version,
    targets: targets,
  );
}

/// 解析目标平台对应的打包产物列表，并校验受支持的目标格式。
List<String> resolvePackageTargets(String platform, String? rawTargets) {
  final defaults = _defaultTargets[platform];
  final supported = _supportedTargets[platform];
  if (defaults == null || supported == null) {
    throw FormatException('不支持的平台: $platform');
  }
  if (rawTargets == null || rawTargets.trim().isEmpty) {
    return defaults;
  }

  final parsed = rawTargets
      .split(',')
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toList();
  if (parsed.isEmpty) {
    throw const FormatException('--targets 不能为空');
  }
  for (final target in parsed) {
    if (!supported.contains(target)) {
      throw FormatException(
        '$platform 不支持打包目标 "$target"；可选值: ${supported.join(', ')}',
      );
    }
  }
  return parsed;
}

/// 将 `macos/packaging/dmg/make_config.json` 渲染为可直接传给 `appdmg` 的配置。
Map<String, Object?> renderAppDmgConfig(
  Map<String, Object?> template, {
  required String appPath,
  String? volumeIconPath,
}) {
  final rendered = Map<String, Object?>.from(template);
  final rawContents = template['contents'];
  if (rawContents is List) {
    rendered['contents'] = rawContents.map((entry) {
      if (entry is Map) {
        final copy = Map<String, Object?>.from(entry);
        final path = copy['path'];
        if (copy['type'] == 'file' && path is String && path.endsWith('.app')) {
          copy['path'] = p.absolute(appPath);
        }
        return copy;
      }
      return entry;
    }).toList();
  }
  if (volumeIconPath != null && volumeIconPath.isNotEmpty) {
    rendered['icon'] = p.absolute(volumeIconPath);
  }
  return rendered;
}

/// 将架构名映射为 Inno Setup 的架构标识。
String innoSetupArch(String arch) =>
    arch == 'arm64' ? 'arm64' : 'x64compatible';

/// 替换 Inno Setup 模板中的占位变量。
String renderInnoSetupScript(
  String template, {
  required String appVersion,
  required String outputDir,
  required String outputBaseFilename,
  required String sourceDir,
  required String setupIconFile,
  required String chineseIslFile,
  required String arch,
  String appId = _flSpeakAppId,
}) {
  final replacements = <String, String>{
    '@APP_ID@': appId,
    '@APP_VERSION@': appVersion,
    '@OUTPUT_DIR@': outputDir,
    '@OUTPUT_BASE_FILENAME@': outputBaseFilename,
    '@SOURCE_DIR@': sourceDir,
    '@SETUP_ICON_FILE@': setupIconFile,
    '@CHINESE_ISL_FILE@': chineseIslFile,
    '@ARCH@': innoSetupArch(arch),
  };
  var result = template;
  for (final MapEntry(:key, :value) in replacements.entries) {
    result = result.replaceAll(key, value);
  }
  return result;
}

Future<void> main(List<String> args) async {
  late final SetupArgs parsed;
  try {
    parsed = parseSetupArgs(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exit(2);
  }

  final platform = parsed.platform;
  final arch = parsed.arch;
  final version = parsed.version ?? _pubspecVersion();

  _requireHostPlatform(platform);

  bumpAllVersions(version);

  final buildNumber = version.contains('+') ? version.split('+').last : '1';
  final buildName = version.split('+').first;
  final subcommand = platform == 'android' ? 'apk' : platform;

  await _run('flutter', [
    'build',
    subcommand,
    '--release',
    if (platform == 'android') '--split-per-abi',
    '--build-name',
    buildName,
    '--build-number',
    buildNumber,
  ]);

  final artifacts = await _collect(platform, buildName, arch, parsed.targets);
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
  List<String> targets,
) async {
  final dist = Directory('dist')..createSync(recursive: true);
  final stem = 'flspeak-$version-$platform-$arch';

  switch (platform) {
    case 'android':
      final dir = Directory('build/app/outputs/flutter-apk');
      if (!dir.existsSync()) {
        return const [];
      }
      final collected = <String>[];
      final splitRegex = RegExp(r'^app-(.+)-release\.apk$');
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final match = splitRegex.firstMatch(p.basename(file.path));
        if (match != null) {
          final abi = match.group(1)!;
          collected.add(
            _copy(file, p.join(dist.path, 'flspeak-$version-android-$abi.apk')),
          );
        }
      }
      if (collected.isNotEmpty) {
        return collected;
      }
      final apk = File(p.join(dir.path, 'app-release.apk'));
      if (apk.existsSync()) {
        return [_copy(apk, p.join(dist.path, '$stem.apk'))];
      }
      return const [];
    case 'macos':
      final releaseDir = Directory('build/macos/Build/Products/Release');
      final preferredApp = Directory(p.join(releaseDir.path, 'FlSpeak.app'));
      final app = preferredApp.existsSync()
          ? preferredApp
          : _first(releaseDir, '.app');
      if (app == null) {
        return const [];
      }
      final collected = <String>[];
      for (final target in targets) {
        if (target == 'dmg') {
          collected.add(
            await _packageMacosDmg(
              appPath: app.path,
              outputPath: p.join(dist.path, '$stem.dmg'),
            ),
          );
        } else if (target == 'zip') {
          collected.add(
            await _archive(app.path, p.join(dist.path, '$stem.zip')),
          );
        }
      }
      return collected;
    case 'linux':
      final bundle = _firstBundle(Directory('build/linux'), 'bundle');
      if (bundle == null) {
        return const [];
      }
      final stagedBundle = _prepareNamedDirectory(bundle, 'FlSpeak');
      return [
        await _archive(stagedBundle.path, p.join(dist.path, '$stem.tar.gz')),
      ];
    case 'windows':
      final release = _firstRelease(Directory('build/windows'));
      if (release == null) {
        return const [];
      }
      final stagedRelease = _prepareNamedDirectory(release, 'FlSpeak');
      final collected = <String>[];
      for (final target in targets) {
        if (target == 'exe') {
          collected.add(
            await _packageWindowsExe(
              sourceDir: stagedRelease.path,
              distDir: dist.path,
              outputBaseFilename: '$stem-setup',
              version: version,
              arch: arch,
            ),
          );
        } else if (target == 'zip') {
          collected.add(
            await _archive(stagedRelease.path, p.join(dist.path, '$stem.zip')),
          );
        }
      }
      return collected;
    default:
      return const [];
  }
}

Future<String> _packageMacosDmg({
  required String appPath,
  required String outputPath,
}) async {
  final appdmgExe = await _ensureAppDmg();
  final configFile = File(
    p.join('macos', 'packaging', 'dmg', 'make_config.json'),
  );
  if (!configFile.existsSync()) {
    stderr.writeln('缺少 DMG 配置文件：${configFile.path}');
    exit(1);
  }

  final template =
      jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  final tempDir = Directory.systemTemp.createTempSync('flspeak_dmg_');
  try {
    final icnsPath = await _buildMacosIcns(tempDir);
    final config = renderAppDmgConfig(
      template,
      appPath: appPath,
      volumeIconPath: icnsPath,
    );
    final specFile = File(p.join(tempDir.path, 'appdmg.json'))
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config));

    final targetFile = File(outputPath);
    if (targetFile.existsSync()) {
      targetFile.deleteSync();
    }

    await _run(appdmgExe, [specFile.path, p.absolute(outputPath)]);
    return outputPath;
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

Future<String?> _buildMacosIcns(Directory tempDir) async {
  final appiconset = Directory(
    p.join('macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'),
  );
  if (!appiconset.existsSync()) {
    return null;
  }

  final iconsetDir = Directory(p.join(tempDir.path, 'AppIcon.iconset'))
    ..createSync(recursive: true);
  for (final MapEntry(:key, :value) in _iconsetFiles.entries) {
    final src = File(p.join(appiconset.path, value));
    if (!src.existsSync()) {
      return null;
    }
    src.copySync(p.join(iconsetDir.path, key));
  }

  final icnsPath = p.join(tempDir.path, 'AppIcon.icns');
  final result = await Process.run('iconutil', [
    '-c',
    'icns',
    iconsetDir.path,
    '-o',
    icnsPath,
  ]);
  if (result.exitCode != 0 || !File(icnsPath).existsSync()) {
    return null;
  }
  return icnsPath;
}

Future<String> _ensureAppDmg() async {
  final existing = await _findAppDmgExecutable();
  if (existing != null) {
    return existing;
  }

  stdout.writeln('正在安装 appdmg（DMG 打包工具）...');
  await _run('npm', ['install', '-g', 'appdmg']);

  final installed = await _findAppDmgExecutable();
  if (installed != null) {
    return installed;
  }

  stderr.writeln('安装 appdmg 后仍无法在 PATH 或 npm 全局目录中找到它。');
  exit(1);
}

Future<String?> _findAppDmgExecutable() async {
  final which = await Process.run('which', ['appdmg']);
  if (which.exitCode == 0) {
    final path = (which.stdout as String).trim();
    if (path.isNotEmpty) {
      return path;
    }
  }
  final prefix = await Process.run('npm', ['prefix', '-g']);
  if (prefix.exitCode == 0) {
    final binPath = p.join((prefix.stdout as String).trim(), 'bin', 'appdmg');
    if (File(binPath).existsSync()) {
      return binPath;
    }
  }
  return null;
}

Future<String> _packageWindowsExe({
  required String sourceDir,
  required String distDir,
  required String outputBaseFilename,
  required String version,
  required String arch,
}) async {
  final isccExe = await _findInnoSetupCompiler();
  final templateFile = File(
    p.join('windows', 'packaging', 'exe', 'inno_setup.iss'),
  );
  final chineseIslFile = File(
    p.join('windows', 'packaging', 'exe', 'ChineseSimplified.isl'),
  );
  final iconFile = File(
    p.join('windows', 'runner', 'resources', 'app_icon.ico'),
  );
  for (final requiredFile in [templateFile, chineseIslFile, iconFile]) {
    if (!requiredFile.existsSync()) {
      stderr.writeln('缺少 Windows 安装包必需文件：${requiredFile.path}');
      exit(1);
    }
  }

  final script = renderInnoSetupScript(
    templateFile.readAsStringSync(),
    appVersion: version,
    outputDir: p.absolute(distDir),
    outputBaseFilename: outputBaseFilename,
    sourceDir: p.absolute(sourceDir),
    setupIconFile: p.absolute(iconFile.path),
    chineseIslFile: p.absolute(chineseIslFile.path),
    arch: arch,
  );

  final tempDir = Directory.systemTemp.createTempSync('flspeak_inno_');
  try {
    final issFile = File(p.join(tempDir.path, 'flspeak.iss'));
    // 写入 UTF-8 BOM，确保英文系统区域的 Inno Setup 正确解析中文自定义文案。
    issFile.writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(script)]);
    await _run(isccExe, [issFile.path], runInShell: false);
    final outputPath = p.join(distDir, '$outputBaseFilename.exe');
    if (!File(outputPath).existsSync()) {
      stderr.writeln('Inno Setup 未生成预期安装包：$outputPath');
      exit(1);
    }
    return outputPath;
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

Future<String> _findInnoSetupCompiler() async {
  final whereResult = await Process.run('where', ['ISCC.exe']);
  if (whereResult.exitCode == 0) {
    final firstLine = (whereResult.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) {
      return firstLine;
    }
  }

  final localAppData = Platform.environment['LOCALAPPDATA'];
  final candidates = <String>[
    r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    r'C:\Program Files\Inno Setup 6\ISCC.exe',
    if (localAppData != null && localAppData.isNotEmpty)
      p.join(localAppData, 'Programs', 'Inno Setup 6', 'ISCC.exe'),
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  stderr.writeln(
    '未找到 Inno Setup 6 (ISCC.exe)。请先安装 Inno Setup 6'
    '（如 winget install JRSoftware.InnoSetup）。',
  );
  exit(1);
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
    final named = Directory(p.join(archDir.path, 'release', 'FlSpeak'));
    if (named.existsSync()) {
      return named;
    }
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
    final named = Directory(p.join(archDir.path, 'runner', 'FlSpeak'));
    if (named.existsSync()) {
      return named;
    }
    final release = Directory(p.join(archDir.path, 'runner', 'Release'));
    if (release.existsSync()) {
      return release;
    }
  }
  return null;
}

Directory _prepareNamedDirectory(Directory source, String targetName) {
  if (p.basename(source.path) == targetName) {
    return source;
  }
  final target = Directory(p.join(source.parent.path, targetName));
  if (target.existsSync()) {
    target.deleteSync(recursive: true);
  }
  return source.renameSync(target.path);
}

String _copy(File source, String target) {
  source.copySync(target);
  return target;
}

Future<String> _archive(String source, String target) async {
  if (Platform.isMacOS) {
    // ditto 保留符号链接与扩展属性，非公证 zip 场景足够。
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

Future<void> _run(
  String executable,
  List<String> args, {
  bool? runInShell,
}) async {
  stdout.writeln('> $executable ${args.join(' ')}');
  final result = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: runInShell ?? Platform.isWindows,
  );
  final code = await result.exitCode;
  if (code != 0) {
    stderr.writeln('$executable 退出码 $code');
    exit(code);
  }
}
