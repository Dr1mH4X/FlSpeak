import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/member_avatars.dart';
import 'package:flspeak/features/workspace/widgets/member_avatar.dart';

void main() {
  testWidgets(
    'avatar uses downloaded bytes and defaults when absent or invalid',
    (tester) async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
      );
      Future<void> mount(String uid, Future<Uint8List> Function() load) async {
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
}
