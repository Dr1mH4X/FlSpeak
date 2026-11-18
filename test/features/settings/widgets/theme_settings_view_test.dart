// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        PopupMenuItem,
        Slider,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/system_fonts.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/features/settings/settings_page.dart';
import 'package:flspeak/features/settings/widgets/font_family_view.dart';
import 'package:flspeak/features/settings/widgets/palette.dart';
import 'package:flspeak/features/settings/widgets/settings_section.dart';
import 'package:flspeak/features/settings/widgets/theme_preview.dart';
import 'package:flspeak/features/settings/widgets/theme_settings_view.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

class _Core extends Fake implements CoreSession {}

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView();
}

class _Update extends UpdateController {
  @override
  UpdateStateView build() => const UpdateStateView(available: false);
}

Future<ProviderContainer> _mountSettings(
  WidgetTester tester, {
  SessionPreferences initialPreferences = const SessionPreferences(
    nickname: 'Test',
    locale: 'zh',
  ),
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_Core()),
      sessionViewProvider.overrideWith(_Session.new),
      updateProvider.overrideWith(_Update.new),
      appVersionProvider.overrideWithValue('0.1.0'),
      storePathProvider.overrideWithValue('/tmp/flspeak-test/preferences.json'),
      preferencesStoreProvider.overrideWithValue(
        PreferencesStore.inMemory(preferences: initialPreferences),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(
          Brightness.light,
          primaryColor: initialPreferences.primaryColor,
          colorStyle: initialPreferences.colorStyle,
          pureBlack: initialPreferences.pureBlack,
          fontFamily: initialPreferences.fontFamily,
        ),
        darkTheme: buildAppTheme(
          Brightness.dark,
          primaryColor: initialPreferences.primaryColor,
          colorStyle: initialPreferences.colorStyle,
          pureBlack: initialPreferences.pureBlack,
          fontFamily: initialPreferences.fontFamily,
        ),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          PrismUiLocalizationsDelegate(),
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final theme = Theme.of(context);
          return PrismRootScope(
            brightness: theme.brightness,
            primaryColor: initialPreferences.primaryColor,
            colorStyle: initialPreferences.colorStyle,
            pureBlack: initialPreferences.pureBlack,
            fontFamily: initialPreferences.fontFamily,
            textScale: initialPreferences.textScaleEnabled
                ? initialPreferences.textScale
                : null,
            child: child!,
          );
        },
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openAppearance(WidgetTester tester) async {
  final appearance = find.widgetWithText(SettingsTile, '外观');
  await tester.ensureVisible(appearance);
  await tester.tap(appearance);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'appearance page shows single top ThemeLivePreview without Tooltips or VoiceMeterSource',
    (tester) async {
      await _mountSettings(tester);
      await _openAppearance(tester);

      expect(find.byType(ThemeSettingsView), findsOneWidget);
      expect(find.byType(ThemeLivePreview), findsOneWidget);
      expect(find.byType(MiniScreen), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
      expect(find.byType(SettingsOptionsTile<VoiceMeterSource>), findsNothing);

      // 点击预览底栏第二个标签触发实时切换动画。
      final previewRect = tester.getRect(find.byType(ThemeLivePreview));
      await tester.tapAt(
        Offset(previewRect.center.dx + 32, previewRect.bottom - 38),
      );
      await tester.pumpAndSettle();

      // 返回后验证 VoiceMeterSource 已迁入「通用 -> 语音」。
      await tester.tap(
        find.bySemanticsLabel(
          MaterialLocalizations.of(tester.element(find.byType(SettingsPage)))
              .backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SettingsTile, '通用'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SettingsTile, '语音'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SettingsOptionsTile<VoiceMeterSource>, '音频显示'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'theme mode, pure black, bottom bar, tab animation, and liquid glass update preferences',
    (tester) async {
      final container = await _mountSettings(tester);
      await _openAppearance(tester);

      expect(
        container.read(preferencesProvider).theme,
        AppThemePreference.system,
      );

      await tester.tap(find.widgetWithText(DecorationListItem, '浅色'));
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).theme,
        AppThemePreference.light,
      );

      await tester.tap(find.widgetWithText(DecorationListItem, '纯黑'));
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).pureBlack, isTrue);

      final docked = find.widgetWithText(DecorationListItem, '停靠');
      await tester.ensureVisible(docked);
      await tester.tap(docked);
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).floatingNavigationBar,
        isFalse,
      );

      final fade = find.widgetWithText(DecorationListItem, '淡入淡出');
      await tester.ensureVisible(fade);
      await tester.tap(fade);
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).tabAnimation,
        TabAnimation.fade,
      );

      final ultra = find.widgetWithText(DecorationListItem, '极致');
      await tester.ensureVisible(ultra);
      await tester.tap(ultra);
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).liquidGlass,
        LiquidGlassMode.ultra,
      );
    },
  );

  testWidgets(
    'theme color defaults to #C44D78, supports custom Hex/Palette add, context menu delete, ColorStyle, and reset',
    (tester) async {
      final container = await _mountSettings(tester);
      await _openAppearance(tester);

      expect(
        container.read(preferencesProvider).primaryColor,
        defaultPrimaryColor,
      );
      expect(find.bySemanticsLabel('#C44D78'), findsOneWidget);
      expect(find.bySemanticsLabel('重置'), findsNothing);

      // 更改配色风格。
      final styleTile = find.widgetWithText(ListItem<AppColorStyle>, '配色风格');
      await tester.ensureVisible(styleTile);
      await tester.tap(styleTile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('单色').last);
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).colorStyle,
        AppColorStyle.monochrome,
      );

      // 出现重置按钮，点击添色打开 Palette 与 HexColorField。
      expect(find.bySemanticsLabel('重置'), findsWidgets);
      final addButton = find.bySemanticsLabel('添加颜色');
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.byType(Palette), findsOneWidget);
      expect(find.byType(HexColorField), findsOneWidget);
      // 确认滑块模式渲染三组滑块。
      await tester.tap(find.text('滑块'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Palette),
          matching: find.byType(Slider),
        ),
        findsNWidgets(3),
      );

      await tester.enterText(find.byType(HexColorField), '2F6F5E');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('完成'));
      await tester.pumpAndSettle();

      expect(container.read(preferencesProvider).primaryColor, 0xFF2F6F5E);
      expect(find.bySemanticsLabel('#2F6F5E'), findsOneWidget);

      // 右键菜单删除自定义颜色并二次确认。
      final customSwatch = find.bySemanticsLabel('#2F6F5E');
      await tester.ensureVisible(customSwatch);
      await tester.tapAt(
        tester.getCenter(customSwatch),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).primaryColors.contains(0xFF2F6F5E),
        isFalse,
      );

      // 重置主题色回到 #C44D78 与 vivid。
      final resetBtn = find.bySemanticsLabel('重置').first;
      await tester.ensureVisible(resetBtn);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '重置'));
      await tester.pumpAndSettle();
      expect(
        container.read(preferencesProvider).primaryColor,
        defaultPrimaryColor,
      );
      expect(
        container.read(preferencesProvider).colorStyle,
        AppColorStyle.vivid,
      );
    },
  );

  testWidgets(
    'font family sheet filters fonts, shows empty NullStatus, and selects system font',
    (tester) async {
      final originalReader = systemFontFamiliesReader;
      addTearDown(() => systemFontFamiliesReader = originalReader);
      systemFontFamiliesReader = () async => ['Inter', 'Noto Sans SC'];

      final container = await _mountSettings(tester);
      await _openAppearance(tester);

      final fontCard = find.text('默认').last;
      await tester.ensureVisible(fontCard);
      await tester.tap(fontCard);
      await tester.pumpAndSettle();

      expect(find.byType(FontFamilyView), findsOneWidget);
      expect(find.byType(SearchField), findsOneWidget);
      expect(find.text('Inter'), findsOneWidget);

      await tester.enterText(find.byType(SearchField), 'NoSuchFont');
      await tester.pumpAndSettle();
      expect(find.text('未找到匹配的字体'), findsOneWidget);

      await tester.enterText(find.byType(SearchField), 'Inter');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DecorationListItem, 'Inter'));
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).fontFamily, 'Inter');
    },
  );

  testWidgets(
    'compact appearance uses OpenContainer to push FontFamilyView full-screen and selects font',
    (tester) async {
      final originalReader = systemFontFamiliesReader;
      addTearDown(() => systemFontFamiliesReader = originalReader);
      systemFontFamiliesReader = () async => ['Roboto Mono'];

      final container = await _mountSettings(
        tester,
        size: const Size(390, 844),
      );
      await _openAppearance(tester);

      final fontCard = find.text('默认').last;
      await tester.ensureVisible(fontCard);
      await tester.tap(fontCard);
      await tester.pumpAndSettle();

      expect(find.byType(FontFamilyView), findsOneWidget);
      await tester.tap(find.widgetWithText(DecorationListItem, 'Roboto Mono'));
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).fontFamily, 'Roboto Mono');
    },
  );

  testWidgets(
    'text scale SegmentedControl and Slider update scale factor and reset restores 1.0',
    (tester) async {
      final container = await _mountSettings(tester);
      await _openAppearance(tester);

      final customSegment = find.text('自定义');
      await tester.ensureVisible(customSegment);
      await tester.tap(customSegment);
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).textScaleEnabled, isTrue);

      final slider = find.byType(Slider);
      await tester.ensureVisible(slider);
      await tester.drag(slider, const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).textScale, greaterThan(1.0));

      final resetBtn = find.bySemanticsLabel('重置').last;
      await tester.ensureVisible(resetBtn);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();
      expect(container.read(preferencesProvider).textScale, 1.0);
    },
  );
}
