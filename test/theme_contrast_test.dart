import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/theme/app_theme.dart';

/// 主题里每个颜色配对的对比度闸门。
///
/// 分两类要求：会被当作正文读的颜色必须到 4.5:1（WCAG 2.1 AA 正文），
/// 只用于边界与状态点的颜色必须到 3:1（WCAG 1.4.11 非文本对比）。
/// 颜色改错了这里会红，比肉眼可靠。
double _luminance(Color color) {
  double channel(double value) {
    final v = value / 255;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r * 255) +
      0.7152 * channel(color.g * 255) +
      0.0722 * channel(color.b * 255);
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final high = math.max(la, lb);
  final low = math.min(la, lb);
  return (high + 0.05) / (low + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    final theme = buildAppTheme(brightness);
    final scheme = theme.colorScheme;
    final status = theme.extension<StatusColors>()!;
    final label = brightness.name;

    test('$label：正文颜色都到 4.5:1', () {
      final failures = <String>[];
      final pairs = <String, (Color, Color)>{
        'onSurface 在 surface 上': (scheme.onSurface, scheme.surface),
        'onSurface 在 surfaceContainerLow 上': (
          scheme.onSurface,
          scheme.surfaceContainerLow,
        ),
        'onSurface 在 surfaceContainerHigh 上': (
          scheme.onSurface,
          scheme.surfaceContainerHigh,
        ),
        'onSurfaceVariant 在 surface 上': (
          scheme.onSurfaceVariant,
          scheme.surface,
        ),
        'onSurfaceVariant 在 surfaceContainerLow 上': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerLow,
        ),
        'onSurfaceVariant 在 surfaceContainerLowest 上（输入框底色）': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerLowest,
        ),
        'onSurfaceVariant 在 surfaceContainerHigh 上': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHigh,
        ),
        'onPrimary 在 primary 上': (scheme.onPrimary, scheme.primary),
        'onPrimaryContainer 在 primaryContainer 上': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'onErrorContainer 在 errorContainer 上': (
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
        'live 在 surface 上': (status.live, scheme.surface),
        'live 在 surfaceContainerLow 上': (
          status.live,
          scheme.surfaceContainerLow,
        ),
        'live 在 surfaceContainerHigh 上': (
          status.live,
          scheme.surfaceContainerHigh,
        ),
        'live 在 surfaceContainerLowest 上': (
          status.live,
          scheme.surfaceContainerLowest,
        ),
        'deny 在 surface 上': (status.deny, scheme.surface),
        'deny 在 surfaceContainerLow 上': (
          status.deny,
          scheme.surfaceContainerLow,
        ),
        'primary 在 surface 上': (scheme.primary, scheme.surface),
        'primary 在 surfaceContainerLowest 上': (
          scheme.primary,
          scheme.surfaceContainerLowest,
        ),
      };
      pairs.forEach((name, pair) {
        final ratio = contrastRatio(pair.$1, pair.$2);
        if (ratio < 4.5) {
          failures.add('$name = ${ratio.toStringAsFixed(2)}');
        }
      });
      expect(failures, isEmpty, reason: '$label 下正文对比度不足：$failures');
    });

    test('$label：边界都到 3:1', () {
      final failures = <String>[];
      final pairs = <String, (Color, Color)>{
        'outline 在 surface 上': (scheme.outline, scheme.surface),
        'outline 在 surfaceContainerLow 上（卡片底色）': (
          scheme.outline,
          scheme.surfaceContainerLow,
        ),
        'outline 在 surfaceContainerLowest 上（输入框底色）': (
          scheme.outline,
          scheme.surfaceContainerLowest,
        ),
        'outline 在 surfaceContainerHigh 上': (
          scheme.outline,
          scheme.surfaceContainerHigh,
        ),
      };
      pairs.forEach((name, pair) {
        final ratio = contrastRatio(pair.$1, pair.$2);
        if (ratio < 3) {
          failures.add('$name = ${ratio.toStringAsFixed(2)}');
        }
      });
      expect(failures, isEmpty, reason: '$label 下边界对比度不足：$failures');
    });
  }

  test('分隔线在两种主题下都看得见', () {
    for (final brightness in Brightness.values) {
      final scheme = buildAppTheme(brightness).colorScheme;
      final ratio = contrastRatio(scheme.outlineVariant, scheme.surface);
      // 分隔线是装饰性的，不要求 3:1；但低到 1.15:1 就等于没有。
      expect(ratio, greaterThan(1.15), reason: '${brightness.name} 的分隔线不可见');
    }
  });

  test('服务器磁贴底色上的标记始终到 4.5:1', () {
    final failures = <String>[];
    for (final brightness in Brightness.values) {
      for (var index = 0; index < 500; index++) {
        final id = 'host$index.example.com:9987';
        final background = ServerPalette.of(id, brightness);
        final ratio = contrastRatio(readableOn(background), background);
        if (ratio < 4.5) {
          failures.add('${brightness.name}/$id = ${ratio.toStringAsFixed(2)}');
        }
      }
    }
    expect(failures, isEmpty, reason: '磁贴前景对比度不足：$failures');
  });

  test('服务器磁贴的感知亮度落在同一区间，一排看过去一样重', () {
    for (final brightness in Brightness.values) {
      final luminances = [
        for (var index = 0; index < 500; index++)
          ServerPalette.of(
            'host$index.example.com:9987',
            brightness,
          ).computeLuminance(),
      ]..sort();
      expect(luminances.first, greaterThanOrEqualTo(0.08));
      expect(luminances.last, lessThanOrEqualTo(0.18));
      // 最亮与最暗之间不应出现明显跳变。
      expect(luminances.last - luminances.first, lessThan(0.10));
    }
  });

  test('同一台服务器在两种主题下拿到同一个色相', () {
    for (final id in ['a.example.com:9987', 'b.example.com:9987']) {
      final dark = ServerPalette.of(id, Brightness.dark);
      final light = ServerPalette.of(id, Brightness.light);
      expect(
        HSLColor.fromColor(dark).hue,
        closeTo(HSLColor.fromColor(light).hue, 0.001),
      );
    }
  });
}
