// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/features/settings/widgets/about_card.dart';
import 'package:flspeak/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({Future<bool> Function(String url)? onOpenUrl}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AboutCard(onOpenUrl: onOpenUrl ?? (_) async => true),
        ),
      ),
    );
  }

  testWidgets('renders about card elements correctly', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('FlSpeak'), findsOneWidget);
    expect(find.text('自托管 TeamSpeak 3 客户端'), findsOneWidget);
    expect(find.text('项目与源码'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('GitHub Issue'), findsOneWidget);
    expect(find.text('许可证'), findsOneWidget);
    expect(
      find.text('GNU Affero General Public License v3.0 (AGPL-3.0)'),
      findsOneWidget,
    );
    expect(find.text('Powered by Flutter & Rust'), findsOneWidget);

    // 严禁包含 Tooltip
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets(
    'clicking links triggers onOpenUrl callback with exact target urls',
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
    },
  );
}
