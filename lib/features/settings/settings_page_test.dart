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
import '../../widgets/app_navigation_sidebar.dart';
import 'settings_page.dart';
import 'widgets/settings_section.dart';

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
              '/tmp/flspeak-test/preferences.json',
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

        // 两级菜单：先点击一级分类卡片进入二级页面
        final categoryRow = find.widgetWithText(
          SettingsTile,
          language ? '通用' : '外观',
        );
        await tester.ensureVisible(categoryRow);
        await tester.tap(categoryRow);
        await tester.pumpAndSettle();

        final row = find.widgetWithText(SettingsTile, language ? '语言' : '音频显示');
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
        storePathProvider.overrideWithValue(
          '/tmp/flspeak-test/preferences.json',
        ),
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

    // 先进入「外观」二级页面
    final appearanceCategory = find.widgetWithText(SettingsTile, '外观');
    await tester.ensureVisible(appearanceCategory);
    await tester.tap(appearanceCategory);
    await tester.pumpAndSettle();

    final row = find.widgetWithText(SettingsTile, '动效');
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

  testWidgets(
    'global navigation sidebar toggles expansion and subpage navigation operates cleanly',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
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

      // 侧边栏存在且遵守全仓无 Tooltip 约束
      expect(find.byType(AppNavigationSidebar), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);

      // 切换展开/收起
      final toggle = find.bySemanticsLabel('展开侧边栏');
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('收起侧边栏'), findsOneWidget);
      }

      // 点击一级菜单项「语音」进入二级页面
      final voiceCategory = find.widgetWithText(SettingsTile, '语音');
      await tester.ensureVisible(voiceCategory);
      await tester.tap(voiceCategory);
      await tester.pumpAndSettle();

      // 二级页面已占满展示
      expect(find.text('按住说话'), findsWidgets);
      expect(find.text('麦克风'), findsWidgets);

      // 点击顶部返回按钮返回一级菜单
      final backBtn = find.byIcon(Icons.arrow_back_rounded);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      // 返回一级菜单后重新见到各个大类入口
      expect(find.widgetWithText(SettingsTile, '外观'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '语音'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '通用'), findsOneWidget);
    },
  );

  testWidgets(
    'compact mobile mode hides sidebar and allows navigating to subpage',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(nickname: 'Test'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      // 窄屏下侧栏隐藏
      expect(find.byType(AppNavigationSidebar), findsNothing);

      // 点击数据大类进入二级数据页面
      final dataCategory = find.widgetWithText(SettingsTile, '数据');
      await tester.ensureVisible(dataCategory);
      await tester.tap(dataCategory);
      await tester.pumpAndSettle();

      // 二级页面已呈现并包含返回按钮
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '存储目录'), findsOneWidget);
    },
  );
}
