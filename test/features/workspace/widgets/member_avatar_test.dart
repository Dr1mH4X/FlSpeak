import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/member_avatars.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/member_avatar.dart';

class _AvatarCore extends Fake implements CoreSession {
  _AvatarCore(this._events, this._handler);

  final Stream<CoreEvent> _events;
  final Future<Uint8List?> Function(String uid) _handler;
  int calls = 0;

  @override
  Stream<CoreEvent> events() => _events;

  @override
  Future<List<ServerProfileView>> listServers() async => const [];

  @override
  Future<List<ServerIconView>> listServerIcons() async => const [];

  @override
  Future<Uint8List?> fetchAvatar({required String uid}) {
    calls++;
    return _handler(uid);
  }
}

class _ConnectedController extends SessionController {
  @override
  SessionView build() => super.build().copyWith(
    activeServerId: 'srv-1',
    connectionEpoch: 1,
    state: const CoreSessionState.connected(clientId: 1, channelId: 1),
  );
}

void main() {
  testWidgets(
    'avatar uses downloaded bytes and defaults when absent or invalid',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
      );
      Future<void> mount(String uid, Future<Uint8List?> Function() load) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              memberAvatarProvider(uid).overrideWith((ref) => load()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SessionMemberAvatar(uid: uid, nickname: 'Alice'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount('present', () async => png);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('AL'), findsNothing);
      await mount('absent', () async => null);
      expect(find.byType(Image), findsNothing);
      expect(find.text('AL'), findsOneWidget);
      await mount('missing', () => Future.error(StateError('missing')));
      expect(find.byType(Image), findsNothing);
      expect(find.text('AL'), findsOneWidget);
      await mount('invalid', () async => Uint8List.fromList([1, 2, 3]));
      expect(find.text('AL'), findsOneWidget);
      await mount(
        '',
        () => throw StateError('empty UID must not request an avatar'),
      );
      expect(find.text('AL'), findsOneWidget);
    },
  );

  testWidgets(
    'SessionMemberAvatar renders initials on null without retry and updates on avatarUpdated',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
      );
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      Uint8List? currentAvatar;
      final core = _AvatarCore(events.stream, (_) async => currentAvatar);
      addTearDown(events.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreSessionProvider.overrideWithValue(core),
            sessionViewProvider.overrideWith(_ConnectedController.new),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SessionMemberAvatar(uid: 'alice-uid', nickname: 'Alice'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(core.calls, 1);
      expect(find.byType(Image), findsNothing);
      expect(find.text('AL'), findsOneWidget);

      await tester.pump(const Duration(minutes: 2));
      expect(core.calls, 1);

      currentAvatar = png;
      events.add(const CoreEvent.avatarUpdated(uid: 'alice-uid'));
      await tester.pumpAndSettle();
      expect(core.calls, 2);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('AL'), findsNothing);

      currentAvatar = null;
      events.add(const CoreEvent.avatarUpdated(uid: 'alice-uid'));
      await tester.pumpAndSettle();
      expect(core.calls, 3);
      expect(find.byType(Image), findsNothing);
      expect(find.text('AL'), findsOneWidget);
    },
  );
}
