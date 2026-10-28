// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import 'client_actions.dart';

class _Controller extends SessionController {
  final calls = <({String uid, String message})>[];
  bool succeed = false;
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
  );
  @override
  Future<bool> pokeClient(String uid, String message) async {
    calls.add((uid: uid, message: message));
    return succeed;
  }
}

void main() {
  testWidgets(
    'member action submits a poke and preserves text on server failure',
    (tester) async {
      final container = ProviderContainer(
        overrides: [sessionViewProvider.overrideWith(_Controller.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ClientActionsButton(
                client: ClientView(
                  id: 2,
                  nickname: 'Peer',
                  uid: 'peer',
                  channelId: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('戳一下'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello 🌍');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '戳一下'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hello 🌍',
      );
      final controller =
          container.read(sessionViewProvider.notifier) as _Controller;
      controller.succeed = true;
      await tester.tap(find.widgetWithText(FilledButton, '戳一下'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(controller.calls, [
        (uid: 'peer', message: 'hello 🌍'),
        (uid: 'peer', message: 'hello 🌍'),
      ]);
    },
  );
}
