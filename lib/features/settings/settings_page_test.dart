// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import '../../core/preferences.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'settings_page.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView();
}

void main() {
  for (final language in [true, false]) {
    testWidgets(
      'closing settings before its picker returns does not access a disposed ref, language=$language',
      (tester) async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        final container = ProviderContainer(
          overrides: [
            coreSessionProvider.overrideWithValue(_Core()),
            sessionViewProvider.overrideWith(_Session.new),
            storePathProvider.overrideWithValue(
              '/tmp/flspeak-test/servers.json',
            ),
            preferencesStoreProvider.overrideWithValue(
              PreferencesStore.inMemory(
                preferences: const SessionPreferences(
                  nickname: 'Test',
                  locale: 'zh',
                ),
              ),
            ),
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
              home: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, show, child) =>
                    show ? const SettingsPage() : const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.text(language ? '语言' : '音频显示');
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        visible.value = false;
        await tester.pump();
        await tester.tap(find.text(language ? 'English' : '接收到的音频').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final preferences = container.read(preferencesProvider);
        expect(preferences.locale, 'zh');
        expect(preferences.voiceMeterSource, VoiceMeterSource.microphone);
      },
    );
  }

  testWidgets('picking motion preference updates provider state', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(_Core()),
        sessionViewProvider.overrideWith(_Session.new),
        storePathProvider.overrideWithValue('/tmp/flspeak-test/servers.json'),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore.inMemory(
            preferences: const SessionPreferences(nickname: 'Test'),
          ),
        ),
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
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('动效');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    // 弹层中选择「关闭」
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();

    expect(container.read(preferencesProvider).motion, AppMotionPreference.off);

    // 再次点击切回「开启」
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启').last);
    await tester.pumpAndSettle();

    expect(container.read(preferencesProvider).motion, AppMotionPreference.on);
  });
}
