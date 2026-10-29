// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../router.dart';
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

class _ConnectedSessionController extends _TestSessionController {
  @override
  SessionView build() => super.build().copyWith(
    state: const CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'server-1',
  );
}

const _switchServers = [
  ServerProfileView(id: 'a', label: 'A', host: 'a.example.com', port: 9987),
  ServerProfileView(id: 'b', label: 'B', host: 'b.example.com', port: 9987),
];

class _SwitchingCore extends _FakeCore {
  _SwitchingCore(this.changes);
  final StreamController<CoreEvent> changes;
  final disconnected = Completer<void>();
  final connected = Completer<void>();
  final calls = <String>[];
  @override
  Stream<CoreEvent> events() => changes.stream;
  @override
  Future<List<ServerProfileView>> listServers() async => _switchServers;
  @override
  Future<void> disconnect() {
    calls.add('disconnect');
    return disconnected.future;
  }

  @override
  Future<void> connect({required String id, required String nickname}) {
    calls.add(id);
    return connected.future;
  }
}

class _LiveSwitchSession extends SessionController {
  @override
  SessionView build() => super.build().copyWith(
    state: const CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'a',
    servers: _switchServers,
  );
}

void main() {
  for (final lateEvent in [false, true]) {
    testWidgets(
      'switching servers reaches the workspace with either API/event order, late=$lateEvent',
      (tester) async {
        final changes = StreamController<CoreEvent>.broadcast(sync: true);
        final core = _SwitchingCore(changes);
        final container = ProviderContainer(
          overrides: [
            coreSessionProvider.overrideWithValue(core),
            sessionViewProvider.overrideWith(_LiveSwitchSession.new),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await changes.close();
        });
        final router = container.read(routerProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: buildAppTheme(Brightness.light),
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        router.go('${AppRoutes.connect}?server=b');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(core.calls, ['disconnect']);
        core.changes.add(
          const CoreEvent.state(
            state: CoreSessionState.reconnecting(attempt: 1, delayMs: 1000),
          ),
        );
        core.changes.add(
          const CoreEvent.state(
            state: CoreSessionState.connected(clientId: 1, channelId: 5),
          ),
        );
        await tester.pump();
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutes.connect,
        );
        core.disconnected.complete();
        core.changes.add(
          const CoreEvent.state(state: CoreSessionState.disconnected()),
        );
        core.changes.add(
          const CoreEvent.state(state: CoreSessionState.connecting()),
        );
        await tester.pump();
        expect(core.calls, ['disconnect', 'b']);
        if (lateEvent) {
          core.connected.complete();
          await tester.pump();
        }
        core.changes.add(
          const CoreEvent.state(
            state: CoreSessionState.connected(clientId: 2, channelId: 8),
          ),
        );
        if (!lateEvent) core.connected.complete();
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutes.workspace,
        );
        expect(container.read(sessionViewProvider).activeServerId, 'b');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final locale in ['zh', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'connected compact layout supports $locale at text scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(360, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                coreSessionProvider.overrideWithValue(_FakeCore()),
                sessionViewProvider.overrideWith(
                  _ConnectedSessionController.new,
                ),
              ],
              child: MaterialApp(
                theme: buildAppTheme(Brightness.light),
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const ConnectPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Icon &&
                  widget.semanticLabel ==
                      lookupAppLocalizations(Locale(locale)).workspaceReturn,
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

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

  testWidgets('连接页不显示未连接状态及身份冗余文案', (tester) async {
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

    expect(find.text('未连接'), findsNothing);
    expect(find.text('一个身份，连接你熟悉的每个社区。'), findsNothing);
    expect(find.text('身份保存在本机'), findsNothing);
  });
}
