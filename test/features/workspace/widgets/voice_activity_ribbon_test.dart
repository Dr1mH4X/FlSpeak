import 'dart:async';
import 'dart:ui' as ui;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/voice_activity_ribbon.dart';

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

  void enterNoChannel() {
    state = state.copyWith(
      state: const CoreSessionState.connected(clientId: 1, channelId: 0),
    );
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  Stream<VoiceLevels> levels,
  Key boundaryKey,
) async {
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
        home: Center(
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
  testWidgets(
    'history stays isolated across connections even without a rendered disconnect frame',
    (tester) async {
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
    },
  );

  testWidgets(
    'microphone history stays flat outside a channel while received audio keeps rendering',
    (tester) async {
      final levels = StreamController<VoiceLevels>.broadcast(sync: true);
      addTearDown(levels.close);
      const boundaryKey = ValueKey('meter-channel');
      final container = await _mount(tester, levels.stream, boundaryKey);
      levels.add(const VoiceLevels(mic: 1));
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), greaterThan(4));

      (container.read(sessionViewProvider.notifier) as _Session)
          .enterNoChannel();
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), 0);
      levels.add(const VoiceLevels(mic: 1));
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), 0);

      container
          .read(preferencesProvider.notifier)
          .setVoiceMeterSource(VoiceMeterSource.received);
      levels.add(const VoiceLevels(received: 1));
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), greaterThan(4));
    },
  );

  testWidgets('peaks are visible on the first frame after receipt', (
    tester,
  ) async {
    final levels = StreamController<VoiceLevels>.broadcast(sync: true);
    addTearDown(levels.close);
    const boundaryKey = ValueKey('meter');
    await _mount(tester, levels.stream, boundaryKey);
    expect(await _peakPixels(tester, boundaryKey), 0);
    levels.add(const VoiceLevels(mic: 1));
    await tester.pump();
    expect(await _peakPixels(tester, boundaryKey), greaterThan(4));
  });

  testWidgets(
    'switching source or disconnecting clears history immediately without stale peaks',
    (tester) async {
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
      (container.read(sessionViewProvider.notifier) as _Session)
          .dropConnection();
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), 0);
      levels.add(const VoiceLevels(received: 1));
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), 0);
    },
  );

  testWidgets(
    'level listening pauses when TickerMode is off or the app is backgrounded and stays active only while inactive',
    (tester) async {
      final levels = StreamController<VoiceLevels>.broadcast(sync: true);
      addTearDown(levels.close);
      const boundaryKey = ValueKey('meter-pause');
      final tickerEnabled = ValueNotifier(true);
      addTearDown(tickerEnabled.dispose);

      final container = ProviderContainer(
        overrides: [
          sessionViewProvider.overrideWith(_Session.new),
          voiceLevelsProvider.overrideWith((ref) => levels.stream),
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
            home: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: tickerEnabled,
                builder: (_, enabled, child) => TickerMode(
                  enabled: enabled,
                  child: const RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 200,
                      height: 48,
                      child: VoiceActivityRibbon(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(levels.hasListener, isTrue);

      // 桌面双窗口失焦（inactive）保持活跃
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(levels.hasListener, isTrue);

      // 后台（paused）即使宿主停止调度帧，也立即释放底层流监听。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(Duration.zero);
      expect(levels.hasListener, isFalse);
      levels.add(const VoiceLevels(mic: 1));
      await tester.pump();
      expect(await _peakPixels(tester, boundaryKey), 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(levels.hasListener, isTrue);

      // TickerMode 关闭时停止订阅
      tickerEnabled.value = false;
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(levels.hasListener, isFalse);

      tickerEnabled.value = true;
      await tester.pump();
      expect(levels.hasListener, isTrue);
    },
  );
}
