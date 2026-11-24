import 'package:material_ui/material_ui.dart' hide AlertDialog;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/core/notices.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/features/settings/widgets/about_card.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/localization.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak/widgets/update_dot.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

class _FixedUpdateController extends UpdateController {
  _FixedUpdateController(this.initial);

  final UpdateStateView initial;

  @override
  UpdateStateView build() => initial;
}

void main() {
  Widget buildTestWidget({
    Locale locale = const Locale('zh'),
    String? version,
    bool isDebug = false,
    Future<bool> Function(String url)? onOpenUrl,
    UpdateStateView updateResult = const UpdateStateView(available: false),
    UpdateCheckClient? checkClient,
  }) {
    return ProviderScope(
      overrides: [
        appVersionProvider.overrideWithValue('0.1.0'),
        updateProvider.overrideWith(() => _FixedUpdateController(updateResult)),
        if (checkClient != null)
          updateCheckClientProvider.overrideWithValue(checkClient),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AboutCard(
              version: version,
              isDebug: isDebug,
              onOpenUrl: onOpenUrl ?? (_) async => true,
            ),
          ),
        ),
      ),
    );
  }

  test('rejects non-http external urls', () async {
    expect(await openExternalUrl('file:///tmp/flspeak'), isFalse);
    expect(await openExternalUrl('ftp://example.com/file'), isFalse);
    expect(await openExternalUrl('not a url'), isFalse);
  });

  testWidgets('renders about card elements correctly in Chinese and English', (
    tester,
  ) async {
    // 验证中文
    await tester.pumpWidget(buildTestWidget(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.byType(SurfaceCard), findsOneWidget);
    final iconImage = tester.widget<Image>(find.byType(Image));
    expect(
      (iconImage.image as AssetImage).assetName,
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png',
    );
    expect(find.text('FlSpeak'), findsOneWidget);
    expect(find.text('v0.1.0'), findsOneWidget);
    expect(find.text('又一个跨平台、开源的 TeamSpeak 客户端'), findsOneWidget);
    expect(find.text('项目与源码'), findsOneWidget);
    expect(find.text('项目官网: '), findsOneWidget);
    expect(find.text('点击前往'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('GitHub Issue'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('点击前往')).dy,
      lessThan(tester.getTopLeft(find.text('GitHub')).dy),
    );
    expect(find.text('许可证'), findsOneWidget);
    expect(
      find.text('GNU Affero General Public License v3.0 (AGPL-3.0)'),
      findsOneWidget,
    );
    expect(find.text('Powered by '), findsOneWidget);
    expect(find.text('tsclient-rs'), findsOneWidget);
    expect(find.text(' · Supports '), findsOneWidget);
    expect(find.text('OpenProtocol'), findsOneWidget);

    // 验证所有链接 MouseRegion 鼠标悬停均为可点击手型
    final mouseRegions = tester.widgetList<MouseRegion>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion && widget.cursor == SystemMouseCursors.click,
      ),
    );
    expect(mouseRegions.length, greaterThanOrEqualTo(4));

    // 严禁包含 Tooltip
    expect(find.byType(Tooltip), findsNothing);

    // 验证英文
    await tester.pumpWidget(buildTestWidget(locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Yet another teamspeak client, multi-platform and open-source.',
      ),
      findsOneWidget,
    );
    expect(find.text('Project & Source'), findsOneWidget);
    expect(find.text('Project Website: '), findsOneWidget);
    expect(find.text('Visit'), findsOneWidget);
  });

  testWidgets(
    'clicking links triggers onOpenUrl callback with exact target urls including tsclient-rs',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        buildTestWidget(
          onOpenUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      // 点击项目官网链接
      await tester.tap(find.text('点击前往'));
      await tester.pumpAndSettle();
      expect(opened, contains('https://flspeak.dreamhax.cc'));

      // 点击 GitHub 源码链接
      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();
      expect(opened, contains('https://github.com/Dr1mH4X/FlSpeak'));

      // 点击 Issue 链接
      await tester.tap(find.text('GitHub Issue'));
      await tester.pumpAndSettle();
      expect(opened, contains('https://github.com/Dr1mH4X/FlSpeak/issues'));

      // 点击许可证链接
      await tester.tap(
        find.text('GNU Affero General Public License v3.0 (AGPL-3.0)'),
      );
      await tester.pumpAndSettle();
      expect(
        opened,
        contains('https://github.com/Dr1mH4X/FlSpeak/blob/main/LICENSE'),
      );

      // 点击 tsclient-rs 链接
      await tester.ensureVisible(find.text('tsclient-rs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tsclient-rs'));
      await tester.pumpAndSettle();
      expect(opened, contains('https://github.com/Dr1mH4X/tsclient-rs'));

      // 点击 OpenProtocol 链接
      await tester.ensureVisible(find.text('OpenProtocol'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenProtocol'));
      await tester.pumpAndSettle();
      expect(
        opened,
        contains(
          'https://github.com/Dr1mH4X/tsclient-rs/blob/master/docs/open-protocol.md',
        ),
      );
    },
  );

  testWidgets('renders custom version in pill correctly', (tester) async {
    await tester.pumpWidget(buildTestWidget(version: '0.2.5'));
    await tester.pumpAndSettle();
    expect(find.text('v0.2.5'), findsOneWidget);

    await tester.pumpWidget(buildTestWidget(version: 'v1.0.0'));
    await tester.pumpAndSettle();
    expect(find.text('v1.0.0'), findsOneWidget);
  });

  testWidgets(
    'appends debug suffixes in debug mode without duplicating prerelease',
    (tester) async {
      await tester.pumpWidget(buildTestWidget(isDebug: true));
      await tester.pumpAndSettle();
      expect(find.text('FlSpeak Debug'), findsOneWidget);
      expect(find.text('v0.1.0-debug'), findsOneWidget);

      await tester.pumpWidget(
        buildTestWidget(
          version: '0.1.15-main.123.abc1234',
          isDebug: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('FlSpeak Debug'), findsOneWidget);
      expect(find.text('v0.1.15-main.123.abc1234'), findsOneWidget);
    },
  );

  testWidgets('does not make the version pill actionable without an update', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      buildTestWidget(
        version: '0.1.0',
        onOpenUrl: (url) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDot), findsNothing);
    await tester.tap(find.text('v0.1.0'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets(
    'shows the update dot on version pill without making it clickable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final opened = <String>[];
      var refreshCalls = 0;
      await tester.pumpWidget(
        buildTestWidget(
          version: '0.1.0',
          updateResult: const UpdateStateView(
            available: true,
            latestVersion: '0.2.0',
            releaseUrl:
                'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
            releaseNotes: '## 新增\n\n- 更新日志',
          ),
          checkClient: ({bool force = false}) async {
            refreshCalls++;
            return const UpdateStateView(available: false);
          },
          onOpenUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(refreshCalls, 0);
      expect(find.byType(UpdateDot), findsOneWidget);
      final badge = find.bySemanticsLabel('有新版本 0.2.0');
      expect(badge, findsOneWidget);
      expect(
        tester
            .getSemantics(badge)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );

      await tester.tap(find.text('v0.1.0'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsNothing);
      expect(opened, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'manual check updates button handles available, up-to-date, and error results',
    (tester) async {
      final opened = <String>[];
      final forceFlags = <bool>[];
      var mode = 'available';

      final container = ProviderContainer(
        overrides: [
          appVersionProvider.overrideWithValue('0.1.0'),
          updateCheckClientProvider.overrideWithValue(({
            bool force = false,
          }) async {
            forceFlags.add(force);
            return switch (mode) {
              'available' => const UpdateStateView(
                available: true,
                latestVersion: '0.2.0',
                releaseUrl:
                    'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
                releaseNotes: '## 修复\n\n- 修复若干问题',
              ),
              'upToDate' => const UpdateStateView(available: false),
              _ => throw StateError('network failed'),
            };
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AboutCard(
                  version: '0.1.0',
                  onOpenUrl: (url) async {
                    opened.add(url);
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 有更新：弹出更新弹窗（无「不再提醒」），点击「前往下载」打开链接
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(forceFlags, [true]);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('不再提醒'), findsNothing);
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();
      expect(opened, [
        'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
      ]);

      // 2. 已是最新：弹出单按钮提示框
      mode = 'upToDate';
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(forceFlags, [true, true]);
      expect(find.text('当前应用已经是最新版了'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('当前应用已经是最新版了'), findsNothing);

      // 3. 网络失败：通过 NoticeCenter 报错误横幅，不弹出「已是最新版」
      mode = 'error';
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('当前应用已经是最新版了'), findsNothing);
      final notices = container.read(noticeCenterProvider);
      expect(notices, isNotEmpty);
      expect(notices.first.message, '检查更新失败，请稍后重试');
      expect(notices.first.tone, NoticeTone.error);
    },
  );
}
