// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/core/notices.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/notice_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatelessWidget {
  const _Harness({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: mode,
      home: const Scaffold(
        body: Stack(
          children: [
            Center(child: Text('content')),
            Positioned(top: 0, right: 0, child: NoticeHost()),
          ],
        ),
      ),
    );
  }
}

Finder noticeText(String message) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == message,
);

Future<ProviderContainer> pumpHost(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(child: _Harness(mode: mode)));
  return ProviderScope.containerOf(tester.element(find.byType(NoticeHost)));
}

void main() {
  testWidgets('MaterialApp.builder 顶层可以挂载提示', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const Positioned(top: 0, right: 0, child: NoticeHost()),
            ],
          ),
          home: const Scaffold(body: Center(child: Text('content'))),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NoticeHost)),
    );

    container.read(noticeCenterProvider.notifier).show('boom');
    await tester.pumpAndSettle();

    expect(noticeText('boom'), findsOneWidget);
  });

  testWidgets('没有提示时不拦截右上角的点击', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                const Positioned(top: 0, right: 0, child: NoticeHost()),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(990, 6));

    expect(tapped, isTrue);
  });

  testWidgets('提示出现在右上角且不移动页面内容', (tester) async {
    final container = await pumpHost(tester);
    final contentBefore = tester.getRect(find.text('content'));

    container.read(noticeCenterProvider.notifier).show('boom');
    await tester.pumpAndSettle();

    expect(noticeText('boom'), findsOneWidget);
    expect(tester.getRect(find.text('content')), contentBefore);

    final rect = tester.getRect(noticeText('boom'));
    expect(rect.top, lessThan(80));
    expect(rect.right, greaterThan(900));
  });

  testWidgets('关闭按钮移除提示，命中区域达到触控下限', (tester) async {
    final container = await pumpHost(tester);
    container.read(noticeCenterProvider.notifier).show('boom');
    await tester.pumpAndSettle();

    final close = find.widgetWithIcon(IconButton, Icons.close_rounded);
    expect(tester.getSize(close), const Size(Sizes.touch, Sizes.touch));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(noticeText('boom'), findsNothing);
    expect(container.read(noticeCenterProvider), isEmpty);
  });

  testWidgets('错误 8 秒后自动消失，提示 5 秒后消失', (tester) async {
    final container = await pumpHost(tester);
    final center = container.read(noticeCenterProvider.notifier);

    center.show('failure');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 7));
    expect(noticeText('failure'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(noticeText('failure'), findsNothing);

    center.show('copied', tone: NoticeTone.info);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(noticeText('copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(noticeText('copied'), findsNothing);
  });

  testWidgets('超过三条时只显示最新的三条', (tester) async {
    final container = await pumpHost(tester);
    final center = container.read(noticeCenterProvider.notifier);

    for (final message in ['one', 'two', 'three', 'four']) {
      center.show(message);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNWidgets(3));
    expect(noticeText('one'), findsNothing);
    expect(noticeText('four'), findsOneWidget);
  });

  testWidgets('深色主题用错误容器色', (tester) async {
    final container = await pumpHost(tester, mode: ThemeMode.dark);
    container.read(noticeCenterProvider.notifier).show('boom');
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NoticeHost));
    final scheme = Theme.of(context).colorScheme;
    expect(
      find.ancestor(
        of: noticeText('boom'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.color == scheme.errorContainer,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('提示 tone 用次级容器色', (tester) async {
    final container = await pumpHost(tester);
    container
        .read(noticeCenterProvider.notifier)
        .show('copied', tone: NoticeTone.info);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NoticeHost));
    final scheme = Theme.of(context).colorScheme;
    expect(
      find.ancestor(
        of: noticeText('copied'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.color == scheme.secondaryContainer,
        ),
      ),
      findsOneWidget,
    );
  });
}
