import 'package:flutter/widgets.dart' show LocalizationsDelegate;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' as ui;

import 'l10n/app_localizations.dart';
import 'widgets/prism.dart' show PrismUiLocalizationsDelegate;

/// 应用与组件测试共用的本地化代理。
///
/// `material_ui` 在自身的库里定义 `MaterialLocalizations`；SDK 的
/// `GlobalMaterialLocalizations` 提供的是另一个同名类型，无法被
/// `material_ui` 与 `cupertino_ui` 的组件查到。`flutter_markdown_plus`
/// 等第三方包仍从 SDK 取控件，因此两套代理都要注册。
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  // flutter_markdown_plus 等第三方包仍渲染 SDK 控件，迁移完成前保留 SDK 代理。
  // ignore: deprecated_member_use
  GlobalMaterialLocalizations.delegate,
  // ignore: deprecated_member_use
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  ...ui.GlobalMaterialLocalizations.delegates,
  PrismUiLocalizationsDelegate(),
];
