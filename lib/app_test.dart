// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/app.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('theme text and status contrast: $brightness', () {
      final theme = buildAppTheme(brightness);
      final scheme = theme.colorScheme;
      final status = theme.extension<StatusColors>()!;
      for (final pair in [
        (scheme.onSurface, scheme.surface),
        (scheme.onSurfaceVariant, scheme.surfaceContainerLow),
        (scheme.onPrimary, scheme.primary),
        (scheme.onPrimaryContainer, scheme.primaryContainer),
        (status.live, scheme.surfaceContainer),
      ]) {
        final first = pair.$1.computeLuminance();
        final second = pair.$2.computeLuminance();
        final ratio = first > second
            ? (first + 0.05) / (second + 0.05)
            : (second + 0.05) / (first + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });
  }

  test('深色主题要求浅色系统栏图标', () {
    final style = appSystemUiOverlayStyle(buildAppTheme(Brightness.dark));

    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
  });

  test('浅色主题要求深色系统栏图标', () {
    final style = appSystemUiOverlayStyle(buildAppTheme(Brightness.light));

    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
  });
}
