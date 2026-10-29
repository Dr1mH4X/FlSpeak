// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import 'client_actions.dart';

class _Controller extends SessionController {
  final calls = <({String uid, int? clientId, String message})>[];
  bool succeed = false;
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
  );
  @override
  Future<bool> pokeClient(String uid, String message, {int? clientId}) async {
    calls.add((uid: uid, clientId: clientId, message: message));
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
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
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
      final menuButtons = tester
          .widgetList<MenuItemButton>(find.byType(MenuItemButton))
          .toList();
      final menuItems = menuButtons
          .map((item) => (item.child as Text).data)
          .toList();
      expect(menuItems, ['私信', '戳一戳', '权限管理', '踢出频道', '踢出服务器']);
      final menuThemeStyle = MenuButtonTheme.of(
        tester.element(find.byType(MenuItemButton).first),
      ).style;
      expect(menuThemeStyle?.iconSize?.resolve({}), IconSizes.medium);
      expect(menuThemeStyle?.textStyle?.resolve({})?.fontSize, 12.5);
      expect(
        IconTheme.of(
          tester.element(find.byIcon(Icons.chat_bubble_outline_rounded)),
        ).size,
        IconSizes.medium,
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('私信'))).style.fontSize,
        12.5,
      );
      await tester.tap(find.text('戳一戳'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello 🌍');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '戳一戳'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hello 🌍',
      );
      final controller =
          container.read(sessionViewProvider.notifier) as _Controller;
      controller.succeed = true;
      await tester.tap(find.widgetWithText(FilledButton, '戳一戳'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(controller.calls, [
        (uid: 'peer', clientId: 2, message: 'hello 🌍'),
        (uid: 'peer', clientId: 2, message: 'hello 🌍'),
      ]);
    },
  );
}
