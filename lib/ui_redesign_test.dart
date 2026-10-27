// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app.dart';
import 'core/models.dart';
import 'core/preferences.dart';
import 'core/providers.dart';
import 'core/voice_levels.dart';
import 'features/workspace/widgets/members_pane.dart';
import 'router.dart';

const _captureDirectory = String.fromEnvironment('FLSPEAK_CAPTURE_DIR');
const _captureFont = String.fromEnvironment('FLSPEAK_CAPTURE_FONT');
const _captureCjk = String.fromEnvironment('FLSPEAK_CAPTURE_CJK');
const _servers = [
  ServerProfileView(
    id: 'studio',
    label: 'Design studio',
    host: 'studio.example.com',
    port: 9987,
  ),
  ServerProfileView(
    id: 'friends',
    label: 'After hours',
    host: 'friends.example.com',
    port: 9987,
  ),
  ServerProfileView(
    id: 'games',
    label: 'Game night',
    host: 'games.example.com',
    port: 9987,
  ),
];

SessionView _session({bool connected = true, bool empty = false}) =>
    SessionView(
      state: connected
          ? const CoreSessionState.connected(clientId: 1, channelId: 1)
          : const CoreSessionState.disconnected(),
      activeServerId: connected ? 'studio' : null,
      servers: empty ? const [] : _servers,
      channels: const [
        ChannelView(id: 1, parentId: 0, name: 'The lounge', description: ''),
        ChannelView(id: 2, parentId: 0, name: 'Design room', description: ''),
        ChannelView(
          id: 3,
          parentId: 0,
          name: 'Listening party',
          description: '',
        ),
        ChannelView(id: 4, parentId: 0, name: 'Quiet corner', description: ''),
      ],
      clients: const [
        ClientView(id: 1, nickname: 'Zero', uid: 'zero', channelId: 1),
        ClientView(id: 2, nickname: 'Mia', uid: 'mia', channelId: 1),
        ClientView(
          id: 3,
          nickname: 'Alex',
          uid: 'alex',
          channelId: 1,
          inputMuted: true,
        ),
        ClientView(id: 4, nickname: 'Yuki', uid: 'yuki', channelId: 2),
      ],
      voiceInputReady: true,
      voiceOutputReady: true,
      speaking: const {2},
      messages: [
        ChatMessage(
          from: 'Mia',
          fromUid: 'mia',
          text: 'Hey everyone! Ready for a little catch-up?',
          at: DateTime(2026, 10, 27, 20, 30),
          scope: ChatScope.channel,
          targetId: 1,
        ),
        ChatMessage(
          from: 'Zero',
          fromUid: 'zero',
          text: 'Absolutely. Good to have everyone here.',
          at: DateTime(2026, 10, 27, 20, 31),
          scope: ChatScope.channel,
          targetId: 1,
        ),
        ChatMessage(
          from: 'Alex',
          fromUid: 'alex',
          text: 'The new space is looking great. Clean, quiet, and just what we need.',
          at: DateTime(2026, 10, 27, 20, 32),
          scope: ChatScope.channel,
          targetId: 1,
        ),
        ChatMessage(
          from: 'Mia',
          fromUid: 'mia',
          text: 'Let’s jump into voice — I have a few ideas to share.',
          at: DateTime(2026, 10, 27, 20, 33),
          scope: ChatScope.channel,
          targetId: 1,
        ),
      ],
    );

class _UiSessionController extends SessionController {
  _UiSessionController(this.initial);
  final SessionView initial;
  String? sentMessage;
  @override
  SessionView build() => initial;
  @override
  Future<void> setMuted(bool value) async {
    state = state.copyWith(muted: value);
  }

  @override
  Future<void> setDeafened(bool value) async {
    state = state.copyWith(deafened: value);
  }

  @override
  Future<void> setAway(bool value) async {
    state = state.copyWith(away: value);
  }

  @override
  Future<bool> disconnect() async {
    state = state.copyWith(state: const CoreSessionState.disconnected());
    return true;
  }

  @override
  Future<void> sendMessage(String message) async {
    sentMessage = message;
  }
}

