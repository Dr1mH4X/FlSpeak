// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../theme/app_theme.dart';
import 'common.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets('桌面弹窗淡入缩放并可取消，减少动效=$reduceMotion', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showAppModal<void>(
                    context,
                    title: 'Audio',
                    builder: (_) => const Text('Microphone'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final dialog = find.byType(Dialog);
      expect(dialog, findsOneWidget);
      final scale = find.ancestor(
        of: dialog,
        matching: find.byType(ScaleTransition),
      );
      if (reduceMotion) {
        expect(scale, findsNothing);
      } else {
        expect(
          tester.widget<ScaleTransition>(scale).scale.value,
          inExclusiveRange(0.94, 1.0),
        );
      }
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  }
}
