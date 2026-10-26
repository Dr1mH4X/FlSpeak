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

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

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

  /// No description provided for @connectNicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get connectNicknameLabel;

  /// No description provided for @serverLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label (optional)'**
  String get serverLabelField;

  /// No description provided for @serverLabelHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Photo club'**
  String get serverLabelHint;

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

  /// No description provided for @serverRemoveFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove from list'**
  String get serverRemoveFromList;

  /// No description provided for @serverRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove server?'**
  String get serverRemoveTitle;

  /// No description provided for @serverRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'“{label}” will be removed from the list; local chat history stays.'**
  String serverRemoveBody(String label);

  /// No description provided for @serverAddAndConnect.
  ///
  /// In en, this message translates to:
  /// **'Add & connect'**
  String get serverAddAndConnect;

  /// No description provided for @serverAddAndConnecting.
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get serverAddAndConnecting;

  /// No description provided for @serverAddressRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a server address.'**
  String get serverAddressRequired;

  /// No description provided for @serverInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid server address.'**
  String get serverInvalidAddress;

  /// No description provided for @serverDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get serverDisconnect;

  /// No description provided for @serverEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No servers yet'**
  String get serverEmptyTitle;

  /// No description provided for @serverEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Add your first server'**
  String get serverEmptyAction;

  /// No description provided for @serversTitle.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get serversTitle;

  /// No description provided for @serversUsedBy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Used by 1 server} other{Used by {count} servers}}'**
  String serversUsedBy(int count);

  /// No description provided for @sessionConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get sessionConnected;

  /// No description provided for @sessionConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get sessionConnecting;

  /// No description provided for @sessionDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get sessionDisconnected;

  /// No description provided for @sessionConnectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to {name}'**
  String sessionConnectedTo(String name);

  /// No description provided for @sessionConnectingTo.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {name}…'**
  String sessionConnectingTo(String name);

  /// No description provided for @sessionLastConnectedNever.
  ///
  /// In en, this message translates to:
  /// **'Never connected'**
  String get sessionLastConnectedNever;

  /// No description provided for @sessionLastConnectedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get sessionLastConnectedJustNow;

  /// No description provided for @sessionLastConnectedMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String sessionLastConnectedMinutes(int count);

  /// No description provided for @sessionLastConnectedHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String sessionLastConnectedHours(int count);

  /// No description provided for @sessionLastConnectedYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get sessionLastConnectedYesterday;

  /// No description provided for @sessionLastConnectedDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String sessionLastConnectedDays(int count);

  /// No description provided for @workspaceReturn.
  ///
  /// In en, this message translates to:
  /// **'Back to workspace'**
  String get workspaceReturn;

  /// No description provided for @identityCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current identity'**
  String get identityCurrent;

  /// No description provided for @identityManage.
  ///
  /// In en, this message translates to:
  /// **'Manage identity'**
  String get identityManage;

  /// No description provided for @identityTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get identityTitle;

  /// No description provided for @identityRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get identityRename;

  /// No description provided for @identitySave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get identitySave;

  /// No description provided for @identityNicknameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nickname cannot be empty.'**
  String get identityNicknameEmpty;

  /// No description provided for @identityCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get identityCancel;

  /// No description provided for @identityUpgrading.
  ///
  /// In en, this message translates to:
  /// **'Upgrading identity level to {target}…'**
  String identityUpgrading(int target);

  /// No description provided for @channelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Not connected.'**
  String get channelsEmpty;

  /// No description provided for @channelsSection.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channelsSection;

  /// No description provided for @workspaceNoChannels.
  ///
  /// In en, this message translates to:
  /// **'This server has no channels yet.'**
  String get workspaceNoChannels;

  /// No description provided for @workspaceOpenMenu.
  ///
  /// In en, this message translates to:
  /// **'Open channel menu'**
  String get workspaceOpenMenu;

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

  /// No description provided for @channelPasswordProtected.
  ///
  /// In en, this message translates to:
  /// **'Channel password required'**
  String get channelPasswordProtected;

  /// No description provided for @channelJoinMenu.
  ///
  /// In en, this message translates to:
  /// **'Join channel'**
  String get channelJoinMenu;

  /// No description provided for @channelPaneResize.
  ///
  /// In en, this message translates to:
  /// **'Resize channel pane'**
  String get channelPaneResize;

  /// No description provided for @channelPaneResizeHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to resize, double-click to reset'**
  String get channelPaneResizeHint;

  /// No description provided for @voiceMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get voiceMute;

  /// No description provided for @voiceUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get voiceUnmute;

  /// No description provided for @voiceDeafen.
  ///
  /// In en, this message translates to:
  /// **'Deafen'**
  String get voiceDeafen;

  /// No description provided for @voiceUndeafen.
  ///
  /// In en, this message translates to:
  /// **'Undeafen'**
  String get voiceUndeafen;

  /// No description provided for @memberMicMuted.
  ///
  /// In en, this message translates to:
  /// **'Microphone muted'**
  String get memberMicMuted;

  /// No description provided for @memberSpeakerMuted.
  ///
  /// In en, this message translates to:
  /// **'Speaker muted'**
  String get memberSpeakerMuted;

  /// No description provided for @memberAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get memberAway;

  /// No description provided for @memberAwayWith.
  ///
  /// In en, this message translates to:
  /// **'Away: {message}'**
  String memberAwayWith(Object message);

  /// No description provided for @voiceAway.
  ///
  /// In en, this message translates to:
  /// **'Set away'**
  String get voiceAway;

  /// No description provided for @voiceUnaway.
  ///
  /// In en, this message translates to:
  /// **'Unset away'**
  String get voiceUnaway;

  /// No description provided for @voiceMicUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone unavailable'**
  String get voiceMicUnavailable;

  /// No description provided for @voiceSpeakerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Speaker unavailable'**
  String get voiceSpeakerUnavailable;

  /// No description provided for @voiceReconnectingAttempt.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting (attempt {attempt})…'**
  String voiceReconnectingAttempt(int attempt);

  /// No description provided for @chatTabMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get chatTabMessages;

  /// No description provided for @chatTabMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get chatTabMedia;

  /// No description provided for @chatWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to {channel}'**
  String chatWelcomeTitle(String channel);

  /// No description provided for @chatWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'This is the start of the channel. Share text, images and videos.'**
  String get chatWelcomeBody;

  /// No description provided for @chatComposerHintTo.
  ///
  /// In en, this message translates to:
  /// **'Message {target}'**
  String chatComposerHintTo(String target);

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Send to'**
  String get chatScopeTitle;

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

  /// No description provided for @chatUnsupportedImage.
  ///
  /// In en, this message translates to:
  /// **'Unsupported image format'**
  String get chatUnsupportedImage;

  /// No description provided for @chatImageLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading image…'**
  String get chatImageLoading;

  /// No description provided for @chatImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image failed to load'**
  String get chatImageLoadFailed;

  /// No description provided for @chatTs6Attachment.
  ///
  /// In en, this message translates to:
  /// **'TS6 official attachment'**
  String get chatTs6Attachment;

  /// No description provided for @chatTs6AttachmentPolicy.
  ///
  /// In en, this message translates to:
  /// **'myTeamSpeak media is not used; showing file metadata only.'**
  String get chatTs6AttachmentPolicy;

  /// No description provided for @chatDirectTag.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get chatDirectTag;

  /// No description provided for @mediaEmpty.
  ///
  /// In en, this message translates to:
  /// **'No images or videos in this channel yet'**
  String get mediaEmpty;

  /// No description provided for @mediaViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Media viewer'**
  String get mediaViewerTitle;

  /// No description provided for @mediaPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get mediaPrevious;

  /// No description provided for @mediaNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get mediaNext;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get settingsVoice;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsTheme;

  /// No description provided for @settingsThemeDesc.
  ///
  /// In en, this message translates to:
  /// **'System, light or dark'**
  String get settingsThemeDesc;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsPttMode.
  ///
  /// In en, this message translates to:
  /// **'Push to talk'**
  String get settingsPttMode;

  /// No description provided for @settingsPttModeDesc.
  ///
  /// In en, this message translates to:
  /// **'When off, voice activation is used'**
  String get settingsPttModeDesc;

  /// No description provided for @settingsPttHotkey.
  ///
  /// In en, this message translates to:
  /// **'Push-to-talk hotkey'**
  String get settingsPttHotkey;

  /// No description provided for @settingsPttHotkeyNone.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get settingsPttHotkeyNone;

  /// No description provided for @settingsPttHotkeyRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Record hotkey'**
  String get settingsPttHotkeyRecordTitle;

  /// No description provided for @settingsPttHotkeyRecordHint.
  ///
  /// In en, this message translates to:
  /// **'Press any key… (Esc to cancel)'**
  String get settingsPttHotkeyRecordHint;

  /// No description provided for @settingsPttHotkeyUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This key is not supported. Try another one.'**
  String get settingsPttHotkeyUnsupported;

  /// No description provided for @settingsPttHotkeyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsPttHotkeyClear;

  /// No description provided for @settingsInputDevice.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get settingsInputDevice;

  /// No description provided for @settingsOutputDevice.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get settingsOutputDevice;

  /// No description provided for @settingsDeviceDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsDeviceDefault;

  /// No description provided for @settingsAudioUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Audio devices unavailable'**
  String get settingsAudioUnavailable;

  /// No description provided for @settingsAudioLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading audio devices…'**
  String get settingsAudioLoading;

  /// No description provided for @settingsStorePath.
  ///
  /// In en, this message translates to:
  /// **'Storage directory'**
  String get settingsStorePath;

  /// No description provided for @settingsStorePathDesc.
  ///
  /// In en, this message translates to:
  /// **'Where profiles and preferences live'**
  String get settingsStorePathDesc;

  /// No description provided for @settingsAboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Self-hosted TeamSpeak client'**
  String get settingsAboutTagline;
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
