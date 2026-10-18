import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// 「上次连接」的相对时间。超过 30 天用短日期，避免出现「127 天前」。
String lastConnectedLabel(BuildContext context, DateTime? at) {
  final l10n = AppLocalizations.of(context);
  if (at == null) {
    return l10n.sessionLastConnectedNever;
  }
  final difference = DateTime.now().difference(at);
  if (difference.isNegative || difference.inMinutes < 1) {
    return l10n.sessionLastConnectedJustNow;
  }
  if (difference.inMinutes < 60) {
    return l10n.sessionLastConnectedMinutes(difference.inMinutes);
  }
  if (difference.inHours < 24) {
    return l10n.sessionLastConnectedHours(difference.inHours);
  }
  if (difference.inDays == 1) {
    return l10n.sessionLastConnectedYesterday;
  }
  if (difference.inDays < 30) {
    return l10n.sessionLastConnectedDays(difference.inDays);
  }
  return MaterialLocalizations.of(context).formatShortDate(at);
}
