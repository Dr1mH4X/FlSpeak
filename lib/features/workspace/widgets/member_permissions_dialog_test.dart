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
  final changes = <({String uid, int? clientId, int group, bool enabled})>[];
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    clients: [ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 5)],
  );
  @override
  Future<bool> setMemberGroup(
    String uid,
    MemberGroupView group,
    bool enabled, {
    int? clientId,
  }) async {
    changes.add((
      uid: uid,
      clientId: clientId,
      group: group.id,
      enabled: enabled,
    ));
    return true;
  }
}

const _groups = [
  MemberGroupView(
    channelId: 5,
    id: 6,
    name: 'Server Admin',
    kind: GroupKind.server,
    member: false,
    canAdd: false,
    canRemove: false,
  ),
  MemberGroupView(
    channelId: 5,
    id: 7,
    name: 'Normal',
    kind: GroupKind.server,
    member: false,
    canAdd: true,
    canRemove: true,
  ),
  MemberGroupView(
    channelId: 5,
    id: 8,
    name: 'Guest',
    kind: GroupKind.channel,
    member: true,
    canAdd: true,
    canRemove: true,
  ),
];
Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required bool allowed,
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionViewProvider.overrideWith(_Controller.new),
      sessionAccessProvider.overrideWith(
        (ref) async => AccessView(
          memberAddPower: allowed ? 50 : 0,
          memberRemovePower: allowed ? 50 : 0,
        ),
      ),
      memberGroupsProvider((clientId: 2, uid: 'peer'))
          .overrideWith((ref) async => _groups),
    ],
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
              channelId: 5,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.more_horiz_rounded));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('ordinary user sees a disabled permission management action', (
    tester,
  ) async {
    await _mount(tester, allowed: false);
    final button = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, '权限管理'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets('authorized manager can change only assignable roles', (
    tester,
  ) async {
    final container = await _mount(tester, allowed: true);
    await tester.tap(find.text('权限管理'));
    await tester.pumpAndSettle();
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].onChanged, isNull);
    expect(switches[1].onChanged, isNotNull);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(
      (container.read(sessionViewProvider.notifier) as _Controller).changes,
      [(uid: 'peer', clientId: 2, group: 7, enabled: true)],
    );
  });
}
