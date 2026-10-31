// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'widgets/chat_pane.dart';
import 'workspace_page.dart';
import 'workspace_state.dart';

class _Core extends Fake implements CoreSession {
  @override
  Future<AccessView> access() async => const AccessView();
}

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'test',
    connectionEpoch: 1,
    channels: [
      ChannelView(
        id: 5,
        parentId: 0,
        name: 'Lounge',
        description: '',
        order: 0,
      ),
      ChannelView(
        id: 6,
        parentId: 0,
        name: 'Studio',
        description: '',
        order: 0,
      ),
    ],
  );
}

Future<ProviderContainer> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_Core()),
      sessionViewProvider.overrideWith(_Session.new),
    ],
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
        home: const Scaffold(body: WorkspacePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('频道切换交叉淡入，退出中的输入区不能接收焦点或点击', (tester) async {
    final container = await _mount(tester);
    final field = find.descendant(
      of: find.byType(ChatPane),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.pump();
    final input = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(input.focusNode.hasFocus, isTrue);
    container
        .read(selectedChannelProvider.notifier)
        .select(6, serverId: 'test');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(ChatPane, skipOffstage: false), findsNWidgets(2));
    final outgoing = find.byWidgetPredicate(
      (widget) => widget is ChatPane && widget.channelName == 'Lounge',
      skipOffstage: false,
    );
    expect(
      find.ancestor(
        of: outgoing,
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsWidgets,
    );
    expect(input.focusNode.hasFocus, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(ChatPane), findsOneWidget);
    expect(
      tester.widget<ChatPane>(find.byType(ChatPane)).channelName,
      'Studio',
    );
  });
}
