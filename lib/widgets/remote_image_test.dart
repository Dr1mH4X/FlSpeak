// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/workspace/widgets/media_grid.dart';
import '../features/workspace/widgets/media_viewer.dart';
import '../features/workspace/widgets/message_content.dart';
import '../l10n/app_localizations.dart';
import 'remote_image.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
);

class _Api extends Fake implements RustLibApi {
  final requests = <String>[];
  bool fail = false;

  @override
  Future<Uint8List> crateApiSessionFetchImage({required String url}) async {
    requests.add(url);
    if (fail) throw const CoreError.connection(message: 'offline');
    return _png;
  }
}

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  // Codec completion uses the engine's real clock, outside widget-test fake time.
  await tester.runAsync(
    () =>
        precacheImage(MemoryImage(_png), tester.element(find.byType(Scaffold))),
  );
}

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.requests.clear();
    api.fail = false;
  });

  for (final text in [
    'https://example.com/a.png',
    '[IMG]https://example.com/a.png[/IMG]',
    '![cat](https://example.com/a.png)',
  ]) {
    testWidgets('chat loads standalone image through Rust: $text', (
      tester,
    ) async {
      await _mount(
        tester,
        MessageContent(text: text, style: const TextStyle()),
      );
      await tester.pumpAndSettle();
      expect(api.requests, ['https://example.com/a.png']);
      expect(find.byType(Image), findsOneWidget);
    });
  }

  testWidgets('media wall and viewer share the guarded request', (
    tester,
  ) async {
    const url = 'https://example.com/shared.png';
    await _mount(
      tester,
      Row(
        children: [
          Expanded(
            child: MediaGrid(urls: const [url], onOpen: (_) {}),
          ),
          const Expanded(child: MediaViewer(urls: [url])),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(api.requests, [url]);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('failed fetch retries in place and succeeds', (tester) async {
    api.fail = true;
    await _mount(
      tester,
      const RemoteImage(url: 'https://example.com/retry.png'),
    );
    await tester.pumpAndSettle();
    expect(find.text('图片加载失败'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(2));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('图片加载失败'), findsNothing);
  });

  testWidgets('viewer opens, changes page and closes', (tester) async {
    await _mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showMediaViewer(
            context,
            urls: const [
              'https://example.com/one.png',
              'https://example.com/two.png',
            ],
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewer), findsNothing);
  });
}
