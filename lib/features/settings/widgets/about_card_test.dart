// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/features/settings/widgets/about_card.dart';
import 'package:flspeak/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({
    Locale locale = const Locale('zh'),
    Future<bool> Function(String url)? onOpenUrl,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AboutCard(onOpenUrl: onOpenUrl ?? (_) async => true),
        ),
      ),
    );
  }

  testWidgets('renders about card elements correctly in Chinese and English', (
    tester,
  ) async {
    // 验证中文
    await tester.pumpWidget(buildTestWidget(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.text('FlSpeak'), findsOneWidget);
    expect(find.text('又一个跨平台、开源的 TeamSpeak 客户端'), findsOneWidget);
    expect(find.text('项目与源码'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('GitHub Issue'), findsOneWidget);
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
      await tester.tap(find.text('tsclient-rs'));
      await tester.pumpAndSettle();
      expect(opened, contains('https://github.com/Dr1mH4X/tsclient-rs'));
    },
  );
}
