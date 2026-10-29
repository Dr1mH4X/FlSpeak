// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'expressive_frame.dart';

void main() {
  double perimeter(WidgetTester tester) {
    final clip = tester.widget<ClipPath>(find.byType(ClipPath));
    final shape = (clip.clipper! as ShapeBorderClipper).shape;
    return shape
        .getOuterPath(const Rect.fromLTWH(0, 0, 40, 40))
        .computeMetrics()
        .fold(0.0, (sum, metric) => sum + metric.length);
  }

  Future<void> pumpFrame(
    WidgetTester tester, {
    required bool loading,
    bool reducedMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Center(
          child: ExpressiveFrame(
            loading: loading,
            child: const Icon(Icons.music_note),
          ),
        ),
      ),
    ),
  );

  testWidgets('loading morph freezes at its current shape on completion', (
    tester,
  ) async {
    await pumpFrame(tester, loading: true);
    final initial = perimeter(tester);
    await tester.pump(const Duration(milliseconds: 650));
    final moving = perimeter(tester);
    expect(moving, isNot(closeTo(initial, 0.01)));
    await pumpFrame(tester, loading: false);
    final stopped = perimeter(tester);
    expect(stopped, closeTo(moving, 0.001));
    await tester.pump(const Duration(seconds: 3));
    expect(perimeter(tester), closeTo(stopped, 0.001));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion keeps loading frame static', (tester) async {
    await pumpFrame(tester, loading: true, reducedMotion: true);
    final initial = perimeter(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(perimeter(tester), closeTo(initial, 0.001));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
