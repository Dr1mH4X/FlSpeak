// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../workspace_page.dart';
import '../workspace_state.dart';
import 'channel_details_pane.dart';
import 'media_grid.dart';

class _FakeCore extends Fake implements CoreSession {
  _FakeCore({this.descriptionResult, this.throwError = false});

  final String? descriptionResult;
  final bool throwError;
  int callCount = 0;

  @override
  Future<String> channelDescription({required int channelId}) async {
    callCount++;
    if (throwError) {
      throw const CoreError.internal(message: 'Failed to fetch description');
    }
    return descriptionResult ?? '';
  }
}

class _Controller extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 7),
    channels: [
      ChannelView(
        id: 7,
        parentId: 0,
        name: 'General Discussion',
        description: '',
      ),
      ChannelView(id: 8, parentId: 0, name: 'Gaming Channel', description: ''),
    ],
    activeServerId: 'server-1',
  );
}

void main() {
  const testChannel = ChannelView(
    id: 7,
    parentId: 0,
    name: 'General Discussion',
    description: '',
  );

  testWidgets('displays channel description fetched from core', (tester) async {
    final core = _FakeCore(descriptionResult: 'Welcome to TeamSpeak channel!');
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_Controller.new),
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
          home: Scaffold(body: ChannelDetailsPane(channel: testChannel)),
        ),
      ),
    );

    // Initial loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('General Discussion'), findsOneWidget);
    expect(find.text('Welcome to TeamSpeak channel!'), findsOneWidget);
    expect(core.callCount, 1);
  });

  testWidgets('displays empty state when channel description is blank', (
    tester,
  ) async {
    final core = _FakeCore(descriptionResult: '   ');
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_Controller.new),
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
          home: Scaffold(body: ChannelDetailsPane(channel: testChannel)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('此频道暂无简介'), findsOneWidget);
  });

  testWidgets('displays error and allows retry when fetch fails', (
    tester,
  ) async {
    final core = _FakeCore(throwError: true);
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_Controller.new),
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
          home: Scaffold(body: ChannelDetailsPane(channel: testChannel)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('获取频道简介失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // Tap retry
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(core.callCount, 2);
  });

  testWidgets(
    'switching to details tab displays channel details in workspace without dialog',
    (tester) async {
      final core = _FakeCore(descriptionResult: 'Channel topic & details');
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          sessionViewProvider.overrideWith(_Controller.new),
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
            home: Scaffold(body: WorkspacePage()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find details tab icon in the header
      final detailsTab = find.byIcon(Icons.info_outline_rounded);
      expect(detailsTab, findsOneWidget);

      // Switch to details tab
      await tester.tap(detailsTab);
      await tester.pumpAndSettle();

      // Verify that ChannelDetailsPane is shown in the workspace without any dialog
      expect(find.byType(ChannelDetailsPane), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Channel topic & details'), findsOneWidget);

      // Verify that the pane starts from the top and is not vertically centered
      final channelTitleOffset = tester.getTopLeft(
        find.descendant(
          of: find.byType(ChannelDetailsPane),
          matching: find.text('General Discussion'),
        ),
      );
      // Header is 64px, padding is 24px, inner padding is 16px -> dy is around 104px (not vertically centered at ~250px)
      expect(channelTitleOffset.dy, lessThan(150));
    },
  );

  testWidgets(
    'switching channel preserves active tab without resetting to chat',
    (tester) async {
      final core = _FakeCore(descriptionResult: 'Gaming Channel Details');
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          sessionViewProvider.overrideWith(_Controller.new),
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
            home: Scaffold(body: WorkspacePage()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to media tab
      final mediaTab = find.byIcon(Icons.photo_library_rounded);
      expect(mediaTab, findsOneWidget);
      await tester.tap(mediaTab);
      await tester.pumpAndSettle();

      expect(find.byType(MediaGrid), findsOneWidget);

      // Select another channel (previewing channel 8)
      container
          .read(selectedChannelProvider.notifier)
          .select(8, serverId: 'server-1');
      await tester.pumpAndSettle();

      // Tab should still be media, not reset to chat
      expect(find.byType(MediaGrid), findsOneWidget);
      expect(find.text('Gaming Channel'), findsOneWidget);
    },
  );
}
