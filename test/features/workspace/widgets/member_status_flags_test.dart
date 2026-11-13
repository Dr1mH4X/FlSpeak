import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        Divider,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/member_status_flags.dart';
import 'package:flspeak/features/workspace/widgets/members_pane.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

class _FlagsController extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'test',
    channels: [
      ChannelView(
        id: 5,
        parentId: 0,
        name: 'Lounge',
        description: '',
        order: 0,
      ),
    ],
    clients: [
      ClientView(id: 1, nickname: 'Me', uid: 'uid-me', channelId: 5),
      ClientView(
        id: 2,
        nickname: 'AliceWithAVeryLongNicknameThatTruncatesInSidebar',
        uid: 'uid-alice',
        channelId: 5,
        inputMuted: true,
        outputMuted: true,
        away: true,
        awayMessage: 'BRB',
      ),
    ],
    streams: [
      StreamView(
        id: 'stream-1',
        clientId: 2,
        name: 'Alice Screen',
        hasAudio: false,
      ),
    ],
  );

  void watchStreamById(String? id) {
    state = state.copyWith(watchingStreamId: id);
  }
}

Future<void> _mountPanes(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final view = ref.watch(sessionViewProvider);
              return Row(
                children: [
                  const SizedBox(
                    width: 288,
                    height: 600,
                    child: ChannelPanel(),
                  ),
                  SizedBox(
                    height: 600,
                    child: MembersPane(view: view, channelId: 5),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'channel and members panes keep compact right-aligned status flags in fixed order',
    (tester) async {
      final container = ProviderContainer(
        overrides: [sessionViewProvider.overrideWith(_FlagsController.new)],
      );
      addTearDown(container.dispose);
      await _mountPanes(tester, container);

      void expectOrderedIn(Finder root) {
        final micDx = tester
            .getTopLeft(
              find.descendant(
                of: root,
                matching: find.byIcon(Icons.mic_off_rounded),
              ),
            )
            .dx;
        final speakerDx = tester
            .getTopLeft(
              find.descendant(
                of: root,
                matching: find.byIcon(Icons.volume_off_rounded),
              ),
            )
            .dx;
        final awayDx = tester
            .getTopLeft(
              find.descendant(
                of: root,
                matching: find.byIcon(Icons.schedule_rounded),
              ),
            )
            .dx;
        final shareDx = tester
            .getTopLeft(
              find.descendant(
                of: root,
                matching: find.byIcon(Icons.screen_share_rounded),
              ),
            )
            .dx;
        expect(micDx, lessThan(speakerDx));
        expect(speakerDx, lessThan(awayDx));
        expect(awayDx, lessThan(shareDx));
      }

      final channelFlags = find
          .descendant(
            of: find.byType(ChannelPanel),
            matching: find.byType(MemberStatusFlags),
          )
          .at(1);
      final membersFlags = find
          .descendant(
            of: find.byType(MembersPane),
            matching: find.byType(MemberStatusFlags),
          )
          .at(1);

      expectOrderedIn(channelFlags);
      expectOrderedIn(membersFlags);
      expect(find.byKey(const ValueKey('member-stream-2')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MembersPane),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );

      final beforeChannelRight = tester.getTopRight(channelFlags).dx;
      final beforeMembersRight = tester.getTopRight(membersFlags).dx;

      (container.read(sessionViewProvider.notifier) as _FlagsController)
          .watchStreamById('stream-1');
      await tester.pump();

      expectOrderedIn(channelFlags);
      expectOrderedIn(membersFlags);
      expect(tester.getTopRight(channelFlags).dx, beforeChannelRight);
      expect(tester.getTopRight(membersFlags).dx, beforeMembersRight);
    },
  );
}
