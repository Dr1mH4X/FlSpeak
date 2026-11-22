import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/connect/widgets/connect_greeting.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/localization.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app({
  required DateTime Function() clock,
  SessionPreferences preferences = const SessionPreferences(nickname: 'Alice'),
  Locale locale = const Locale('zh'),
  ConnectPrompt prompt = ConnectPrompt.whereToChat,
}) {
  return ProviderScope(
    key: ValueKey(
      '${clock().toIso8601String()}-${locale.languageCode}-${prompt.name}',
    ),
    overrides: [
      preferencesStoreProvider.overrideWithValue(
        PreferencesStore.inMemory(preferences: preferences),
      ),
      clockProvider.overrideWithValue(clock),
      connectPromptProvider.overrideWithValue(prompt),
    ],
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: Padding(padding: EdgeInsets.all(20), child: ConnectGreeting()),
      ),
    ),
  );
}

void main() {
  testWidgets('greeting follows the local day period', (tester) async {
    final cases = <(DateTime, String)>[
      (DateTime(2026, 5, 1, 5), '上午好，Alice'),
      (DateTime(2026, 5, 1, 11, 59), '上午好，Alice'),
      (DateTime(2026, 5, 1, 12), '下午好，Alice'),
      (DateTime(2026, 5, 1, 17, 59), '下午好，Alice'),
      (DateTime(2026, 5, 1, 18), '晚上好，Alice'),
      (DateTime(2026, 5, 1, 23, 59), '晚上好，Alice'),
      (DateTime(2026, 5, 1, 0), '夜深了，Alice'),
      (DateTime(2026, 5, 1, 4, 59), '夜深了，Alice'),
    ];

    for (final (time, expected) in cases) {
      await tester.pumpWidget(_app(clock: () => time));
      await tester.pumpAndSettle();

      expect(find.text(expected), findsOneWidget, reason: '$time');
    }
  });

  testWidgets('greeting refreshes when the day period changes', (tester) async {
    var now = DateTime(2026, 5, 1, 11, 59, 30);
    await tester.pumpWidget(_app(clock: () => now));
    await tester.pumpAndSettle();

    expect(find.text('上午好，Alice'), findsOneWidget);

    now = DateTime(2026, 5, 1, 12, 0, 30);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(find.text('下午好，Alice'), findsOneWidget);
  });

  testWidgets('greeting omits placeholder nicknames', (tester) async {
    await tester.pumpWidget(
      _app(
        clock: () => DateTime(2026, 5, 1, 9),
        preferences: const SessionPreferences(
          nickname: SessionPreferences.fallbackNickname,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你好'), findsOneWidget);
    expect(
      find.textContaining(SessionPreferences.fallbackNickname),
      findsNothing,
    );
  });

  testWidgets('greeting welcomes back a nameless returning user', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        clock: () => DateTime(2026, 5, 1, 9),
        preferences: SessionPreferences(
          nickname: SessionPreferences.fallbackNickname,
          lastConnected: {'server-1': DateTime(2026, 4, 30)},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('欢迎回来'), findsOneWidget);
  });

  testWidgets('prompt keeps the provider choice', (tester) async {
    final cases = <(ConnectPrompt, String)>[
      (ConnectPrompt.whereToChat, '今天去哪聊？'),
      (ConnectPrompt.whatToDo, '今天做点什么？'),
      (ConnectPrompt.hopIn, '选个频道开麦？'),
    ];

    for (final (prompt, expected) in cases) {
      await tester.pumpWidget(
        _app(clock: () => DateTime(2026, 5, 1, 9), prompt: prompt),
      );
      await tester.pumpAndSettle();

      expect(find.text(expected), findsOneWidget);
    }
  });

  testWidgets('greeting and prompt localize to English', (tester) async {
    await tester.pumpWidget(
      _app(
        clock: () => DateTime(2026, 5, 1, 20),
        locale: const Locale('en'),
        prompt: ConnectPrompt.hopIn,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good evening, Alice'), findsOneWidget);
    expect(find.text('Ready to hop in?'), findsOneWidget);
  });

  testWidgets('greeting name stays on one line with ellipsis', (tester) async {
    await tester.pumpWidget(
      _app(
        clock: () => DateTime(2026, 5, 1, 9),
        preferences: const SessionPreferences(
          nickname: 'A very long identity name',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final greeting = tester.widget<Text>(
      find.text('上午好，A very long identity name'),
    );
    expect(greeting.maxLines, 1);
    expect(greeting.overflow, TextOverflow.ellipsis);
  });
}
