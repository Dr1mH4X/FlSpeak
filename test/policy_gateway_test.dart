import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flspeak_ffi/flspeak_ffi.dart';

/// 这组测试真的跨 FFI：加载 Rust 动态库、起 actor、走事件桥。
///
/// 样例刻意只用中性域名：官方域名字面量只允许出现在策略层，
/// `tool/audit_policy.sh` 会扫描 `test/*.dart`。合规语义的断言留在 Rust 侧
/// （`policy` 与 `proto` 的单测）。
///
/// 清理顺序要注意：**先 `shutdown()` 再取消事件订阅**。反过来的话取消会挂住——
/// Rust 侧转发任务要等广播通道关闭才退出。
void main() {
  setUpAll(() => RustLib.init(externalLibrary: _loadBuiltLibrary()));

  test('接受完整 host:port 并归一化', () {
    final profile = validateServerAddress(address: 'ts.example.com:9987');

    expect(profile.host, 'ts.example.com');
    expect(profile.port, 9987);
  });

  test('接受不带端口的 host 并补默认端口', () {
    expect(validateServerAddress(address: 'ts.example.com').port, 9987);
  });

  test('拒绝裸昵称', () {
    expect(
      () => validateServerAddress(address: 'my-server'),
      throwsA(isA<CoreError>()),
    );
  });

  test('拒绝非法端口', () {
    expect(
      () => validateServerAddress(address: 'ts.example.com:99999'),
      throwsA(isA<CoreError>()),
    );
  });

  test('未连接时发文字消息返回明确错误', () async {
    final directory = await Directory.systemTemp.createTemp('flspeak-ffi-idle');
    final session = CoreSession(
      storePath: p.join(directory.path, 'servers.json'),
    );
    try {
      await expectLater(
        session.sendText(targetMode: 2, targetId: 0, message: 'hello'),
        throwsA(isA<CoreError>()),
      );
      expect(await session.state(), isA<CoreSessionState_Disconnected>());
    } finally {
      await session.shutdown();
      await directory.delete(recursive: true);
    }
  });

  test('actor 接受登记并通过事件流推送档案', () async {
    final directory = await Directory.systemTemp.createTemp('flspeak-ffi-test');
    final session = CoreSession(
      storePath: p.join(directory.path, 'servers.json'),
    );
    final received = <CoreEvent>[];
    final subscription = session.events().listen(received.add);
    try {
      expect(await session.listServers(), isEmpty);

      // 等事件桥连上，避免登记命令发出时 Dart 侧还没订阅。
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final profile = await session.registerServer(
        label: 'home',
        address: 'ts.example.com:9987',
      );
      expect(profile.id, isNotEmpty);
      expect(await session.listServers(), hasLength(1));

      expect(
        await _waitFor(
          () => received.whereType<CoreEvent_Servers>().isNotEmpty,
        ),
        isTrue,
        reason: '登记后应收到 Servers 事件',
      );
      expect(
        received.whereType<CoreEvent_Servers>().last.profiles.single.host,
        'ts.example.com',
      );
    } finally {
      await session.shutdown();
      await subscription.cancel();
      await directory.delete(recursive: true);
    }
  });
}

/// `flutter test` 不做应用打包，frb 默认去找的 `flspeak_ffi.framework` 并不存在；
/// native assets 钩子已经把动态库编在 `.dart_tool` 下，这里直接指过去。
ExternalLibrary _loadBuiltLibrary() {
  final root = Directory('.dart_tool/hooks_runner/shared/flspeak_ffi/build');
  File? found;
  if (root.existsSync()) {
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (p.basename(file.path) == _libraryFileName &&
          p.split(file.path).contains('release')) {
        found = file;
        break;
      }
    }
  }
  if (found == null) {
    fail(
      '没找到 $_libraryFileName：先跑一次 flutter test 或 flutter build，'
      '让 native assets 钩子把 Rust 编出来',
    );
  }
  return ExternalLibrary.open(found.path);
}

String get _libraryFileName {
  if (Platform.isMacOS) {
    return 'libflspeak_ffi.dylib';
  }
  if (Platform.isWindows) {
    return 'flspeak_ffi.dll';
  }
  return 'libflspeak_ffi.so';
}

Future<bool> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return predicate();
}
