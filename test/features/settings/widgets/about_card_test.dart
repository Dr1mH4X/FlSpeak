// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/update_check.dart';
import 'package:flspeak/features/settings/widgets/about_card.dart';
import 'package:flspeak/l10n/app_localizations.dart';
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
        localizationsDelegates: [
          ...AppLocalizations.localizationsDelegates,
          const PrismUiLocalizationsDelegate(),
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AboutCard(
              version: version,
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

  testWidgets('shows the update dot and opens the release page', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final opened = <String>[];
    var refreshCalls = 0;
    await tester.pumpWidget(
      buildTestWidget(
        version: '0.1.0',
        updateResult: const UpdateStateView(
          available: true,
          latestVersion: '0.2.0',
          releaseUrl: 'https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0',
        ),
        checkClient: () async {
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
    final link = find.bySemanticsLabel('打开版本 0.2.0 的发布页面');
    expect(link, findsOneWidget);
    expect(
      tester
          .getSemantics(link)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.text('v0.1.0'));
    await tester.pumpAndSettle();
    expect(opened, ['https://github.com/Dr1mH4X/FlSpeak/releases/tag/v0.2.0']);
    semantics.dispose();
  });
}
