// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/router.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/features/connect/widgets/identity_card.dart';
import 'package:flspeak/features/connect/widgets/server_row.dart';
import 'package:flspeak/widgets/prism.dart';

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
              localizationsDelegates: const [
                ...AppLocalizations.localizationsDelegates,
                PrismUiLocalizationsDelegate(),
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) =>
                  PrismRootScope(brightness: Brightness.light, child: child!),
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
                localizationsDelegates: const [
                  ...AppLocalizations.localizationsDelegates,
                  PrismUiLocalizationsDelegate(),
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: PrismRootScope(
                    brightness: Brightness.light,
                    child: child!,
                  ),
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
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const ConnectPage(),
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
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未连接'), findsNothing);
    expect(find.text('一个身份，连接你熟悉的每个社区。'), findsNothing);
    expect(find.text('身份保存在本机'), findsNothing);
  });

  testWidgets('通过管理身份弹窗修改昵称并在连接页更新', (tester) async {
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
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FlSpeakUser'), findsOneWidget);

    await tester.tap(find.text('管理身份'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final renameField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '昵称',
    );
    await tester.enterText(renameField, 'Alice');
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('FlSpeakUser'), findsNothing);
  });

  testWidgets('管理身份弹窗中输入空昵称点击完成自动回退为默认昵称', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PreferencesStore.inMemory(
      preferences: const SessionPreferences(nickname: 'Bob'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
          preferencesStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);

    await tester.tap(find.text('管理身份'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final renameField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '昵称',
    );
    await tester.enterText(renameField, '   ');
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('FlSpeakUser'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('管理身份弹窗中取消编辑后点击完成不应修改昵称', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PreferencesStore.inMemory(
      preferences: const SessionPreferences(nickname: 'Charlie'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
          preferencesStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Charlie'), findsOneWidget);

    await tester.tap(find.text('管理身份'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();

    final renameField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '昵称',
    );
    await tester.enterText(renameField, 'NewCharlie');
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('NewCharlie'), findsNothing);
  });

  testWidgets('桌面端服务器行不显示三点按钮，右键在点击位置呼出菜单而非卡片最左侧', (tester) async {
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
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    final rowRect = tester.getRect(find.byType(ServerRow));
    final clickPoint = Offset(
      rowRect.left + rowRect.width * 0.65,
      rowRect.center.dy,
    );
    await tester.tapAt(clickPoint, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    final menuLeft = tester.getTopLeft(find.byType(MenuItemButton).first).dx;
    expect(menuLeft, closeTo(clickPoint.dx, 4.0));
  });

  testWidgets('窄屏下服务器行显示三点按钮并从按钮位置呼出菜单', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreSessionProvider.overrideWithValue(_FakeCore()),
          sessionViewProvider.overrideWith(_TestSessionController.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const ConnectPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rowRect = tester.getRect(find.byType(ServerRow));
    final moreFinder = find.byIcon(Icons.more_vert_rounded);
    expect(moreFinder, findsOneWidget);
    await tester.tap(moreFinder);
    await tester.pumpAndSettle();

    final menuLeft = tester.getTopLeft(find.byType(MenuItemButton).first).dx;
    expect(menuLeft, greaterThan(rowRect.center.dx));
  });

  testWidgets('主页在浅色与深色模式下使用 pageColor 底板与 xl 超椭圆卡片对比', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness);
      final pageColor = surfaceColorFor(SurfaceLevel.page, theme.colorScheme);
      final cardColor = surfaceColorFor(SurfaceLevel.card, theme.colorScheme);
      expect(cardColor, isNot(pageColor));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreSessionProvider.overrideWithValue(_FakeCore()),
            sessionViewProvider.overrideWith(_TestSessionController.new),
          ],
          child: MaterialApp(
            theme: theme,
            locale: const Locale('zh'),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: brightness, child: child!),
            home: const ConnectPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, pageColor);

      final pageCanvas = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(ConnectPage),
              matching: find.byWidgetPredicate(
                (w) => w is Material && w.color == pageColor,
              ),
            )
            .first,
      );
      expect(pageCanvas.color, pageColor);

      final cards = tester
          .widgetList<SurfaceCard>(find.byType(SurfaceCard))
          .toList();
      expect(cards, isNotEmpty);
      for (final card in cards) {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byWidget(card),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final decoration = box.decoration as ShapeDecoration;
        expect(decoration.color, cardColor);
        expect(decoration.shape, AppShape.xl);
      }
    }
  });
}
