// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../core/voice_levels.dart';
import 'voice_activity_ribbon.dart';

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
  );

  void dropConnection() {
    state = const SessionView();
  }

  void switchConnection() {
    state = state.copyWith(activeServerId: 'next', connectionEpoch: 1);
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  Stream<VoiceLevels> levels,
  Key boundaryKey, {
  bool reduceMotion = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionViewProvider.overrideWith(_Session.new),
      voiceLevelsProvider.overrideWith((ref) => levels),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red)
              .copyWith(primary: const Color(0xFFFF0000)),
        ),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: const SizedBox(
                width: 200,
                height: 48,
                child: VoiceActivityRibbon(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

// 读取画布顶部的红色峰值，验证实际像素而非动画对象的目标属性。
Future<int> _peakPixels(WidgetTester tester, Key boundaryKey) async =>
    (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var peaks = 0;
        for (var y = 0; y < image.height ~/ 3; y++) {
          for (var x = image.width * 2 ~/ 3; x < image.width; x++) {
            final offset = (y * image.width + x) * 4;
            if (pixels.getUint8(offset) > 180 &&
                pixels.getUint8(offset + 1) < 80 &&
                pixels.getUint8(offset + 3) > 128) {
              peaks++;
            }
          }
        }
        return peaks;
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  testWidgets('换连接时隔离历史，即使没有渲染中间的断开帧', (tester) async {
    final levels = StreamController<VoiceLevels>.broadcast(sync: true);
    addTearDown(levels.close);
    const boundaryKey = ValueKey('meter');
    final container = await _mount(tester, levels.stream, boundaryKey);
    levels.add(const VoiceLevels(mic: 1));
    await tester.pump();
    levels.add(const VoiceLevels());
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), greaterThan(4));
    (container.read(sessionViewProvider.notifier) as _Session)
        .switchConnection();
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), 0);
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('峰值在收到后的第一帧可见，减少动效=$reduceMotion', (tester) async {
      final levels = StreamController<VoiceLevels>.broadcast(sync: true);
      addTearDown(levels.close);
      const boundaryKey = ValueKey('meter');
      await _mount(
        tester,
        levels.stream,
        boundaryKey,
        reduceMotion: reduceMotion,
      );
      expect(await _peakPixels(tester, boundaryKey), 0);
      levels.add(const VoiceLevels(mic: 1));
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), greaterThan(4));
    });
  }

  testWidgets('切换声源或断开连接立即清空历史，不保留旧峰值', (tester) async {
    final levels = StreamController<VoiceLevels>.broadcast(sync: true);
    addTearDown(levels.close);
    const boundaryKey = ValueKey('meter');
    final container = await _mount(tester, levels.stream, boundaryKey);
    levels.add(const VoiceLevels(mic: 1));
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), greaterThan(4));

    container
        .read(preferencesProvider.notifier)
        .setVoiceMeterSource(VoiceMeterSource.received);
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), 0);

    levels.add(const VoiceLevels(received: 1));
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), greaterThan(4));
    (container.read(sessionViewProvider.notifier) as _Session).dropConnection();
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), 0);
    levels.add(const VoiceLevels(received: 1));
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), 0);
  });
}
