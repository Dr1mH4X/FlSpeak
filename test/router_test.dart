// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/features/settings/settings_page.dart';
import 'package:flspeak/features/workspace/workspace_shell.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/localization.dart';
import 'package:flspeak/router.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  _Session([this._initial = const SessionView()]);
  final SessionView _initial;

  @override
  SessionView build() => _initial;
}

Future<GoRouter> _mount(
  WidgetTester tester, {
  SessionView sessionView = const SessionView(),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_Core()),
      sessionViewProvider.overrideWith(() => _Session(sessionView)),
      storePathProvider.overrideWithValue('/tmp/flspeak-test/preferences.json'),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'settings navigation in the SDK MaterialApp renders intermediate frames on enter and return',
    (tester) async {
      final router = await _mount(tester);
      unawaited(router.push<void>(AppRoutes.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final route = ModalRoute.of(tester.element(find.byType(SettingsPage)))!;
      expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
    },
  );

  testWidgets('wide root tab switches replace the page directly like FlClash', (
    tester,
  ) async {
    final router = await _mount(tester);
    expect(find.byType(ConnectPage), findsOneWidget);

    router.go(AppRoutes.workspace);
    await tester.pump();

    expect(find.byType(ConnectPage), findsNothing);
    expect(find.byType(WorkspaceShell), findsOneWidget);
  });

  testWidgets(
    'returning from settings through the sidebar home returns to the connect page instead of the connection-lost page',
    (tester) async {
      await _mount(tester);
      expect(find.byType(ConnectPage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          MaterialLocalizations.of(tester.element(find.byType(SettingsPage)))
              .backButtonTooltip,
        ),
        findsNothing,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.byIcon(Icons.home_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ConnectPage), findsOneWidget);
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.text('连接丢失'), findsNothing);
    },
  );

  testWidgets(
    'pressing Esc from settings returns directly to the connect page',
    (tester) async {
      await _mount(tester);
      expect(find.byType(ConnectPage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ConnectPage), findsOneWidget);
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.text('连接丢失'), findsNothing);
    },
  );
}
