import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Self-hosted TeamSpeak'**
  String get appTitle;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'FlSpeak'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Self-hosted TeamSpeak client'**
  String get appTagline;

  /// No description provided for @connectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to a server'**
  String get connectTitle;

  /// No description provided for @connectAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get connectAddressLabel;

  /// No description provided for @connectAddressHint.
  ///
  /// In en, this message translates to:
  /// **'ts.example.com or ts.example.com:9987'**
  String get connectAddressHint;

  /// No description provided for @connectAddressHelp.
  ///
  /// In en, this message translates to:
  /// **'A full host name or IP. Port defaults to 9987.'**
  String get connectAddressHelp;

  /// No description provided for @connectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectAction;

  /// No description provided for @connectKnownServers.
  ///
  /// In en, this message translates to:
  /// **'Registered servers'**
  String get connectKnownServers;

  /// No description provided for @connectNoServers.
  ///
  /// In en, this message translates to:
  /// **'No server yet. Type an address above to register the first one.'**
  String get connectNoServers;

  /// No description provided for @connectNewServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Register a new server'**
  String get connectNewServerTitle;

  /// No description provided for @connectBack.
  ///
  /// In en, this message translates to:
  /// **'Back to all servers'**
  String get connectBack;

  /// No description provided for @connectNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get connectNicknameLabel;

  /// No description provided for @connectNicknameHelp.
  ///
  /// In en, this message translates to:
  /// **'The name others see. No account needed.'**
  String get connectNicknameHelp;

  /// No description provided for @serverLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label (optional)'**
  String get serverLabelField;

  /// No description provided for @serverAdd.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get serverAdd;

  /// No description provided for @serverRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get serverRemove;

  /// No description provided for @serverDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get serverDisconnect;

  /// No description provided for @serverInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid server address.'**
  String get serverInvalidAddress;

  /// No description provided for @railServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get railServers;

  /// No description provided for @railCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse server bar'**
  String get railCollapse;

  /// No description provided for @channelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channelsTitle;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @channelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Not connected.'**
  String get channelsEmpty;

  /// No description provided for @channelExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get channelExpand;

  /// No description provided for @channelCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get channelCollapse;

  /// No description provided for @channelJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get channelJoin;

  /// No description provided for @channelCurrent.
  ///
  /// In en, this message translates to:
  /// **'You are here'**
  String get channelCurrent;

  /// No description provided for @workspaceOnlineCount.
  ///
  /// In en, this message translates to:
  /// **'{count} online'**
  String workspaceOnlineCount(int count);

  /// No description provided for @workspaceNotConnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get workspaceNotConnectedTitle;

  /// No description provided for @workspaceNotConnectedBody.
  ///
  /// In en, this message translates to:
  /// **'Pick a registered server from the bar on the left, or add a new address.'**
  String get workspaceNotConnectedBody;

  /// No description provided for @workspaceReturn.
  ///
  /// In en, this message translates to:
  /// **'Back to workspace'**
  String get workspaceReturn;

  /// No description provided for @workspaceRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get workspaceRefresh;

  /// No description provided for @chatScopeChannel.
  ///
  /// In en, this message translates to:
  /// **'This channel'**
  String get chatScopeChannel;

  /// No description provided for @chatScopeServer.
  ///
  /// In en, this message translates to:
  /// **'Whole server'**
  String get chatScopeServer;

  /// No description provided for @chatComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get chatComposerHint;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatEmptyChannel.
  ///
  /// In en, this message translates to:
  /// **'No messages in this channel yet.'**
  String get chatEmptyChannel;

  /// No description provided for @chatEmptyServer.
  ///
  /// In en, this message translates to:
  /// **'No server-wide messages yet.'**
  String get chatEmptyServer;

  /// No description provided for @chatDirectTag.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get chatDirectTag;

  /// No description provided for @chatNoChannel.
  ///
  /// In en, this message translates to:
  /// **'Join a channel before sending channel messages.'**
  String get chatNoChannel;

  /// No description provided for @sessionConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get sessionConnected;

  /// No description provided for @voiceRustNote.
  ///
  /// In en, this message translates to:
  /// **'Capture, playback and the Opus codec live in Rust (core/audio). Audio frames never cross the FFI boundary; routing them through the session actor is the next milestone.'**
  String get voiceRustNote;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsLocale.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLocale;

  /// No description provided for @settingsLocaleSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLocaleSystem;

  /// No description provided for @settingsStorePath.
  ///
  /// In en, this message translates to:
  /// **'Core state file'**
  String get settingsStorePath;

  /// No description provided for @settingsValidateTitle.
  ///
  /// In en, this message translates to:
  /// **'Check an address'**
  String get settingsValidateTitle;

  /// No description provided for @settingsValidateHint.
  ///
  /// In en, this message translates to:
  /// **'host or host:port'**
  String get settingsValidateHint;

  /// No description provided for @settingsValidate.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get settingsValidate;

  /// No description provided for @settingsValidateOk.
  ///
  /// In en, this message translates to:
  /// **'Allowed, normalized to'**
  String get settingsValidateOk;

  /// No description provided for @settingsAudioTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get settingsAudioTitle;

  /// No description provided for @complianceTitle.
  ///
  /// In en, this message translates to:
  /// **'Compliance'**
  String get complianceTitle;

  /// No description provided for @compliancePolicy.
  ///
  /// In en, this message translates to:
  /// **'This client only connects to servers you entered yourself and never contacts official TeamSpeak services.'**
  String get compliancePolicy;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commonMore;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
