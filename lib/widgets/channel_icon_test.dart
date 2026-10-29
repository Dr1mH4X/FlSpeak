// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/channel_icons.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../l10n/app_localizations.dart';
import 'channel_icon.dart';
import 'expressive_frame.dart';

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView(
    activeServerId: 'test',
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
  );
}

void main() {
  testWidgets(
    'download and decoding stop the morph; failure offers explicit retry',
    (tester) async {
      var calls = 0;
      var response = Completer<Uint8List>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionViewProvider.overrideWith(_Session.new),
            channelIconProvider(42).overrideWith((ref) {
              calls++;
              return response.future;
            }),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ChannelIcon(iconId: 42, color: Colors.purple)),
          ),
        ),
      );
      expect(
        tester.widget<ExpressiveFrame>(find.byType(ExpressiveFrame)).loading,
        isTrue,
      );
      response.completeError(StateError('transfer failed'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ExpressiveFrame>(find.byType(ExpressiveFrame)).loading,
        isFalse,
      );
      expect(find.bySemanticsLabel('重新加载频道图标'), findsOneWidget);
      response = Completer<Uint8List>();
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();
      expect(calls, 2);
      response.complete(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
        ),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        if (!tester
            .widget<ExpressiveFrame>(find.byType(ExpressiveFrame))
            .loading) {
          break;
        }
      }
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<ExpressiveFrame>(find.byType(ExpressiveFrame)).loading,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
