// ignore_for_file: depend_on_referenced_packages

// 回归用例校验 SDK 与 material_ui 两套本地化类型同时可查。
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart' as sdk_cupertino;
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as sdk;
import 'package:flutter/widgets.dart' show BuildContext, Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as ui;

import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/localization.dart';

void main() {
  testWidgets('registers material_ui and Flutter SDK localizations', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      ui.MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: ui.Builder(
          builder: (value) {
            context = value;
            return const ui.SizedBox.shrink();
          },
        ),
      ),
    );

    expect(ui.MaterialLocalizations.of(context), isNotNull);
    expect(sdk.MaterialLocalizations.of(context), isNotNull);
    expect(sdk_cupertino.CupertinoLocalizations.of(context), isNotNull);
  });
}
