// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/app.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/system_fonts.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/core/window_chrome.dart';
import 'package:flspeak/widgets/app_navigation_sidebar.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView();
}

class _Update extends UpdateController {
  @override
  UpdateStateView build() => const UpdateStateView(available: false);
}

void main() {
  test('sortFontFamilies trims, drops hidden leading-dot names, deduplicates case-insensitively, and sorts', () {
    final result = sortFontFamilies([
      ' .SF NS ',
      'PingFang SC',
      'inter',
      'Inter',
      '   ',
      'Arial',
    ]);
    expect(result, ['Arial', 'inter', 'PingFang SC']);
  });

  test('androidFontFamilies parses family attributes from fonts.xml', () {
    const sample = '''
<familyset version="23">
  <family name="sans-serif">
    <font weight="400">Roboto-Regular.ttf</font>
  </family>
  <family lang="zh-Hans" name="noto-sans-cjk">
    <font weight="400">NotoSansCJK-Regular.ttc</font>
  </family>
</familyset>
''';
    expect(androidFontFamilies(sample), ['sans-serif', 'noto-sans-cjk']);
  });

  test('loadSystemFontFamilies handles reader failures gracefully', () async {
    final original = systemFontFamiliesReader;
    addTearDown(() => systemFontFamiliesReader = original);

    systemFontFamiliesReader = () async => throw StateError('boom');
    expect(await loadSystemFontFamilies(), isEmpty);
  });

  test('loadSystemFontFamilies enumerates macOS CoreText families', () async {
    if (!Platform.isMacOS) {
      return;
    }
    final families = await loadSystemFontFamilies();
    expect(families, isNotEmpty);
  });

  testWidgets(
    'sidebarBlur applies translucent tint to docked sidebar on supported host',
    (tester) async {
      const channel = MethodChannel('flspeak/window');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        switch (call.method) {
          case 'isEffectSupported':
            return call.arguments == 'glass';
          case 'setEffect':
          case 'setBackgroundColor':
            return true;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final opacity = await WindowChrome.setSidebarBlur(
        enabled: true,
        brightness: Brightness.dark,
        tint: const Color(0xFF1E1E24),
      );
      if (Platform.isMacOS || Platform.isWindows) {
        expect(opacity, WindowChrome.sidebarBlurTintOpacity);
      } else {
        expect(opacity, isNull);
      }

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(
                nickname: 'Test',
                locale: 'zh',
                sidebarBlur: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TsClientApp(),
        ),
      );
      await tester.pumpAndSettle();

      final sidebarSurface = tester.widget<Surface>(
        find
            .descendant(
              of: find.byType(AppNavigationSidebar),
              matching: find.byType(Surface),
            )
            .first,
      );
      if (Platform.isMacOS || Platform.isWindows) {
        expect(
          container.read(windowBlurOpacityProvider),
          WindowChrome.sidebarBlurTintOpacity,
        );
        expect(
          sidebarSurface.color?.a,
          closeTo(WindowChrome.sidebarBlurTintOpacity, 0.01),
        );
      } else {
        expect(sidebarSurface.color?.a, 1.0);
      }
    },
  );
}
