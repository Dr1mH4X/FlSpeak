// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，原始许可证为 GPL-3.0，来源提交 be84736605527034689c95bf27828ff27d912c5e。
// dashboard、settings、reset、sync、add、addCircle、edit、palette、delete、layers、sun、pureBlack、paintbrush、eyedropper、motion、blur、liquidGlass、font、textSize、info、account、photos 沿用 FlClash 的 lib/ui/icons/app_glyphs.dart 矢量定义，其余为 FlSpeak 业务动作补充。

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

  static const dashboard = Glyph([
    GlyphBox(3.5, 3.5, 10.5, 11.5, 2),
    GlyphBox(13.5, 3.5, 20.5, 9.5, 2),
    GlyphBox(3.5, 14.5, 10.5, 20.5, 2),
    GlyphBox(13.5, 12.5, 20.5, 20.5, 2),
  ]);

  static const settings = Glyph([
    GlyphPolyline([
      GlyphVertex(9.87, 5.44, 0.6),
      GlyphVertex(10.09, 3, 0.9),
      GlyphVertex(13.91, 3, 0.9),
      GlyphVertex(14.13, 5.44, 0.6),
      GlyphVertex(16.62, 6.87, 0.6),
      GlyphVertex(18.84, 5.84, 0.9),
      GlyphVertex(20.75, 9.16, 0.9),
      GlyphVertex(18.75, 10.57, 0.6),
      GlyphVertex(18.75, 13.43, 0.6),
      GlyphVertex(20.75, 14.84, 0.9),
      GlyphVertex(18.84, 18.16, 0.9),
      GlyphVertex(16.62, 17.13, 0.6),
      GlyphVertex(14.13, 18.56, 0.6),
      GlyphVertex(13.91, 21, 0.9),
      GlyphVertex(10.09, 21, 0.9),
      GlyphVertex(9.87, 18.56, 0.6),
      GlyphVertex(7.38, 17.13, 0.6),
      GlyphVertex(5.16, 18.16, 0.9),
      GlyphVertex(3.25, 14.84, 0.9),
      GlyphVertex(5.25, 13.43, 0.6),
      GlyphVertex(5.25, 10.57, 0.6),
      GlyphVertex(3.25, 9.16, 0.9),
      GlyphVertex(5.16, 5.84, 0.9),
      GlyphVertex(7.38, 6.87, 0.6),
    ], closed: true),
    GlyphCircle(12, 12, 3, role: GlyphRole.detail),
  ]);

  static const reset = Glyph([
    GlyphArc(
      12,
      13.77,
      7.07,
      math.pi * 1.15,
      math.pi * -1.65,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(12, 6.7),
      GlyphVertex(9.9, 6.7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(13.7, 10.5),
      GlyphVertex(9.9, 6.7, 0.4),
      GlyphVertex(13.7, 2.9),
    ], role: GlyphRole.line),
  ]);

  static const sync = Glyph([
    GlyphArc(
      12,
      12,
      7.78,
      math.pi * 1.144,
      math.pi * 0.889,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(5, 5),
      GlyphVertex(5, 8.6, 0.4),
      GlyphVertex(8.6, 8.6),
    ], role: GlyphRole.line),
    GlyphArc(
      12,
      12,
      7.78,
      math.pi * 0.144,
      math.pi * 0.889,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(19, 19),
      GlyphVertex(19, 15.4, 0.4),
      GlyphVertex(15.4, 15.4),
    ], role: GlyphRole.line),
  ]);

  static const add = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 5),
      GlyphVertex(12, 19),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5, 12),
      GlyphVertex(19, 12),
    ], role: GlyphRole.line),
  ]);

  static const addCircle = Glyph([
    GlyphCircle(12, 12, 8.8, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 7.8),
      GlyphVertex(12, 16.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(7.8, 12),
      GlyphVertex(16.2, 12),
    ], role: GlyphRole.line),
  ]);

  static const layers = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3, 1.5),
      GlyphVertex(20.8, 7.6, 1.2),
      GlyphVertex(12, 12.2, 1.5),
      GlyphVertex(3.2, 7.6, 1.2),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(3.2, 12),
      GlyphVertex(12, 16.6, 1.5),
      GlyphVertex(20.8, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.2, 16.4),
      GlyphVertex(12, 21, 1.5),
      GlyphVertex(20.8, 16.4),
    ], role: GlyphRole.line),
  ]);

  static const sun = Glyph([
    GlyphCircle(12, 12, 4),
    GlyphPolyline([
      GlyphVertex(12, 2.9),
      GlyphVertex(12, 4.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 19.6),
      GlyphVertex(12, 21.1),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(2.9, 12),
      GlyphVertex(4.4, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(19.6, 12),
      GlyphVertex(21.1, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5.57, 5.57),
      GlyphVertex(6.63, 6.63),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18.43, 5.57),
      GlyphVertex(17.37, 6.63),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5.57, 18.43),
      GlyphVertex(6.63, 17.37),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18.43, 18.43),
      GlyphVertex(17.37, 17.37),
    ], role: GlyphRole.line),
  ]);

  static const pureBlack = Glyph([
    GlyphBox(3, 3.5, 21, 16.5, 2.5),
    GlyphPath(
      'M7 6H17A1.5 1.5 0 0 1 18.5 7.5V12.5A1.5 1.5 0 0 1 17 14H7A1.5 1.5 0 0 1 5.5 12.5V7.5A1.5 1.5 0 0 1 7 6Z',
      role: GlyphRole.detail,
      solid: true,
    ),
    GlyphPolyline([
      GlyphVertex(12, 16.5),
      GlyphVertex(12, 20.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8, 20.4),
      GlyphVertex(16, 20.4),
    ], role: GlyphRole.line),
  ]);

  static const paintbrush = Glyph([
    GlyphPolyline([
      GlyphVertex(9.1, 10.51, 1.2),
      GlyphVertex(13.49, 14.9, 1.2),
      GlyphVertex(9.95, 18.43, 3.6),
      GlyphVertex(4.08, 20.2, 1),
      GlyphVertex(5.57, 14.05, 3.6),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(12.64, 8.96, 0.6),
      GlyphVertex(15.04, 11.36, 0.6),
      GlyphVertex(21.4, 5, 1.7),
      GlyphVertex(19, 2.6, 1.7),
    ], closed: true),
  ]);

  static const eyedropper = Glyph([
    GlyphPolyline([
      GlyphVertex(4.79, 19.21, 0.9),
      GlyphVertex(8.46, 18.08, 1.2),
      GlyphVertex(14.4, 12.14, 0.5),
      GlyphVertex(16.24, 13.98, 1),
      GlyphVertex(18.79, 11.43, 1),
      GlyphVertex(17.73, 10.37, 0.5),
      GlyphVertex(21.4, 6.7, 2.9),
      GlyphVertex(17.3, 2.6, 2.9),
      GlyphVertex(13.63, 6.27, 0.5),
      GlyphVertex(12.57, 5.21, 1),
      GlyphVertex(10.02, 7.76, 1),
      GlyphVertex(11.86, 9.6, 0.5),
      GlyphVertex(5.92, 15.54, 1.2),
    ], closed: true),
  ]);

  static const motion = Glyph([
    GlyphCircle(15.6, 12, 5.3),
    GlyphPolyline([
      GlyphVertex(4.4, 8),
      GlyphVertex(7.6, 8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(2.9, 12),
      GlyphVertex(6.5, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4.4, 16),
      GlyphVertex(7.6, 16),
    ], role: GlyphRole.line),
  ]);

  static const blur = Glyph([
    GlyphCircle(9.4, 9.4, 1.6, role: GlyphRole.line, solid: true),
    GlyphCircle(14.6, 9.4, 1.6, role: GlyphRole.line, solid: true),
    GlyphCircle(9.4, 14.6, 1.6, role: GlyphRole.line, solid: true),
    GlyphCircle(14.6, 14.6, 1.6, role: GlyphRole.line, solid: true),
    GlyphCircle(9.4, 4.2, 1.1, role: GlyphRole.line, solid: true),
    GlyphCircle(14.6, 4.2, 1.1, role: GlyphRole.line, solid: true),
    GlyphCircle(4.2, 9.4, 1.1, role: GlyphRole.line, solid: true),
    GlyphCircle(19.8, 9.4, 1.1, role: GlyphRole.line, solid: true),
    GlyphCircle(4.2, 14.6, 1.1, role: GlyphRole.line, solid: true),
    GlyphCircle(19.8, 14.6, 1.1, role: GlyphRole.line, solid: true),
    GlyphCircle(9.4, 19.8, 1.1, role: GlyphRole.line, solid: true),
    GlyphCircle(14.6, 19.8, 1.1, role: GlyphRole.line, solid: true),
  ]);

  static const liquidGlass = Glyph([
    GlyphPath(
      'M12 3.4C14.6 6.2 18.4 10.2 18.4 14.4A6.4 6.4 0 0 1 5.6 14.4'
      'C5.6 10.2 9.4 6.2 12 3.4Z',
    ),
    GlyphArc(
      12,
      14.4,
      3.4,
      math.pi * 0.6,
      math.pi * 0.36,
      role: GlyphRole.detail,
    ),
  ]);

  static const font = Glyph([
    GlyphPolyline([
      GlyphVertex(5.2, 19.6),
      GlyphVertex(12, 4.4, 0.6),
      GlyphVertex(18.8, 19.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(7.7, 14),
      GlyphVertex(16.3, 14),
    ], role: GlyphRole.line),
  ]);

  static const textSize = Glyph([
    GlyphPolyline([
      GlyphVertex(3.2, 4.4),
      GlyphVertex(14, 4.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8.6, 4.4),
      GlyphVertex(8.6, 19.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(14.8, 10.8),
      GlyphVertex(21, 10.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(17.9, 10.8),
      GlyphVertex(17.9, 19.6),
    ], role: GlyphRole.line),
  ]);

  static const workspace = Glyph([
    GlyphArc(12, 12.8, 7.5, math.pi, math.pi, role: GlyphRole.line),
    GlyphBox(3.5, 12.2, 7.5, 19.2, 2.0),
    GlyphBox(16.5, 12.2, 20.5, 19.2, 2.0),
  ]);

  static const workspaceConnected = Glyph([
    GlyphArc(12, 12.8, 7.5, math.pi, math.pi, role: GlyphRole.line),
    GlyphBox(3.5, 12.2, 7.5, 19.2, 2.0),
    GlyphBox(16.5, 12.2, 20.5, 19.2, 2.0),
    GlyphCircle(12, 15.2, 2.1, role: GlyphRole.line, solid: true),
  ]);

  static const info = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphCircle(12, 7.5, 1.4, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(12, 11.8),
      GlyphVertex(12, 16.7),
    ], role: GlyphRole.detail),
  ]);

  static const account = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphCircle(12, 9.4, 2.8, role: GlyphRole.detail),
    GlyphArc(
      12,
      22.6,
      7,
      math.pi * -0.8087,
      math.pi * 0.6173,
      role: GlyphRole.detail,
    ),
  ]);

  static const photos = Glyph([
    GlyphBox(3, 6.4, 17.6, 21, 2.6),
    GlyphPolyline([
      GlyphVertex(6.4, 3),
      GlyphVertex(21, 3, 2.6),
      GlyphVertex(21, 17.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3, 17.2),
      GlyphVertex(7.8, 12.4, 0.8),
      GlyphVertex(12.2, 16.8, 0.8),
      GlyphVertex(14, 15, 0.8),
      GlyphVertex(17.6, 18.6),
    ], role: GlyphRole.detail),
    GlyphCircle(13.4, 10.6, 1.4, role: GlyphRole.detail, solid: true),
  ]);

  static const folder = Glyph([
    GlyphPolyline([
      GlyphVertex(3.5, 6.2, 2),
      GlyphVertex(9.6, 6.2, 1),
      GlyphVertex(11.6, 8.4, 1),
      GlyphVertex(20.5, 8.4, 2),
      GlyphVertex(20.5, 18.8, 2),
      GlyphVertex(3.5, 18.8, 2),
    ], closed: true),
  ]);

  static const media = Glyph([
    GlyphBox(3.5, 4.5, 20.5, 19.5, 2.5),
    GlyphCircle(8.6, 9.2, 1.4, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(5.2, 17.5),
      GlyphVertex(10.2, 12.5, 0.6),
      GlyphVertex(13.4, 15.6, 0.5),
      GlyphVertex(16, 13.2, 0.6),
      GlyphVertex(18.8, 17.5),
    ], role: GlyphRole.detail),
  ]);

  static const person = Glyph([
    GlyphCircle(12, 7.8, 3.2),
    GlyphArc(12, 19.4, 5.6, math.pi, math.pi, role: GlyphRole.line),
  ]);
}
