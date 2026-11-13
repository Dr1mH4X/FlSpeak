// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        PopupMenuItem,
        Switch,
        TextButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/features/settings/settings_page.dart';
import 'package:flspeak/features/settings/widgets/settings_section.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/app_navigation_sidebar.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak/widgets/update_dot.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView();
}

class _Update extends UpdateController {
  @override
  UpdateStateView build() => const UpdateStateView(
    available: true,
    latestVersion: '0.2.0',
    releaseUrl: 'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
  );
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
              localizationsDelegates: const [
                ...AppLocalizations.localizationsDelegates,
                PrismUiLocalizationsDelegate(),
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) =>
                  PrismRootScope(brightness: Brightness.light, child: child!),
              home: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, show, child) =>
                    show ? const SettingsPage() : const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (!language) {
          // 音频显示在「外观」二级页面中
          final categoryRow = find.widgetWithText(SettingsTile, '外观');
          await tester.ensureVisible(categoryRow);
          await tester.tap(categoryRow);
          await tester.pumpAndSettle();
        }

        final row = find.widgetWithText(
          language
              ? SettingsOptionsTile<String?>
              : SettingsOptionsTile<VoiceMeterSource>,
          language ? '语言' : '音频显示',
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        visible.value = false;
        await tester.pump();
        await tester.tap(find.text(language ? 'English' : '接收音频').last);
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
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
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

    final row = find.widgetWithText(
      SettingsOptionsTile<AppMotionPreference>,
      '动效',
    );
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    // 弹出菜单中选择「关闭」
    expect(find.byType(PopupMenu), findsOneWidget);
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
    'picking language preference updates provider state and displays in trailing',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          appVersionProvider.overrideWithValue('0.1.0'),
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
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 一级概览卡片第一项即为语言选择
      final languageTile = find.widgetWithText(
        SettingsOptionsTile<String?>,
        '语言',
      );
      expect(languageTile, findsOneWidget);
      expect(find.text('中文'), findsOneWidget);

      // 点击语言项打开弹出菜单
      await tester.tap(languageTile);
      await tester.pumpAndSettle();

      // 弹出菜单中包含选项
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      // 点击选择 English
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      expect(container.read(preferencesProvider).locale, 'en');
    },
  );

  testWidgets(
    'global navigation sidebar toggles expansion and subpage navigation operates cleanly',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          appVersionProvider.overrideWithValue('0.1.0'),
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
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
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

      // 点击一级菜单项「通用」进入二级页面
      final generalCategory = find.widgetWithText(SettingsTile, '通用');
      await tester.ensureVisible(generalCategory);
      await tester.tap(generalCategory);
      await tester.pumpAndSettle();

      // 二级通用页面展示语音、屏幕共享与图片上传入口，且无小标题
      expect(find.widgetWithText(SettingsTile, '语音'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '屏幕共享'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '图片上传'), findsOneWidget);
      expect(find.text('按住说话'), findsNothing);

      // 点击二级「语音」进入三级独立页面
      final voiceTile = find.widgetWithText(SettingsTile, '语音');
      await tester.tap(voiceTile);
      await tester.pumpAndSettle();

      // 三级页面允许小标题并完整展示配置
      expect(find.text('按住说话'), findsWidgets);
      expect(find.text('麦克风'), findsWidgets);

      // 点击顶部返回按钮返回二级通用菜单
      final backBtn = find.byIcon(Icons.arrow_back_rounded);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      // 返回二级通用后重新见到通用子项入口
      expect(find.widgetWithText(SettingsTile, '语音'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '屏幕共享'), findsOneWidget);
      expect(find.text('按住说话'), findsNothing);

      // 再次点击返回按钮返回一级菜单
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      // 返回一级菜单后重新见到各个大类入口（语音和屏幕共享已降级至通用下）
      expect(find.widgetWithText(SettingsTile, '外观'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '通用'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '数据'), findsNothing);
      expect(find.widgetWithText(SettingsTile, '关于'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '语音'), findsNothing);
      expect(find.widgetWithText(SettingsTile, '屏幕共享'), findsNothing);
    },
  );

  testWidgets(
    'compact mobile mode hides sidebar and allows navigating to subpage',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          appVersionProvider.overrideWithValue('0.1.0'),
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
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 窄屏下侧栏隐藏且不再显示「数据」分类
      expect(find.byType(AppNavigationSidebar), findsNothing);
      expect(find.widgetWithText(SettingsTile, '数据'), findsNothing);

      // 点击通用大类进入二级通用页面
      final generalCategory = find.widgetWithText(SettingsTile, '通用');
      await tester.ensureVisible(generalCategory);
      await tester.tap(generalCategory);
      await tester.pumpAndSettle();

      // 二级页面已呈现并包含返回按钮与通用选项
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '语音'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '自动检查更新'), findsOneWidget);
      expect(
        find.widgetWithText(SettingsOptionsTile<AppLogLevel>, '日志等级'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'general settings toggles auto check update and switches log level via popup',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          appVersionProvider.overrideWithValue('0.1.0'),
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
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final generalCategory = find.widgetWithText(SettingsTile, '通用');
      await tester.tap(generalCategory);
      await tester.pumpAndSettle();

      // 自动检查更新默认开启，切换后更新偏好
      expect(container.read(preferencesProvider).autoCheckUpdate, isTrue);
      final autoUpdateTile = find.widgetWithText(SettingsTile, '自动检查更新');
      await tester.ensureVisible(autoUpdateTile);
      await tester.tap(autoUpdateTile);
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).autoCheckUpdate, isFalse);

      // 日志等级通过 popup 菜单切换
      final logLevelTile = find.widgetWithText(
        SettingsOptionsTile<AppLogLevel>,
        '日志等级',
      );
      await tester.ensureVisible(logLevelTile);
      expect(
        find.descendant(
          of: logLevelTile,
          matching: find.text(AppLogLevel.defaultForBuild.id),
        ),
        findsOneWidget,
      );

      await tester.tap(logLevelTile);
      await tester.pumpAndSettle();

      expect(find.text('debug'), findsWidgets);
      expect(find.text('info'), findsWidgets);
      expect(find.text('warning'), findsWidgets);
      expect(find.text('error'), findsWidgets);

      await tester.tap(find.text('warning').last);
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).logLevel, AppLogLevel.warning);
      expect(find.byType(Tooltip), findsNothing);
    },
  );

  testWidgets(
    'screen share settings category updates resolution, framerate, codec, and degradation preferences',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          appVersionProvider.overrideWithValue('0.1.0'),
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
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final generalCategory = find.widgetWithText(SettingsTile, '通用');
      expect(generalCategory, findsOneWidget);
      await tester.ensureVisible(generalCategory);
      await tester.tap(generalCategory);
      await tester.pumpAndSettle();

      final screenShareTile = find.widgetWithText(SettingsTile, '屏幕共享');
      expect(screenShareTile, findsOneWidget);
      await tester.tap(screenShareTile);
      await tester.pumpAndSettle();

      expect(find.byType(Tooltip), findsNothing);

      final resolutionRow = find.widgetWithText(
        SettingsOptionsTile<ScreenShareResolutionPreset>,
        '默认分辨率',
      );
      await tester.tap(resolutionRow);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenu), findsOneWidget);
      await tester.tap(find.text('720p').last);
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).screenShareResolution,
        ScreenShareResolutionPreset.p720,
      );

      final codecRow = find.widgetWithText(
        SettingsOptionsTile<ScreenShareCodecPreference>,
        '视频编码与硬件加速',
      );
      await tester.tap(codecRow);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenu), findsOneWidget);
      await tester.tap(find.text('VP8 优先').last);
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).screenShareCodec,
        ScreenShareCodecPreference.vp8,
      );
    },
  );

  testWidgets(
    'ESC key performs breadcrumb navigation from level 3 to level 2 to level 1 and preserves subheading rules',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          appVersionProvider.overrideWithValue('0.1.0'),
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
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 一级概览无小标题分组
      expect(find.text('设置'), findsWidgets); // 仅顶栏标题
      final generalCategory = find.widgetWithText(SettingsTile, '通用');
      await tester.tap(generalCategory);
      await tester.pumpAndSettle();

      // 二级通用无小标题
      expect(find.text('通用'), findsWidgets);
      final voiceTile = find.widgetWithText(SettingsTile, '语音');
      await tester.tap(voiceTile);
      await tester.pumpAndSettle();

      // 三级语音拥有小标题
      expect(find.text('按住说话'), findsWidgets);
      expect(find.text('麦克风'), findsWidgets);

      // 按 ESC 退回二级通用
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SettingsTile, '语音'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '屏幕共享'), findsOneWidget);
      expect(find.text('按住说话'), findsNothing);

      // 再次按 ESC 退回一级概览
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SettingsTile, '外观'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '通用'), findsOneWidget);
      expect(find.widgetWithText(SettingsTile, '语音'), findsNothing);
    },
  );

  testWidgets('shows an update dot on the About entry', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(_Core()),
        sessionViewProvider.overrideWith(_Session.new),
        updateProvider.overrideWith(_Update.new),
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
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDot), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('有新版本 0.2.0')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'settings subpage push and back use directional horizontal slide transitions without InkSparkle',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
          updateProvider.overrideWith(_Update.new),
          appVersionProvider.overrideWithValue('0.1.0'),
          storePathProvider.overrideWithValue(
            '/tmp/flspeak-test/preferences.json',
          ),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(
                nickname: 'Test',
                locale: 'zh',
                motion: AppMotionPreference.on,
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
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 概览页单行普通项与语言 Popup 项高度严格一致
      final baseX = tester
          .renderObject<RenderBox>(
            find.byKey(const ValueKey<String>('overview')),
          )
          .localToGlobal(Offset.zero)
          .dx;
      final overviewHeights = tester
          .renderObjectList<RenderBox>(find.byType(ListRow))
          .map((box) => box.size.height)
          .toList();
      expect(overviewHeights.every((h) => h >= 48.0), isTrue);

      // 进入通用二级页：通用页自右侧滑入（正向 dx > baseX）
      await tester.tap(find.widgetWithText(SettingsTile, '通用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final incomingGeneralBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey<String>('general')),
      );
      expect(
        incomingGeneralBox.localToGlobal(Offset.zero).dx,
        greaterThan(baseX),
      );
      await tester.pumpAndSettle();

      // 通用页使用 Switch 且行高一致
      expect(find.byType(Switch), findsOneWidget);
      final generalHeights = tester
          .renderObjectList<RenderBox>(find.byType(ListRow))
          .map((box) => box.size.height)
          .toList();
      expect(generalHeights.every((h) => h >= 48.0), isTrue);

      // 返回概览页：被揭开的概览页从左侧回位（dx < baseX），退出中的通用页向右滑出（dx > baseX）
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final revealedOverviewBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey<String>('overview')),
      );
      final exitingGeneralBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey<String>('general')),
      );
      expect(
        revealedOverviewBox.localToGlobal(Offset.zero).dx,
        lessThan(baseX),
      );
      expect(
        exitingGeneralBox.localToGlobal(Offset.zero).dx,
        greaterThan(baseX),
      );
      await tester.pumpAndSettle();

      // 进入关于二级页并验证无 InkSparkle 污染
      await tester.tap(find.widgetWithText(SettingsTile, '关于'));
      await tester.pumpAndSettle();
      for (final ink in tester.widgetList<InkWell>(find.byType(InkWell))) {
        expect(ink.splashFactory, NoSplash.splashFactory);
      }
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('overview')), findsOneWidget);
    },
  );
}
