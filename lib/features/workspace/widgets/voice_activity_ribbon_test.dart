// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/voice_levels.dart';
import 'package:flspeak/features/workspace/widgets/voice_activity_ribbon.dart';
import 'package:flutter/material.dart';
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
            child: const VoiceActivityRibbon(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('电平条在频道栏宽度范围内绘制且不溢出', (tester) async {
    final levels = StreamController<VoiceLevels>.broadcast();
    addTearDown(levels.close);

    for (final width in [200.0, 288.0, 480.0]) {
      await _pumpRibbon(tester, width: width, levels: levels.stream);
      levels.add(const VoiceLevels(mic: 0.9, received: 0.2));
      await tester.pump();

      expect(find.byType(VoiceActivityRibbon), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}
