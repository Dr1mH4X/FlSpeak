// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，原始许可证为 GPL-3.0。
// edit、palette、delete 沿用 FlClash 的 lib/ui/icons/app_glyphs.dart 矢量定义，其余为 FlSpeak 业务动作补充。

import 'dart:math' as math;

import 'package:prism_ui/icons/glyph.dart';

/// 二级弹出菜单与 `prism_ui` 原语使用的 24×24 线条矢量图标。
abstract final class AppGlyphs {
  static const edit = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 20, 1),
      GlyphVertex(8.75, 18.75, 1),
      GlyphVertex(20.25, 7.25, 1.5),
      GlyphVertex(16.75, 3.75, 1.5),
      GlyphVertex(5.25, 15.25, 1),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(13.25, 7.25),
      GlyphVertex(16.75, 10.75),
    ], role: GlyphRole.detail),
  ]);

  static const delete = Glyph([
    GlyphPolyline([
      GlyphVertex(5.8, 6.8),
      GlyphVertex(18.2, 6.8),
      GlyphVertex(17.2, 21, 2.5),
      GlyphVertex(6.8, 21, 2.5),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(10, 10.5),
      GlyphVertex(10, 17.5),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14, 10.5),
      GlyphVertex(14, 17.5),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(3.8, 6.8),
      GlyphVertex(20.2, 6.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9, 6.8),
      GlyphVertex(9, 3.2, 1.4),
      GlyphVertex(15, 3.2, 1.4),
      GlyphVertex(15, 6.8),
    ], role: GlyphRole.line),
  ]);

  static const palette = Glyph([
    GlyphPath(
      'M20.59 13.9A8.8 8.8 0 1 0 13.9 20.59A1.2 1.2 0 0 0 14.83 19.28A4 4 0 0 1 19.28 14.83A1.2 1.2 0 0 0 20.59 13.9Z',
    ),
    GlyphCircle(7.54, 13.89, 1.4, role: GlyphRole.detail, solid: true),
    GlyphCircle(7.96, 9.32, 1.4, role: GlyphRole.detail, solid: true),
    GlyphCircle(12, 7.15, 1.4, role: GlyphRole.detail, solid: true),
    GlyphCircle(16.04, 9.32, 1.4, role: GlyphRole.detail, solid: true),
  ]);

  static const login = Glyph([
    GlyphPolyline([
      GlyphVertex(12.5, 4.5),
      GlyphVertex(17.5, 4.5, 2.2),
      GlyphVertex(19.5, 4.5, 2.2),
      GlyphVertex(19.5, 19.5, 2.2),
      GlyphVertex(12.5, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4, 12),
      GlyphVertex(14.8, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(11.3, 8.5),
      GlyphVertex(14.8, 12, 0.4),
      GlyphVertex(11.3, 15.5),
    ], role: GlyphRole.line),
  ], matchTextDirection: true);

  static const logout = Glyph([
    GlyphPolyline([
      GlyphVertex(11.5, 4.5),
      GlyphVertex(4.5, 4.5, 2.2),
      GlyphVertex(4.5, 19.5, 2.2),
      GlyphVertex(11.5, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9.2, 12),
      GlyphVertex(20, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.5, 8.5),
      GlyphVertex(20, 12, 0.4),
      GlyphVertex(16.5, 15.5),
    ], role: GlyphRole.line),
  ], matchTextDirection: true);

  static const screenShare = Glyph([
    GlyphBox(3.5, 4.5, 20.5, 16, 2.5),
    GlyphPolyline([
      GlyphVertex(12, 16),
      GlyphVertex(12, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8.5, 19.5),
      GlyphVertex(15.5, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 13),
      GlyphVertex(12, 7.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9.2, 10.4),
      GlyphVertex(12, 7.6, 0.4),
      GlyphVertex(14.8, 10.4),
    ], role: GlyphRole.detail),
  ]);

  static const stopScreenShare = Glyph([
    GlyphBox(3.5, 4.5, 20.5, 16, 2.5),
    GlyphPolyline([
      GlyphVertex(12, 16),
      GlyphVertex(12, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8.5, 19.5),
      GlyphVertex(15.5, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9.6, 8),
      GlyphVertex(14.4, 12.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14.4, 8),
      GlyphVertex(9.6, 12.6),
    ], role: GlyphRole.detail),
  ]);

  static const chat = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 5.2, 2.4),
      GlyphVertex(20, 5.2, 2.4),
      GlyphVertex(20, 16.4, 2.4),
      GlyphVertex(9.5, 16.4, 1),
      GlyphVertex(5.6, 20, 0.8),
      GlyphVertex(5.6, 16.4),
      GlyphVertex(4, 16.4, 2.4),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(8.2, 9.6),
      GlyphVertex(15.8, 9.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8.2, 12.8),
      GlyphVertex(13.2, 12.8),
    ], role: GlyphRole.detail),
  ]);

  static const poke = Glyph([
    GlyphArc(
      12,
      9.5,
      5.8,
      math.pi * 1.12,
      math.pi * 0.76,
      role: GlyphRole.detail,
    ),
    GlyphCircle(12, 9.5, 2.6, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 12.1),
      GlyphVertex(12, 20.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9, 17.2),
      GlyphVertex(12, 20.2, 0.4),
      GlyphVertex(15, 17.2),
    ], role: GlyphRole.line),
  ]);

  static const permissions = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3.4, 1),
      GlyphVertex(19, 6.2, 1.5),
      GlyphVertex(19, 11.4, 2),
      GlyphVertex(12, 20.6, 1.4),
      GlyphVertex(5, 11.4, 2),
      GlyphVertex(5, 6.2, 1.5),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(9.2, 11.8),
      GlyphVertex(11.1, 13.7, 0.4),
      GlyphVertex(15.1, 9.5),
    ], role: GlyphRole.detail),
  ]);

  static const personRemove = Glyph([
    GlyphCircle(9.5, 7.8, 3.2),
    GlyphArc(9.5, 19.4, 5.6, math.pi, math.pi, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.4, 12),
      GlyphVertex(20.8, 12),
    ], role: GlyphRole.line),
  ]);
}
