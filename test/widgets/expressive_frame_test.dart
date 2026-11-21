// ignore_for_file: depend_on_referenced_packages

import 'package:material_ui/material_ui.dart';
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

  testWidgets(
    'pauses rotation under disableAnimations and disabled TickerMode',
    (tester) async {
      Future<void> mountWith({
        required bool disableAnimations,
        required bool tickerEnabled,
      }) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: TickerMode(
              enabled: tickerEnabled,
              child: const Center(
                child: ExpressiveFrame(
                  loading: true,
                  child: Icon(Icons.music_note),
                ),
              ),
            ),
          ),
        ),
      );

      await mountWith(disableAnimations: true, tickerEnabled: true);
      await tester.pumpAndSettle();
      expect(rotationOf(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await mountWith(disableAnimations: false, tickerEnabled: false);
      await tester.pumpAndSettle();
      expect(rotationOf(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await mountWith(disableAnimations: false, tickerEnabled: true);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(rotationOf(tester), greaterThan(0));
    },
  );
}
