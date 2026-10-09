import 'dart:io';

import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

/// Flutter 在每次平台构建与 `flutter test` 时运行本钩子：用 Cargo 编译 `rust/`，
/// 把产物注册成 code asset，交给 Flutter 打包与签名。
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await const FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
    ).run(input: input, output: output);
  });
}
