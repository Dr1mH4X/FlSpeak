import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/server_icon.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/features/connect/widgets/server_row.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/app_navigation_sidebar.dart';
import 'package:flspeak/widgets/monogram.dart';
import 'package:flspeak/widgets/prism.dart';

const _original = ServerProfileView(
  id: 'old.example.com:9987',
  label: 'Original',
  host: 'old.example.com',
  port: 9987,
);

class _Core extends Fake implements CoreSession {
  final changes = StreamController<CoreEvent>.broadcast(sync: true);
  final edits = <({String id, String label, String address})>[];
  bool fail = false;
  @override
  Stream<CoreEvent> events() => changes.stream;
  @override
  Future<List<ServerProfileView>> listServers() async => [_original];
  @override
  Future<List<ServerIconView>> listServerIcons() async => const [];
  @override
  Future<ServerProfileView> updateServer({
    required String id,
    required String label,
    required String address,
  }) async {
    edits.add((id: id, label: label, address: address));
    if (fail) throw const CoreError.connection(message: 'refused');
    final updated = ServerProfileView(
      id: address,
      label: label,
      host: 'new.example.com',
      port: 9999,
    );
    changes.add(CoreEvent.servers(profiles: [updated]));
    return updated;
  }
}

Future<ProviderContainer> _mount(WidgetTester tester, _Core core) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(core),
      preferencesStoreProvider.overrideWithValue(
        PreferencesStore.inMemory(
          preferences: SessionPreferences(
            nickname: 'Test',
            serverIcons: {
              _original.id: ServerIconChoice.preset(ServerIcon.gaming),
            },
            lastConnected: {_original.id: DateTime(2026)},
          ),
        ),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await core.changes.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  return container;
}

Future<void> _openEditor(WidgetTester tester, {required bool homeRow}) async {
  final target = homeRow
      ? find.byType(ServerRow)
      : find.descendant(
          of: find.byType(AppNavigationSidebar),
          matching: find.byType(ServerBadge),
        );
  await tester.tap(target, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('编辑服务器'));
  await tester.pumpAndSettle();
}

void main() {
  for (final homeRow in [true, false]) {
    testWidgets(
      '${homeRow ? 'home row' : 'sidebar'} edits the saved profile and migrates its preferences without connecting',
      (tester) async {
        final core = _Core();
        final container = await _mount(tester, core);
        await _openEditor(tester, homeRow: homeRow);
        final fields = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(fields.first).controller!.text,
          'old.example.com:9987',
        );
        expect(
          tester.widget<TextField>(fields.last).controller!.text,
          'Original',
        );
        await tester.enterText(fields.first, 'new.example.com:9999');
        await tester.enterText(fields.last, 'Renamed');
        await tester.tap(find.widgetWithText(FilledButton, '保存'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(core.edits, [
          (id: _original.id, label: 'Renamed', address: 'new.example.com:9999'),
        ]);
        final view = container.read(sessionViewProvider);
        expect(view.servers, hasLength(1));
        expect(view.servers.single.label, 'Renamed');
        expect(view.connected, isFalse);
        final preferences = container.read(preferencesProvider);
        expect(
          preferences.serverIcons['new.example.com:9999'],
          ServerIconChoice.preset(ServerIcon.gaming),
        );
        expect(preferences.serverIcons.containsKey(_original.id), isFalse);
        expect(
          preferences.lastConnected['new.example.com:9999'],
          DateTime(2026),
        );
      },
    );
  }

  testWidgets(
    'invalid input and a refused save retain the original profile and editable form',
    (tester) async {
      final core = _Core()..fail = true;
      final container = await _mount(tester, core);
      await _openEditor(tester, homeRow: true);
      final fields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, 'nickname');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(core.edits, isEmpty);
      await tester.enterText(fields.first, 'new.example.com:9999');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(container.read(sessionViewProvider).servers.single, _original);
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        'new.example.com:9999',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(core.edits, hasLength(1));
    },
  );
}
