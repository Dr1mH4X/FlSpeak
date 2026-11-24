import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

final directoryLauncherProvider = Provider<Future<bool> Function(String)>(
  (ref) => openSystemDirectory,
);

/// 检查当前环境是否具备 GUI 桌面交互能力。
/// - 非桌面系统（移动端/Web）无桌面文件管理器
/// - Linux: 必须存在 DISPLAY 或 WAYLAND_DISPLAY 环境变量
bool hasGuiEnvironment() {
  if (kIsWeb) return false;
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    return false;
  }
  if (Platform.isLinux) {
    return Platform.environment.containsKey('DISPLAY') ||
        Platform.environment.containsKey('WAYLAND_DISPLAY');
  }
  return true;
}

/// 检查当前是否处于单元测试执行环境。
bool isUnitTestEnvironment() {
  return Platform.environment.containsKey('FLUTTER_TEST');
}

/// 跨平台在系统文件管理器（macOS Finder、Windows 资源管理器、Linux 文件管理器）中打开指定目录。
///
/// 若无 GUI 环境、当前平台不支持或打开失败，返回 false，由调用方降级处理（如复制到剪贴板）。
/// 单元测试环境下（FLUTTER_TEST）静默执行，不实际唤起外部 GUI 程序（亦可传入自定义 [processRunner]）。
Future<bool> openSystemDirectory(
  String path, {
  ProcessRunner? processRunner,
  bool? isTest,
  bool? guiAvailable,
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (kIsWeb) return false;

  // 无 GUI 环境（如无头 Linux、非桌面平台）直接返回 false，走复制降级
  if (!(guiAvailable ?? hasGuiEnvironment())) {
    return false;
  }

  try {
    var dirPath = path;
    final file = File(path);
    if (await file.exists()) {
      dirPath = file.parent.path;
    } else {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    // 单元测试环境下若未显式提供 processRunner，静默处理不实际拉起外部 GUI 窗口
    final inTest = isTest ?? isUnitTestEnvironment();
    if (inTest && processRunner == null) {
      return true;
    }

    final runner = processRunner ?? Process.run;
    if (Platform.isMacOS) {
      final res = await runner('open', [dirPath]).timeout(timeout);
      return res.exitCode == 0;
    } else if (Platform.isWindows) {
      final res = await runner('explorer.exe', [dirPath]).timeout(timeout);
      return res.exitCode == 0;
    } else if (Platform.isLinux) {
      final res = await runner('xdg-open', [dirPath]).timeout(timeout);
      return res.exitCode == 0;
    }
  } catch (_) {
    // 忽略异常，降级返回 false
  }
  return false;
}
