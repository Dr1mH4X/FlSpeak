// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/widgets/expressive_frame.dart';

void main() {
  double rotationOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(ExpressiveFrame),
        matching: find.byType(CustomPaint),
      ),
    );
    return (paint.painter! as dynamic).rotation as double;
  }

  Future<void> pumpFrame(WidgetTester tester, {required bool loading}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ExpressiveFrame(
              loading: loading,
              child: const Icon(Icons.music_note),
            ),
          ),
        ),
      );

  testWidgets(
    'clover spins while loading and settles cleanly on quarter turn when stopped',
    (tester) async {
      await pumpFrame(tester, loading: true);
      final initial = rotationOf(tester);
      expect(initial, 0);

      await tester.pump(const Duration(milliseconds: 500));
      final moving = rotationOf(tester);
      expect(moving, greaterThan(0));

      // 保持图标本身不随花底旋转。
      expect(
        find.ancestor(
          of: find.byIcon(Icons.music_note),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );

      await pumpFrame(tester, loading: false);
      await tester.pumpAndSettle();
      final settled = rotationOf(tester);
      expect(settled, greaterThanOrEqualTo(moving));
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
