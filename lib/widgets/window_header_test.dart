// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/window_chrome.dart';
import '../core/window_metrics.dart';
import '../l10n/app_localizations.dart';
import 'caption_icon.dart';
import 'window_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = [];

  setUp(() {
    calls.clear();
    WindowChrome.attach();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flspeak/window'), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'isAlwaysOnTop') {
            return WindowChrome.isPinned.value;
          }
          if (call.method == 'isMaximized') {
            return WindowChrome.isMaximized.value;
          }
          if (call.method == 'isFullScreen') {
            return WindowChrome.fullScreen.value;
          }
          return null;
        });
    WindowChrome.isPinned.value = false;
    WindowChrome.isMaximized.value = false;
    WindowChrome.fullScreen.value = false;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flspeak/window'), null);
  });

  group('showsWindowHeader', () {
    test('Windows always draws its own header at wide and narrow widths', () {
      expect(
        showsWindowHeader(isMacOS: false, isWindows: true, isMobileView: false),
        isTrue,
      );
      expect(
        showsWindowHeader(isMacOS: false, isWindows: true, isMobileView: true),
        isTrue,
      );
    });

    test('macOS only draws header when in mobile view', () {
      expect(
        showsWindowHeader(isMacOS: true, isWindows: false, isMobileView: false),
        isFalse,
      );
      expect(
        showsWindowHeader(isMacOS: true, isWindows: false, isMobileView: true),
        isTrue,
      );
    });
  });

  group('WindowHeaderActions', () {
    testWidgets(
      'renders all 4 buttons on Windows with correct caption glyphs',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: WindowHeaderBar(
                height: 32,
                onDragStart: _noop,
                onDoubleTap: _noop,
                actions: WindowHeaderActions(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pin button
        expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

        // Caption glyph icons: minimize, maximize, close
        expect(
          find.byWidgetPredicate(
            (w) => w is CaptionIcon && w.glyph == CaptionGlyph.minimize,
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is CaptionIcon && w.glyph == CaptionGlyph.maximize,
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is CaptionIcon && w.glyph == CaptionGlyph.close,
          ),
          findsOneWidget,
        );

        // Verify repo rule: No Tooltip widgets exist in the tree
        expect(find.byType(Tooltip), findsNothing);
      },
    );

    testWidgets('pin button toggles isPinned and calls setAlwaysOnTop', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WindowHeaderBar(
              height: 32,
              onDragStart: _noop,
              onDoubleTap: _noop,
              actions: WindowHeaderActions(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();

      expect(calls.any((c) => c.method == 'setAlwaysOnTop'), isTrue);
    });

    testWidgets('minimize button triggers WindowChrome.minimize', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WindowHeaderBar(
              height: 32,
              onDragStart: _noop,
              onDoubleTap: _noop,
              actions: WindowHeaderActions(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final minimizeFinder = find.byWidgetPredicate(
        (w) => w is CaptionIcon && w.glyph == CaptionGlyph.minimize,
      );
      await tester.tap(minimizeFinder);
      await tester.pumpAndSettle();

      expect(calls.any((c) => c.method == 'minimize'), isTrue);
    });

    testWidgets('maximize switches glyph between maximize and restore', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WindowHeaderBar(
              height: 32,
              onDragStart: _noop,
              onDoubleTap: _noop,
              actions: WindowHeaderActions(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is CaptionIcon && w.glyph == CaptionGlyph.maximize,
        ),
        findsOneWidget,
      );

      // Change state to maximized
      WindowChrome.isMaximized.value = true;
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is CaptionIcon && w.glyph == CaptionGlyph.restore,
        ),
        findsOneWidget,
      );
    });

    testWidgets('close button triggers WindowChrome.close', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WindowHeaderBar(
              height: 32,
              onDragStart: _noop,
              onDoubleTap: _noop,
              actions: WindowHeaderActions(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeFinder = find.byWidgetPredicate(
        (w) => w is CaptionIcon && w.glyph == CaptionGlyph.close,
      );
      await tester.tap(closeFinder);
      await tester.pumpAndSettle();

      expect(calls.any((c) => c.method == 'close'), isTrue);
    });
  });
}

void _noop() {}
