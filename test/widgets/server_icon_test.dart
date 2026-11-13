// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
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
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/monogram.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak/widgets/server_icon_picker.dart';

final _validPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _FakeCore extends Fake implements CoreSession {
  final changes = StreamController<CoreEvent>.broadcast(sync: true);

  @override
  Stream<CoreEvent> events() => changes.stream;

  @override
  Future<List<ServerProfileView>> listServers() async => const [];

  @override
  Future<List<ServerIconView>> listServerIcons() async => const [];

  @override
  Future<void> dispose() => changes.close();
}

Widget _wrapApp(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      locale: const Locale('zh'),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        PrismUiLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, inner) =>
          PrismRootScope(brightness: Brightness.light, child: inner!),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets(
    'ServerBadge prefers server icon in auto mode and honors preset override',
    (tester) async {
      final core = _FakeCore();
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(nickname: 'Tester'),
            ),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await core.changes.close();
      });

      await tester.pumpWidget(
        _wrapApp(container, const ServerBadge(id: 's1:9987')),
      );
      await tester.pumpAndSettle();

      // 无缓存服务器图标时回退到社区预设。
      expect(find.byIcon(ServerIcon.community.icon), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      // 收到服务器图标后，默认自动模式切换为图片展示。
      core.changes.add(
        CoreEvent.serverIconUpdated(serverId: 's1:9987', bytes: _validPng),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);

      // 用户显式选择预设图标后覆盖服务器图标；切回自动后恢复服务器图标。
      container
          .read(preferencesProvider.notifier)
          .setServerIcon('s1:9987', ServerIconChoice.preset(ServerIcon.gaming));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(ServerIcon.gaming.icon), findsOneWidget);

      container
          .read(preferencesProvider.notifier)
          .setServerIcon('s1:9987', ServerIconChoice.auto);
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets(
    'ServerBadge falls back to preset icon when cached bytes cannot decode',
    (tester) async {
      final core = _FakeCore();
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(nickname: 'Tester'),
            ),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await core.changes.close();
      });

      await tester.pumpWidget(
        _wrapApp(container, const ServerBadge(id: 's1:9987')),
      );
      core.changes.add(
        CoreEvent.serverIconUpdated(
          serverId: 's1:9987',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(ServerIcon.community.icon), findsOneWidget);
    },
  );

  testWidgets(
    'ServerIconGrid places follow-server option first and selects it',
    (tester) async {
      ServerIconChoice? picked;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapApp(
          container,
          ServerIconGrid(
            selected: ServerIconChoice.preset(ServerIcon.gaming),
            serverIconBytes: _validPng,
            onSelected: (choice) => picked = choice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('跟随服务器'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.text('跟随服务器'));
      expect(picked, ServerIconChoice.auto);
    },
  );
}
