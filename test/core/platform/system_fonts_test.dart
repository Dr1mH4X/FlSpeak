import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/platform/system_fonts.dart';

void main() {
  test('sortFontFamilies trims, drops hidden leading-dot names, deduplicates case-insensitively, and sorts', () {
    final result = sortFontFamilies([
      ' .SF NS ',
      'PingFang SC',
      'inter',
      'Inter',
      '   ',
      'Arial',
    ]);
    expect(result, ['Arial', 'inter', 'PingFang SC']);
  });

  test('androidFontFamilies parses family attributes from fonts.xml', () {
    const sample = '''
<familyset version="23">
  <family name="sans-serif">
    <font weight="400">Roboto-Regular.ttf</font>
  </family>
  <family lang="zh-Hans" name="noto-sans-cjk">
    <font weight="400">NotoSansCJK-Regular.ttc</font>
  </family>
</familyset>
''';
    expect(androidFontFamilies(sample), ['sans-serif', 'noto-sans-cjk']);
  });

  test('loadSystemFontFamilies handles reader failures gracefully', () async {
    final original = systemFontFamiliesReader;
    addTearDown(() => systemFontFamiliesReader = original);

    systemFontFamiliesReader = () async => throw StateError('boom');
    expect(await loadSystemFontFamilies(), isEmpty);
  });

  test('loadSystemFontFamilies enumerates macOS CoreText families', () async {
    if (!Platform.isMacOS) {
      return;
    }
    final families = await loadSystemFontFamilies();
    expect(families, isNotEmpty);
  });
}
