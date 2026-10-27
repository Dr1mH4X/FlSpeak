// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/voice_levels.dart';
import 'package:flspeak/features/workspace/widgets/voice_activity_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpRibbon(
  WidgetTester tester, {
  required double width,
  required Stream<VoiceLevels> levels,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceLevelsProvider.overrideWith((ref) => levels),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore.inMemory(
            preferences: const SessionPreferences(
              nickname: 'n',
              voiceMeterSource: VoiceMeterSource.received,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 68,
            child: const RepaintBoundary(
              key: ValueKey('ribbon-capture'),
              child: VoiceActivityRibbon(),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<int> _inkCoverage(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('ribbon-capture')),
  );
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes;
  });
  final pixels = data!.buffer.asUint8List();
  var coverage = 0;
  for (var index = 3; index < pixels.length; index += 4) {
    coverage += pixels[index];
  }
  return coverage;
}

void main() {
  testWidgets('电平条在频道栏宽度范围内绘制且不溢出', (tester) async {
    final levels = StreamController<VoiceLevels>.broadcast();
    addTearDown(levels.close);

    for (final width in [22.0, 48.0, 80.0, 200.0, 288.0, 480.0]) {
      await _pumpRibbon(tester, width: width, levels: levels.stream);
      levels.add(const VoiceLevels(mic: 0.9, received: 0.2));
      await tester.pump();

      expect(find.byType(VoiceActivityRibbon), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('波形跟随所选声源，切换后清除旧电平历史', (tester) async {
    final levels = StreamController<VoiceLevels>.broadcast();
    addTearDown(levels.close);
    await _pumpRibbon(tester, width: 200, levels: levels.stream);
    await tester.pumpAndSettle();
    final baseline = await _inkCoverage(tester);

    Future<void> emitMicrophone(double amplitude) async {
      for (var index = 0; index < 24; index++) {
        levels.add(VoiceLevels(mic: amplitude));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    await emitMicrophone(1);
    expect(await _inkCoverage(tester), baseline);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(VoiceActivityRibbon)),
    );
    container
        .read(preferencesProvider.notifier)
        .setVoiceMeterSource(VoiceMeterSource.microphone);
    await tester.pumpAndSettle();
    await emitMicrophone(1);
    expect(await _inkCoverage(tester), greaterThan(baseline * 3));

    container
        .read(preferencesProvider.notifier)
        .setVoiceMeterSource(VoiceMeterSource.received);
    await tester.pumpAndSettle();
    expect(await _inkCoverage(tester), baseline);
    expect(tester.takeException(), isNull);
  });
}
