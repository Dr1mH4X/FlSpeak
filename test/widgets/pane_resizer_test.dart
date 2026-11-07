import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/widgets/pane_resizer.dart';

void main() {
  testWidgets(
    'PaneResizer horizontally resizes child on drag and triggers onSizeChanged',
    (tester) async {
      double? lastChangedSize;
      var resetCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaneResizer(
              axis: Axis.horizontal,
              size: 200,
              minSize: 100,
              maxSize: 400,
              defaultSize: 200,
              handleKey: const ValueKey('h-handle'),
              gripKey: const ValueKey('h-grip'),
              semanticLabel: 'Resize pane width',
              onSizeChanged: (val) => lastChangedSize = val,
              onReset: () => resetCalled = true,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('h-handle')), findsOneWidget);

      // Hover handle -> grip expands.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('h-handle'))),
      );
      await tester.pumpAndSettle();

      final gripBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('h-grip')),
      );
      expect(gripBox.size.height, 32.0);

      // Drag handle right by 70px -> size increases.
      await tester.drag(
        find.byKey(const ValueKey('h-handle')),
        const Offset(70, 0),
      );
      await tester.pumpAndSettle();
      expect(lastChangedSize, isNotNull);
      expect(lastChangedSize!, greaterThan(200.0));

      // Drag handle left by 300px -> clamped to minSize (100px).
      await tester.drag(
        find.byKey(const ValueKey('h-handle')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(lastChangedSize, 100.0);

      // Double tap handle -> calls onReset.
      await tester.tap(find.byKey(const ValueKey('h-handle')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('h-handle')));
      await tester.pumpAndSettle();
      expect(resetCalled, isTrue);
    },
  );

  testWidgets(
    'PaneResizer vertically resizes using builder and clamps to min and max',
    (tester) async {
      double currentSize = 180.0;
      double? lastChangedSize;
      double? renderedSize;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PaneResizer(
                  axis: Axis.vertical,
                  size: currentSize,
                  minSize: 120,
                  maxSize: 300,
                  defaultSize: 180,
                  handleKey: const ValueKey('v-handle'),
                  gripKey: const ValueKey('v-grip'),
                  semanticLabel: 'Resize pane height',
                  onSizeChanged: (val) {
                    lastChangedSize = val;
                    if (val != null) {
                      setState(() => currentSize = val);
                    }
                  },
                  builder: (context, size) {
                    renderedSize = size;
                    return SizedBox(
                      height: size,
                      child: const ColoredBox(color: Colors.green),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(renderedSize, 180.0);

      // Drag handle downwards by 80px -> increases size.
      await tester.drag(
        find.byKey(const ValueKey('v-handle')),
        const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      expect(lastChangedSize, isNotNull);
      expect(lastChangedSize!, greaterThan(180.0));
      expect(renderedSize, lastChangedSize);

      // Drag handle upwards by 300px -> clamped to minSize (120px).
      await tester.drag(
        find.byKey(const ValueKey('v-handle')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(lastChangedSize, 120.0);
      expect(renderedSize, 120.0);

      // Drag handle downwards by 400px -> clamped to maxSize (300px).
      await tester.drag(
        find.byKey(const ValueKey('v-handle')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(lastChangedSize, 300.0);
      expect(renderedSize, 300.0);
    },
  );
}
