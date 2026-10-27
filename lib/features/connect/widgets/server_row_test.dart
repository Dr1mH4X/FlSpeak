// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/features/connect/widgets/server_row.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpRow(
  WidgetTester tester, {
  required VoidCallback onTap,
  required VoidCallback onRemove,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: ServerRow(
          profile: const ServerProfileView(
            id: 's1',
            label: 'Studio',
            host: 'localhost',
            port: 9987,
          ),
          lastConnected: null,
          connected: false,
          connecting: false,
          enabled: true,
          onTap: onTap,
          onRemove: onRemove,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('溢出菜单提供移除入口且不触发行连接', (tester) async {
    var tapped = false;
    var removed = false;
    await _pumpRow(
      tester,
      onTap: () => tapped = true,
      onRemove: () => removed = true,
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(tapped, isFalse);
    expect(find.text('从列表移除'), findsOneWidget);

    await tester.tap(find.text('从列表移除'));
    await tester.pumpAndSettle();
    expect(removed, isTrue);
  });
}
