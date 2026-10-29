// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import 'channel_details_dialog.dart';

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
          home: Scaffold(body: ChannelDetailsDialog(channel: testChannel)),
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
          home: Scaffold(body: ChannelDetailsDialog(channel: testChannel)),
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
          home: Scaffold(body: ChannelDetailsDialog(channel: testChannel)),
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

  testWidgets('tapping channel details button opens the dialog', (
    tester,
  ) async {
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
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => IconButton(
                onPressed: () => showChannelDetailsDialog(context, testChannel),
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('频道详情'), findsOneWidget);
    expect(find.text('Channel topic & details'), findsOneWidget);
  });
}
