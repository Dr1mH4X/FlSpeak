// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../theme/app_theme.dart';
import 'press_feedback.dart';

void main() {
  for (final nativeButton in [true, false]) {
    testWidgets('按下与松开有中间帧且保持触摸尺寸，标准按钮=$nativeButton', (tester) async {
      var taps = 0;
      const key = ValueKey('control');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Material(
            child: Center(
              child: nativeButton
                  ? FilledButton(
                      key: key,
                      onPressed: () => taps++,
                      child: const Text('Join'),
                    )
                  : AnimatedInkWell(
                      key: key,
                      onTap: () => taps++,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.mic),
                      ),
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.byKey(key);
      final bounds = tester.getRect(control);
      final scale = find.descendant(
        of: control,
        matching: find.byType(ScaleTransition),
      );
      final gesture = await tester.startGesture(tester.getCenter(control));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.widget<ScaleTransition>(scale).scale.value,
        inExclusiveRange(0.94, 1.0),
      );
      expect(tester.getRect(control), bounds);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester.widget<ScaleTransition>(scale).scale.value,
        inExclusiveRange(0.94, 1.0),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ScaleTransition>(scale).scale.value, 1);
      expect(taps, 1);
    });
  }

  testWidgets('取消手势不会触发操作，禁用区域不缩放', (tester) async {
    var taps = 0;
    const key = ValueKey('control');
    Widget app(bool enabled) => MaterialApp(
      home: Material(
        child: Center(
          child: AnimatedInkWell(
            key: key,
            onTap: enabled ? () => taps++ : null,
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(taps, 0);
    await tester.pumpWidget(app(false));
    final disabled = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      tester
          .widget<ScaleTransition>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(ScaleTransition),
            ),
          )
          .scale
          .value,
      1,
    );
    await disabled.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });
}
