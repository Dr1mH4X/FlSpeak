// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'core/providers.dart';
import 'features/settings/settings_page.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView();
}

Future<GoRouter> _mount(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_Core()),
      sessionViewProvider.overrideWith(_Session.new),
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
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
}
