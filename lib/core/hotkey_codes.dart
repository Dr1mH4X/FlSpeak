import 'dart:io';

import 'package:flutter/services.dart';

/// 全局「按住说话」快捷键的跨平台键码换算。
///
/// 持久化存 Flutter `LogicalKeyboardKey.keyId`（跨平台稳定），注册到系统时按
/// 平台取原生键码：macOS 是 Carbon 虚拟键码，Windows 是虚拟键码，Linux 是
/// X11 键码（evdev + 8）。裸修饰键无法注册全局热键（macOS/Windows 都要求一
/// 个非修饰键），所以不在支持范围里。
///
/// 同一个物理键在三种键盘布局下键码未必一致（如非 ANSI 布局的标点），这里
/// 按美式布局登记；这是全局热键的常规取舍，TeamSpeak 也如此。

/// 当前平台下该逻辑键的原生键码；平台不支持或键不在支持列表里返回 `null`。
int? nativePttKeyCode(LogicalKeyboardKey key) {
  final codes = _codes[key.keyId];
  if (codes == null) {
    return null;
  }
  return switch (Platform.operatingSystem) {
    'macos' => codes.$1,
    'windows' => codes.$2,
    'linux' => codes.$3,
    _ => null,
  };
}

/// 该逻辑键能否在当前平台注册为全局热键。
bool isSupportedPttHotkey(LogicalKeyboardKey key) =>
    nativePttKeyCode(key) != null;

/// 展示用键名。`keyLabel` 对个别键不够友好，这里补一层人工命名。
String pttHotkeyDisplayName(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.space => 'Space',
  LogicalKeyboardKey.capsLock => 'Caps Lock',
  _ => key.keyLabel.isEmpty ? 'Unknown' : key.keyLabel,
};

/// (macOS Carbon, Windows VK, X11 keycode) 三元组；某平台没有该键时为 null。
typedef _PlatformCodes = (int?, int, int);

final Map<int, _PlatformCodes> _codes = _buildCodes();

Map<int, _PlatformCodes> _buildCodes() {
  final table = <LogicalKeyboardKey, _PlatformCodes>{
    // 字母。
    LogicalKeyboardKey.keyA: (0x00, 0x41, 38),
    LogicalKeyboardKey.keyB: (0x0B, 0x42, 56),
    LogicalKeyboardKey.keyC: (0x08, 0x43, 54),
    LogicalKeyboardKey.keyD: (0x02, 0x44, 40),
    LogicalKeyboardKey.keyE: (0x0E, 0x45, 26),
    LogicalKeyboardKey.keyF: (0x03, 0x46, 41),
    LogicalKeyboardKey.keyG: (0x05, 0x47, 42),
    LogicalKeyboardKey.keyH: (0x04, 0x48, 43),
    LogicalKeyboardKey.keyI: (0x22, 0x49, 31),
    LogicalKeyboardKey.keyJ: (0x26, 0x4A, 44),
    LogicalKeyboardKey.keyK: (0x28, 0x4B, 45),
    LogicalKeyboardKey.keyL: (0x25, 0x4C, 46),
    LogicalKeyboardKey.keyM: (0x2E, 0x4D, 58),
    LogicalKeyboardKey.keyN: (0x2D, 0x4E, 57),
    LogicalKeyboardKey.keyO: (0x1F, 0x4F, 32),
    LogicalKeyboardKey.keyP: (0x23, 0x50, 33),
    LogicalKeyboardKey.keyQ: (0x0C, 0x51, 24),
    LogicalKeyboardKey.keyR: (0x0F, 0x52, 27),
    LogicalKeyboardKey.keyS: (0x01, 0x53, 39),
    LogicalKeyboardKey.keyT: (0x11, 0x54, 28),
    LogicalKeyboardKey.keyU: (0x20, 0x55, 30),
    LogicalKeyboardKey.keyV: (0x09, 0x56, 55),
    LogicalKeyboardKey.keyW: (0x0D, 0x57, 25),
    LogicalKeyboardKey.keyX: (0x07, 0x58, 53),
    LogicalKeyboardKey.keyY: (0x10, 0x59, 29),
    LogicalKeyboardKey.keyZ: (0x06, 0x5A, 52),
    // 数字。
    LogicalKeyboardKey.digit0: (0x1D, 0x30, 19),
    LogicalKeyboardKey.digit1: (0x12, 0x31, 10),
    LogicalKeyboardKey.digit2: (0x13, 0x32, 11),
    LogicalKeyboardKey.digit3: (0x14, 0x33, 12),
    LogicalKeyboardKey.digit4: (0x15, 0x34, 13),
    LogicalKeyboardKey.digit5: (0x17, 0x35, 14),
    LogicalKeyboardKey.digit6: (0x16, 0x36, 15),
    LogicalKeyboardKey.digit7: (0x1A, 0x37, 16),
    LogicalKeyboardKey.digit8: (0x1C, 0x38, 17),
    LogicalKeyboardKey.digit9: (0x19, 0x39, 18),
    // 功能键。
    LogicalKeyboardKey.f1: (0x7A, 0x70, 67),
    LogicalKeyboardKey.f2: (0x78, 0x71, 68),
    LogicalKeyboardKey.f3: (0x63, 0x72, 69),
    LogicalKeyboardKey.f4: (0x76, 0x73, 70),
    LogicalKeyboardKey.f5: (0x60, 0x74, 71),
    LogicalKeyboardKey.f6: (0x61, 0x75, 72),
    LogicalKeyboardKey.f7: (0x62, 0x76, 73),
    LogicalKeyboardKey.f8: (0x64, 0x77, 74),
    LogicalKeyboardKey.f9: (0x65, 0x78, 75),
    LogicalKeyboardKey.f10: (0x6D, 0x79, 76),
    LogicalKeyboardKey.f11: (0x67, 0x7A, 95),
    LogicalKeyboardKey.f12: (0x6F, 0x7B, 96),
    // 导航与杂项。macOS 没有 Insert 键（旧键盘的 Help 不是同一个概念）。
    LogicalKeyboardKey.space: (0x31, 0x20, 65),
    LogicalKeyboardKey.capsLock: (0x39, 0x14, 66),
    LogicalKeyboardKey.insert: (null, 0x2D, 118),
    LogicalKeyboardKey.delete: (0x75, 0x2E, 127),
    LogicalKeyboardKey.home: (0x73, 0x24, 110),
    LogicalKeyboardKey.end: (0x77, 0x23, 115),
    LogicalKeyboardKey.pageUp: (0x74, 0x21, 112),
    LogicalKeyboardKey.pageDown: (0x79, 0x22, 117),
    // 标点（美式布局）。
    LogicalKeyboardKey.backquote: (0x32, 0xC0, 49),
    LogicalKeyboardKey.minus: (0x1B, 0xBD, 20),
    LogicalKeyboardKey.equal: (0x18, 0xBB, 21),
    LogicalKeyboardKey.bracketLeft: (0x21, 0xDB, 34),
    LogicalKeyboardKey.bracketRight: (0x1E, 0xDD, 35),
    LogicalKeyboardKey.backslash: (0x2A, 0xDC, 51),
    LogicalKeyboardKey.semicolon: (0x29, 0xBA, 47),
    LogicalKeyboardKey.quote: (0x27, 0xDE, 48),
    LogicalKeyboardKey.comma: (0x2B, 0xBC, 59),
    LogicalKeyboardKey.period: (0x2F, 0xBE, 60),
    LogicalKeyboardKey.slash: (0x2C, 0xBF, 61),
  };
  return {for (final entry in table.entries) entry.key.keyId: entry.value};
}
