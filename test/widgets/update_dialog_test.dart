import 'package:flutter/material.dart' hide AlertDialog, TextButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak/widgets/update_dialog.dart';

void main() {
  test(
    'parseReleaseNotes parses FlSpeak release format and ignores contributors',
    () {
      const raw = '''
# 0.1.14 (2026-11-18): 主题定制、液态玻璃与 Android 窄屏体验优化

客户端重点改进 Android 与窄屏布局交互。

## 新增

- 新增外观与排版设置
- 新增液态玻璃材质

## 修复

- 修复音频初始化

## 贡献者

- @Dr1mH4X
''';

      final parsed = parseReleaseNotes(raw);
      expect(parsed.summary, '客户端重点改进 Android 与窄屏布局交互。');
      expect(parsed.sections.length, 2);
      expect(parsed.sections[0].title, '新增');
      expect(parsed.sections[0].entries, ['新增外观与排版设置', '新增液态玻璃材质']);
      expect(parsed.sections[1].title, '修复');
      expect(parsed.sections[1].entries, ['修复音频初始化']);
      expect(parsed.looseEntries, isEmpty);
    },
  );

  test(
    'parseReleaseNotes falls back to loose bullets when no h2 sections exist',
    () {
      const raw = '''
- 第一条改动
* 第二条改动
''';

      final parsed = parseReleaseNotes(raw);
      expect(parsed.summary, isNull);
      expect(parsed.sections, isEmpty);
      expect(parsed.looseEntries, ['第一条改动', '第二条改动']);
    },
  );

  testWidgets(
    'showUpdateAvailableDialog renders notes, respects showDoNotRemind, and has no Tooltip',
    (tester) async {
      bool? autoResult;
      bool? manualResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      autoResult = await showUpdateAvailableDialog(
                        context,
                        version: '0.2.0',
                        releaseNotes: '## 新增\n\n- 特性 A',
                        showDoNotRemind: true,
                      );
                    },
                    child: const Text('open-auto'),
                  ),
                  TextButton(
                    onPressed: () async {
                      manualResult = await showUpdateAvailableDialog(
                        context,
                        version: '0.2.0',
                        releaseNotes: null,
                        showDoNotRemind: false,
                      );
                    },
                    child: const Text('open-manual'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open-auto'));
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsNothing);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.textContaining('v0.2.0'), findsOneWidget);
      expect(find.textContaining('特性 A'), findsOneWidget);
      expect(find.text('不再提醒'), findsOneWidget);
      expect(find.text('前往下载'), findsOneWidget);
      await tester.tap(find.text('不再提醒'));
      await tester.pumpAndSettle();
      expect(autoResult, isFalse);

      await tester.tap(find.text('open-manual'));
      await tester.pumpAndSettle();
      expect(find.text('不再提醒'), findsNothing);
      expect(find.text('取消'), findsOneWidget);
      expect(find.textContaining('有新版本 0.2.0'), findsOneWidget);
      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();
      expect(manualResult, isTrue);
    },
  );
}
