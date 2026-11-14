import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../setup.dart' as setup;

void main() {
  group('parseSetupArgs', () {
    test('defaults targets per platform', () {
      expect(setup.parseSetupArgs(['macos'], hostArch: 'arm64').targets, [
        'dmg',
      ]);
      expect(setup.parseSetupArgs(['windows'], hostArch: 'amd64').targets, [
        'exe',
        'zip',
      ]);
      expect(setup.parseSetupArgs(['linux'], hostArch: 'amd64').targets, [
        'tar.gz',
      ]);
      expect(setup.parseSetupArgs(['android'], hostArch: 'amd64').targets, [
        'apk',
      ]);
    });

    test('parses explicit arch, --version, and --targets', () {
      final parsed = setup.parseSetupArgs([
        'windows',
        'amd64',
        '--version',
        '0.2.0+3',
        '--targets=exe',
      ]);

      expect(parsed.platform, 'windows');
      expect(parsed.arch, 'amd64');
      expect(parsed.version, '0.2.0+3');
      expect(parsed.targets, ['exe']);
    });

    test('rejects unknown platform or unsupported targets', () {
      expect(() => setup.parseSetupArgs(['ios']), throwsFormatException);
      expect(
        () => setup.parseSetupArgs(['macos', '--targets', 'exe']),
        throwsFormatException,
      );
      expect(
        () => setup.parseSetupArgs(['windows', '--version']),
        throwsFormatException,
      );
    });
  });

  group('packaging config', () {
    test('macos dmg config targets FlSpeak.app and /Applications', () {
      final raw = jsonDecode(
        File('macos/packaging/dmg/make_config.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final rendered = setup.renderAppDmgConfig(
        raw,
        appPath: 'build/macos/Build/Products/Release/FlSpeak.app',
        volumeIconPath: '/tmp/AppIcon.icns',
      );

      expect(rendered['title'], 'FlSpeak');
      expect(rendered['icon'], p.absolute('/tmp/AppIcon.icns'));
      final contents = (rendered['contents']! as List).cast<Map>();
      expect(contents.any((item) => item['path'] == '/Applications'), isTrue);
      expect(
        contents.any(
          (item) =>
              item['type'] == 'file' &&
              item['path'] ==
                  p.absolute('build/macos/Build/Products/Release/FlSpeak.app'),
        ),
        isTrue,
      );
    });

    test('macos PRODUCT_NAME matches FlSpeak.app', () {
      final xcconfig = File('macos/Runner/Configs/AppInfo.xcconfig')
          .readAsStringSync();
      expect(xcconfig, contains('PRODUCT_NAME = FlSpeak'));
    });

    test('windows inno setup template renders all placeholders cleanly', () {
      final template = File('windows/packaging/exe/inno_setup.iss')
          .readAsStringSync();
      final rendered = setup.renderInnoSetupScript(
        template,
        appVersion: '0.2.0',
        outputDir: r'C:\repo\dist',
        outputBaseFilename: 'flspeak-0.2.0-windows-amd64-setup',
        sourceDir: r'C:\repo\build\windows\x64\runner\FlSpeak',
        setupIconFile: r'C:\repo\windows\runner\resources\app_icon.ico',
        chineseIslFile: r'C:\repo\windows\packaging\exe\ChineseSimplified.isl',
        arch: 'amd64',
      );

      expect(RegExp(r'@[A-Z0-9_]+@').hasMatch(rendered), isFalse);
      expect(rendered, contains('AppId={{D4F8E2A1-'));
      expect(rendered, contains('PrivilegesRequired=lowest'));
      expect(rendered, contains('PrivilegesRequiredOverridesAllowed=dialog'));
      expect(rendered, contains('ArchitecturesAllowed=x64compatible'));
      expect(rendered, contains(r'com.dr1mh4x\FlSpeak'));
      expect(setup.innoSetupArch('arm64'), 'arm64');
      expect(
        File('windows/packaging/exe/ChineseSimplified.isl').existsSync(),
        isTrue,
      );
      expect(
        File('windows/runner/resources/app_icon.ico').existsSync(),
        isTrue,
      );
    });
  });
}
