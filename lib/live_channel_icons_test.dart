// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app.dart';
import 'core/channel_icons.dart';
import 'core/preferences.dart';
import 'core/providers.dart';
import 'router.dart';
import 'widgets/channel_icon.dart';
import 'widgets/expressive_frame.dart';

const _server = String.fromEnvironment('FLSPEAK_LIVE_SERVER');
const _library = String.fromEnvironment('FLSPEAK_NATIVE_LIBRARY');
const _capture = String.fromEnvironment('FLSPEAK_CAPTURE_DIR');
const _font = String.fromEnvironment('FLSPEAK_CAPTURE_FONT');
const _cjk = String.fromEnvironment('FLSPEAK_CAPTURE_CJK');

void main() {
  testWidgets('live actor and FFI render real channel icons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late CoreSession session;
    late Directory directory;
    late ServerProfileView profile;
    await tester.runAsync(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(_library));
      directory = await Directory.systemTemp.createTemp('flspeak-live-ui-');
      session = CoreSession(
        storePath: '${directory.path}/servers.json',
        audioEnabled: false,
      );
      profile = await session.registerServer(label: _server, address: _server);
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      for (final pair in [('Roboto', _font), ('PingFang SC', _cjk)]) {
        if (pair.$2.isNotEmpty) {
          await (FontLoader(pair.$1)..addFont(
                File(pair.$2).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
        }
      }
    });
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(session),
        storePathProvider.overrideWithValue('${directory.path}/servers.json'),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore.inMemory(
            preferences: const SessionPreferences(
              nickname: 'FlSpeak-ui-probe',
              locale: 'zh',
            ),
          ),
        ),
      ],
    );
    try {
      debugPrint('live: register and connect');
      final controller = container.read(sessionViewProvider.notifier);
      await tester.runAsync(() async {
        await session.setAutoReconnect(enabled: false);
        expect(
          await controller.connect(
            id: profile.id,
            nickname: 'FlSpeak-ui-probe',
          ),
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      debugPrint('live: connected event delivered');
      final view = container.read(sessionViewProvider);
      expect(view.connected, isTrue);
      final ids = view.channels
          .map((channel) => channel.iconId)
          .whereType<int>()
          .where((id) => id != 0)
          .toSet();
      expect(ids, isNotEmpty);
      final subscriptions = [
        for (final id in ids)
          container.listen(channelIconProvider(id), (previous, next) {}),
      ];
      for (var attempt = 0; attempt < 500; attempt++) {
        await tester.pump();
        if (ids.every(
          (id) => container.read(channelIconProvider(id)).hasValue,
        )) {
          break;
        }
        final errors = ids
            .map((id) => container.read(channelIconProvider(id)))
            .where((value) => value.hasError);
        expect(errors, isEmpty);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      for (final id in ids) {
        final bytes = container.read(channelIconProvider(id)).requireValue;
        expect(bytes, isNotEmpty);
        debugPrint('live icon $id: ${bytes.length} bytes');
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RepaintBoundary(
            key: ValueKey('live-ui'),
            child: TsClientApp(),
          ),
        ),
      );
      container.read(routerProvider).go(AppRoutes.workspace);
      await tester.pump();
      for (var frame = 0; frame < 30; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 40));
        final pending = tester
            .widgetList<ExpressiveFrame>(
              find.descendant(
                of: find.byType(ChannelIcon),
                matching: find.byType(ExpressiveFrame),
              ),
            )
            .any((frame) => frame.loading);
        if (frame > 4 && !pending) break;
      }
      expect(find.byType(Image), findsWidgets);
      expect(
        tester
            .widgetList<ExpressiveFrame>(
              find.descendant(
                of: find.byType(ChannelIcon),
                matching: find.byType(ExpressiveFrame),
              ),
            )
            .every((frame) => !frame.loading),
        isTrue,
      );
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      if (_capture.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('live-ui')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await Directory(_capture).create(recursive: true);
          await File('$_capture/live-channel-icons.png')
              .writeAsBytes(data!.buffer.asUint8List());
        });
      }
      for (final subscription in subscriptions) {
        subscription.close();
      }
    } finally {
      await tester.runAsync(() async {
        await session.disconnect();
        await session.shutdown();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  }, skip: _server.isEmpty || _library.isEmpty);
}
