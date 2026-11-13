// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/features/settings/settings_page.dart';
import 'package:flspeak/l10n/app_localizations.dart';
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
  bool reduceMotion = false,
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
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          PrismUiLocalizationsDelegate(),
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: PrismRootScope(brightness: Brightness.light, child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('SDK MaterialApp 的设置导航在进入和返回时均有中间帧', (tester) async {
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
  });

  testWidgets('减少动态效果时导航直接显示最终内容', (tester) async {
    final router = await _mount(tester, reduceMotion: true);
    unawaited(router.push<void>(AppRoutes.settings));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(SettingsPage)))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.animation!.value, 1);
  });

  testWidgets('从连接页侧栏进入设置后，一级菜单点击返回能回到连接页而非连接丢失页', (tester) async {
    await _mount(tester);
    expect(find.byType(ConnectPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('连接丢失'), findsNothing);
  });

  testWidgets('从连接页进入设置后，按 ESC 键也能直接退回连接页', (tester) async {
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
  });
}
