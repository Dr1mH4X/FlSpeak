import 'dart:ui' show Locale;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/l10n/app_localizations.dart';

void main() {
  test('backend notice codes map to localized copy', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final zh = lookupAppLocalizations(const Locale('zh'));

    expect(
      describeBackendNotice('voice.sync_failed', en),
      en.noticeVoiceSyncFailed,
    );
    expect(describeBackendNotice('session.kicked', zh), zh.noticeKicked);
    expect(describeBackendNotice('unknown.code', en), en.noticeUnknown);
  });

  test('core errors do not expose backend detail in the UI', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final zh = lookupAppLocalizations(const Locale('zh'));

    expect(
      describeCoreError(const CoreError.connection(message: 'detail'), en),
      en.errorConnectionFailed,
    );
    expect(
      describeCoreError(const CoreError.blockedAddress(message: 'detail'), zh),
      zh.errorBlockedAddress,
    );
  });
}
