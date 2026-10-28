// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import 'connect_page.dart';
import 'widgets/identity_card.dart';

class _FakeCore extends Fake implements CoreSession {
  @override
  Stream<CoreEvent> events() => const Stream.empty();
}

class _TestSessionController extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.disconnected(),
    servers: [
      ServerProfileView(
        id: 'server-1',
        label: 'Test Server',
        host: '127.0.0.1',
        port: 9987,
      ),
    ],
  );
}

void main() {
  testWidgets('宽屏下右侧身份卡片顶部与主标题对齐', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('找到你的声音');
    final cardFinder = find.byType(IdentityCard);

    expect(titleFinder, findsOneWidget);
    expect(cardFinder, findsOneWidget);

    final titleTop = tester.getTopLeft(titleFinder).dy;
    final cardTop = tester.getTopLeft(cardFinder).dy;

    expect(cardTop, equals(titleTop));
  });

  testWidgets('紧凑屏下身份条位于主标题下方', (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('找到你的声音');
    final stripFinder = find.byType(IdentityStrip);

    expect(titleFinder, findsOneWidget);
    expect(stripFinder, findsOneWidget);

    final titleBottom = tester.getBottomLeft(titleFinder).dy;
    final stripTop = tester.getTopLeft(stripFinder).dy;

    expect(stripTop, greaterThan(titleBottom));
  });
}