Future<ProviderContainer> _pumpUi(
  WidgetTester tester, {
  required String route,
  Size size = const Size(1440, 900),
  AppThemePreference theme = AppThemePreference.dark,
  String locale = 'zh',
  bool empty = false,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final levels = StreamController<VoiceLevels>.broadcast();
  addTearDown(levels.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceLevelsProvider.overrideWith((ref) => levels.stream),
        sessionViewProvider.overrideWith(
          () => _UiSessionController(
            _session(connected: route != AppRoutes.connect, empty: empty),
          ),
        ),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore.inMemory(
            preferences: SessionPreferences(
              nickname: 'Zero',
              theme: theme,
              locale: locale,
            ),
          ),
        ),
        storePathProvider.overrideWithValue('/local/FlSpeak/servers.json'),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: const RepaintBoundary(
          key: ValueKey('ui-capture'),
          child: TsClientApp(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TsClientApp)),
  );
  container.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  if (_captureDirectory.isNotEmpty && route == AppRoutes.workspace) {
    for (final level in [
      0.08,
      0.14,
      0.3,
      0.62,
      0.85,
      0.5,
      0.26,
      0.4,
      0.72,
      0.96,
      0.65,
      0.32,
      0.14,
      0.27,
      0.5,
      0.8,
      0.59,
      0.36,
      0.16,
      0.1,
      0.24,
      0.48,
      0.31,
      0.12,
    ]) {
      levels.add(VoiceLevels(mic: level, received: level));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
  return container;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureDirectory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('ui-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_captureDirectory).create(recursive: true);
    await File('$_captureDirectory/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    if (_captureFont.isNotEmpty) {
      final font = FontLoader('Roboto')
        ..addFont(
          File(_captureFont)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await font.load();
    }
    if (_captureCjk.isNotEmpty) {
      final font = FontLoader('PingFang SC')
        ..addFont(
          File(_captureCjk)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await font.load();
    }
  });

  testWidgets('workspace: members, audio toggles, send, and disconnect', (
    tester,
  ) async {
    final container = await _pumpUi(tester, route: AppRoutes.workspace);
    expect(find.byType(MembersPane), findsOneWidget);
    await _capture(tester, 'workspace-dark');
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pumpAndSettle();
    expect(container.read(sessionViewProvider).muted, isTrue);
    await tester.tap(find.byIcon(Icons.headphones_rounded));
    await tester.pumpAndSettle();
    expect(container.read(sessionViewProvider).deafened, isTrue);
    await tester.enterText(find.byType(TextField), 'Hello from FlSpeak');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      (container.read(
        sessionViewProvider.notifier,
      ) as _UiSessionController).sentMessage,
      'Hello from FlSpeak',
    );
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, AppRoutes.connect);
    expect(container.read(sessionViewProvider).connected, isTrue);
    expect(find.text('主页'), findsOneWidget);
    container.read(routerProvider).go(AppRoutes.workspace);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, AppRoutes.connect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server search filters and shows a useful empty result', (
    tester,
  ) async {
    await _pumpUi(tester, route: AppRoutes.connect);
    await _capture(tester, 'connect-dark');
    await tester.enterText(find.byType(TextField), 'studio');
    await tester.pumpAndSettle();
    expect(find.text('Design studio'), findsNWidgets(2));
    expect(find.text('friends.example.com:9987'), findsNothing);
    await tester.enterText(find.byType(TextField), 'no-match');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的服务器'), findsOneWidget);
  });

  testWidgets('empty server library opens the add-server form', (tester) async {
    await _pumpUi(
      tester,
      route: AppRoutes.connect,
      size: const Size(375, 812),
      empty: true,
    );
    await _capture(tester, 'connect-empty-mobile');
    await tester.ensureVisible(find.text('添加第一台服务器'));
    await tester.tap(find.text('添加第一台服务器'));
    await tester.pumpAndSettle();
    expect(find.text('服务器地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings appearance changes the app theme and persists the choice',
    (tester) async {
      final container = await _pumpUi(tester, route: AppRoutes.settings);
      await _capture(tester, 'settings-dark');
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).theme,
        AppThemePreference.light,
      );
      expect(
        container.read(preferencesStoreProvider).current.theme,
        AppThemePreference.light,
      );
      expect(
        Theme.of(tester.element(find.text('浅色'))).brightness,
        Brightness.light,
      );
      await _capture(tester, 'settings-light');
      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('外观')).dy, inInclusiveRange(64, 160));
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(768, 1024),
    const Size(1024, 768),
  ]) {
    testWidgets('responsive workspace ${size.width} x ${size.height}', (
      tester,
    ) async {
      await _pumpUi(
        tester,
        route: AppRoutes.workspace,
        size: size,
        theme: AppThemePreference.light,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      if (size.width == 375) {
        await _capture(tester, 'workspace-mobile');
        await tester.tap(find.byIcon(Icons.menu_rounded));
        await tester.pumpAndSettle();
        expect(find.text('语音已连接'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'workspace-mobile-drawer');
      }
    });
  }

  testWidgets('mobile server library supports large English text', (
    tester,
  ) async {
    await _pumpUi(
      tester,
      route: AppRoutes.connect,
      size: const Size(375, 812),
      textScale: 2,
      locale: 'en',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile settings support large text', (tester) async {
    await _pumpUi(
      tester,
      route: AppRoutes.settings,
      size: const Size(375, 812),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, 'settings-mobile-large-text');
  });

  testWidgets('light desktop and English copy', (tester) async {
    await _pumpUi(
      tester,
      route: AppRoutes.workspace,
      theme: AppThemePreference.light,
      locale: 'en',
    );
    expect(find.text('Voice connected'), findsOneWidget);
    await _capture(tester, 'workspace-light');
  });
}
