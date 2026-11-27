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
  /// **'FlSpeak'**
  String get appTitle;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'FlSpeak'**
  String get appName;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @sidebarCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get sidebarCollapse;

  /// No description provided for @sidebarExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar'**
  String get sidebarExpand;

  /// No description provided for @windowPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get windowPin;

  /// No description provided for @windowUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get windowUnpin;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

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

  /// No description provided for @loggingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File logging is unavailable; the app keeps running with console logs.'**
  String get loggingUnavailable;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

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

  /// No description provided for @identityUpgraded.
  ///
  /// In en, this message translates to:
  /// **'Identity upgraded to level {level}. Reconnecting…'**
  String identityUpgraded(int level);

  /// No description provided for @avatarManage.
  ///
  /// In en, this message translates to:
  /// **'Manage avatar'**
  String get avatarManage;

  /// No description provided for @avatarTitle.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get avatarTitle;

  /// No description provided for @avatarChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get avatarChoose;

  /// No description provided for @avatarDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete avatar'**
  String get avatarDelete;

  /// No description provided for @avatarTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The selected image is too large.'**
  String get avatarTooLarge;

  /// No description provided for @avatarTooLargeWithLimit.
  ///
  /// In en, this message translates to:
  /// **'The selected image is too large. The limit is {limit}.'**
  String avatarTooLargeWithLimit(String limit);

  /// No description provided for @avatarPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You cannot change your avatar on this server.'**
  String get avatarPermissionDenied;

  /// No description provided for @avatarUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Choose a PNG, JPEG, GIF, or WebP image.'**
  String get avatarUnsupportedFormat;

  /// No description provided for @avatarUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The avatar could not be updated. Try again.'**
  String get avatarUnavailable;

  /// No description provided for @avatarRequiresConnection.
  ///
  /// In en, this message translates to:
  /// **'Connect to a server to manage your avatar.'**
  String get avatarRequiresConnection;

  /// No description provided for @workspaceDropped.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get workspaceDropped;

  /// No description provided for @workspaceRetrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying…'**
  String get workspaceRetrying;

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

  /// No description provided for @streamViewerResize.
  ///
  /// In en, this message translates to:
  /// **'Resize screen share height'**
  String get streamViewerResize;

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

  /// No description provided for @memberSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking'**
  String get memberSpeaking;

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

  /// No description provided for @voiceMicPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied; listening only'**
  String get voiceMicPermissionDenied;

  /// No description provided for @voiceMicPermissionSettings.
  ///
  /// In en, this message translates to:
  /// **'Enable microphone permission in system settings'**
  String get voiceMicPermissionSettings;

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

  /// No description provided for @chatScopeDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get chatScopeDirect;

  /// No description provided for @chatServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Server messages'**
  String get chatServerTitle;

  /// No description provided for @chatScopeUnread.
  ///
  /// In en, this message translates to:
  /// **'Send to, unread messages'**
  String get chatScopeUnread;

  /// No description provided for @chatUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread messages'**
  String get chatUnread;

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

  /// No description provided for @settingsVoiceMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get settingsVoiceMicrophone;

  /// No description provided for @settingsVoiceDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsVoiceDevices;

  /// No description provided for @settingsPttMode.
  ///
  /// In en, this message translates to:
  /// **'Push to talk'**
  String get settingsPttMode;

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

  /// No description provided for @settingsPttHotkeyInAppOnly.
  ///
  /// In en, this message translates to:
  /// **'In-app only'**
  String get settingsPttHotkeyInAppOnly;

  /// No description provided for @settingsPttHotkeyPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Input Monitoring permission required'**
  String get settingsPttHotkeyPermissionRequired;

  /// No description provided for @settingsPttHotkeyPortalPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Global shortcut not authorized'**
  String get settingsPttHotkeyPortalPermissionRequired;

  /// No description provided for @settingsPttHotkeyGrantPermission.
  ///
  /// In en, this message translates to:
  /// **'Authorize'**
  String get settingsPttHotkeyGrantPermission;

  /// No description provided for @settingsNoiseSuppression.
  ///
  /// In en, this message translates to:
  /// **'Noise suppression'**
  String get settingsNoiseSuppression;

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

  /// No description provided for @settingsVoiceMeter.
  ///
  /// In en, this message translates to:
  /// **'Audio display'**
  String get settingsVoiceMeter;

  /// No description provided for @settingsVoiceMeterMic.
  ///
  /// In en, this message translates to:
  /// **'Outgoing audio'**
  String get settingsVoiceMeterMic;

  /// No description provided for @settingsVoiceMeterReceived.
  ///
  /// In en, this message translates to:
  /// **'Received audio'**
  String get settingsVoiceMeterReceived;

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

  /// No description provided for @settingsAutoCheckUpdate.
  ///
  /// In en, this message translates to:
  /// **'Auto check updates'**
  String get settingsAutoCheckUpdate;

  /// No description provided for @settingsLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get settingsLogLevel;

  /// No description provided for @connectGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String connectGreetingMorning(String name);

  /// No description provided for @connectGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}'**
  String connectGreetingAfternoon(String name);

  /// No description provided for @connectGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening, {name}'**
  String connectGreetingEvening(String name);

  /// No description provided for @connectGreetingLateNight.
  ///
  /// In en, this message translates to:
  /// **'It\'s late, {name}'**
  String connectGreetingLateNight(String name);

  /// No description provided for @connectGreetingHello.
  ///
  /// In en, this message translates to:
  /// **'Hello'**
  String get connectGreetingHello;

  /// No description provided for @connectGreetingWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get connectGreetingWelcomeBack;

  /// No description provided for @connectPromptWhere.
  ///
  /// In en, this message translates to:
  /// **'Where to chat today?'**
  String get connectPromptWhere;

  /// No description provided for @connectPromptDoing.
  ///
  /// In en, this message translates to:
  /// **'What are we doing today?'**
  String get connectPromptDoing;

  /// No description provided for @connectPromptHopIn.
  ///
  /// In en, this message translates to:
  /// **'Ready to hop in?'**
  String get connectPromptHopIn;

  /// No description provided for @serverEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add a server address to join your people in a channel.'**
  String get serverEmptyBody;

  /// No description provided for @serverSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search servers'**
  String get serverSearchLabel;

  /// No description provided for @serverSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching servers'**
  String get serverSearchEmpty;

  /// No description provided for @membersTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel members'**
  String get membersTitle;

  /// No description provided for @memberDetails.
  ///
  /// In en, this message translates to:
  /// **'User details'**
  String get memberDetails;

  /// No description provided for @memberNickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get memberNickname;

  /// No description provided for @memberUid.
  ///
  /// In en, this message translates to:
  /// **'Unique ID'**
  String get memberUid;

  /// No description provided for @memberChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get memberChannel;

  /// No description provided for @memberUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This user is offline'**
  String get memberUnavailable;

  /// No description provided for @serverEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit server'**
  String get serverEdit;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @serverSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get serverSaving;

  /// No description provided for @serverAddressDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect to change the address'**
  String get serverAddressDisconnect;

  /// No description provided for @networkStatus.
  ///
  /// In en, this message translates to:
  /// **'Network status'**
  String get networkStatus;

  /// No description provided for @networkMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Checking network'**
  String get networkMeasuring;

  /// No description provided for @networkDegraded.
  ///
  /// In en, this message translates to:
  /// **'Unstable network'**
  String get networkDegraded;

  /// No description provided for @networkPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor network quality'**
  String get networkPoor;

  /// No description provided for @networkPing.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get networkPing;

  /// No description provided for @networkJitter.
  ///
  /// In en, this message translates to:
  /// **'Jitter'**
  String get networkJitter;

  /// No description provided for @networkLossIn.
  ///
  /// In en, this message translates to:
  /// **'Loss in'**
  String get networkLossIn;

  /// No description provided for @networkLossOut.
  ///
  /// In en, this message translates to:
  /// **'Loss out'**
  String get networkLossOut;

  /// No description provided for @networkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get networkUnavailable;

  /// No description provided for @networkMilliseconds.
  ///
  /// In en, this message translates to:
  /// **'{value} ms'**
  String networkMilliseconds(String value);

  /// No description provided for @voiceConnected.
  ///
  /// In en, this message translates to:
  /// **'Voice connected'**
  String get voiceConnected;

  /// No description provided for @memberListening.
  ///
  /// In en, this message translates to:
  /// **'In this channel'**
  String get memberListening;

  /// No description provided for @appearancePreview.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearancePreview;

  /// No description provided for @serverIconTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose server icon'**
  String get serverIconTitle;

  /// No description provided for @serverIconChange.
  ///
  /// In en, this message translates to:
  /// **'Change icon'**
  String get serverIconChange;

  /// No description provided for @serverIconAuto.
  ///
  /// In en, this message translates to:
  /// **'Server icon'**
  String get serverIconAuto;

  /// No description provided for @serverIconCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get serverIconCommunity;

  /// No description provided for @serverIconGaming.
  ///
  /// In en, this message translates to:
  /// **'Gaming'**
  String get serverIconGaming;

  /// No description provided for @serverIconMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get serverIconMusic;

  /// No description provided for @serverIconWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get serverIconWork;

  /// No description provided for @serverIconTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get serverIconTerminal;

  /// No description provided for @serverIconFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get serverIconFavorite;

  /// No description provided for @serverIconPlanet.
  ///
  /// In en, this message translates to:
  /// **'Planet'**
  String get serverIconPlanet;

  /// No description provided for @serverIconCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee'**
  String get serverIconCoffee;

  /// No description provided for @serverIconRocket.
  ///
  /// In en, this message translates to:
  /// **'Rocket'**
  String get serverIconRocket;

  /// No description provided for @serverIconScience.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get serverIconScience;

  /// No description provided for @channelIconRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry channel icon'**
  String get channelIconRetry;

  /// No description provided for @chatRecipientUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Recipient is offline. Choose another recipient.'**
  String get chatRecipientUnavailable;

  /// No description provided for @chatChannelUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Join this channel before sending a message.'**
  String get chatChannelUnavailable;

  /// No description provided for @chatDirectAction.
  ///
  /// In en, this message translates to:
  /// **'Direct message'**
  String get chatDirectAction;

  /// No description provided for @pokeAction.
  ///
  /// In en, this message translates to:
  /// **'Poke'**
  String get pokeAction;

  /// No description provided for @pokeMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get pokeMessage;

  /// No description provided for @pokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Poke {name}'**
  String pokeTitle(String name);

  /// No description provided for @pokeSent.
  ///
  /// In en, this message translates to:
  /// **'Poked {name}'**
  String pokeSent(String name);

  /// No description provided for @pokeReceived.
  ///
  /// In en, this message translates to:
  /// **'{name} poked you: {message}'**
  String pokeReceived(String name, String message);

  /// No description provided for @memberActions.
  ///
  /// In en, this message translates to:
  /// **'Actions for {name}'**
  String memberActions(String name);

  /// No description provided for @chatDestinationChanged.
  ///
  /// In en, this message translates to:
  /// **'The destination changed. Your draft was kept; confirm the recipient and retry.'**
  String get chatDestinationChanged;

  /// No description provided for @chatImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Images must be no larger than 20 MiB'**
  String get chatImageTooLarge;

  /// No description provided for @chatImageTooLargeWithLimit.
  ///
  /// In en, this message translates to:
  /// **'Images must be no larger than {limit}.'**
  String chatImageTooLargeWithLimit(String limit);

  /// No description provided for @chatImageUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Choose a PNG, JPEG, GIF, or WebP image.'**
  String get chatImageUnsupportedFormat;

  /// No description provided for @chatImageInputFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the image. Please choose it again.'**
  String get chatImageInputFailed;

  /// No description provided for @chatAttachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach image'**
  String get chatAttachImage;

  /// No description provided for @chatRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get chatRemoveImage;

  /// No description provided for @chatSelectMessages.
  ///
  /// In en, this message translates to:
  /// **'Select messages'**
  String get chatSelectMessages;

  /// No description provided for @chatSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String chatSelectedCount(int count);

  /// No description provided for @imageHostTitle.
  ///
  /// In en, this message translates to:
  /// **'Image uploads'**
  String get imageHostTitle;

  /// No description provided for @imageHostRequired.
  ///
  /// In en, this message translates to:
  /// **'Configure an image host in Image uploads first'**
  String get imageHostRequired;

  /// No description provided for @imageHostStorageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not access secure storage for image uploads'**
  String get imageHostStorageFailed;

  /// No description provided for @imageHostUploadBase.
  ///
  /// In en, this message translates to:
  /// **'HTTP PUT upload base URL'**
  String get imageHostUploadBase;

  /// No description provided for @imageHostPublicBase.
  ///
  /// In en, this message translates to:
  /// **'Public image base URL'**
  String get imageHostPublicBase;

  /// No description provided for @imageHostToken.
  ///
  /// In en, this message translates to:
  /// **'Bearer token (optional)'**
  String get imageHostToken;

  /// No description provided for @imageHostRemove.
  ///
  /// In en, this message translates to:
  /// **'Clear configuration'**
  String get imageHostRemove;

  /// No description provided for @imageHostSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get imageHostSave;

  /// No description provided for @imageHostErrorInvalid.
  ///
  /// In en, this message translates to:
  /// **'The image host address is invalid.'**
  String get imageHostErrorInvalid;

  /// No description provided for @imageHostErrorBlocked.
  ///
  /// In en, this message translates to:
  /// **'The image host address is blocked.'**
  String get imageHostErrorBlocked;

  /// No description provided for @imageHostErrorConnection.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the image host.'**
  String get imageHostErrorConnection;

  /// No description provided for @imageHostErrorInternal.
  ///
  /// In en, this message translates to:
  /// **'The image host operation failed.'**
  String get imageHostErrorInternal;

  /// No description provided for @imageHostUploadHint.
  ///
  /// In en, this message translates to:
  /// **'https://upload.example.com/images/'**
  String get imageHostUploadHint;

  /// No description provided for @imageHostPublicHint.
  ///
  /// In en, this message translates to:
  /// **'https://images.example.com/'**
  String get imageHostPublicHint;

  /// No description provided for @channelPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel password required'**
  String get channelPasswordTitle;

  /// No description provided for @channelPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Channel password'**
  String get channelPasswordLabel;

  /// No description provided for @channelPasswordWrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Try again.'**
  String get channelPasswordWrong;

  /// No description provided for @memberPermissions.
  ///
  /// In en, this message translates to:
  /// **'Manage permissions'**
  String get memberPermissions;

  /// No description provided for @permissionsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Permissions are unavailable'**
  String get permissionsUnavailable;

  /// No description provided for @serverGroups.
  ///
  /// In en, this message translates to:
  /// **'Server groups'**
  String get serverGroups;

  /// No description provided for @channelGroups.
  ///
  /// In en, this message translates to:
  /// **'Channel groups'**
  String get channelGroups;

  /// No description provided for @groupCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get groupCurrent;

  /// No description provided for @groupAssign.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get groupAssign;

  /// No description provided for @chatTabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get chatTabFiles;

  /// No description provided for @chatTabDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get chatTabDetails;

  /// No description provided for @fileParent.
  ///
  /// In en, this message translates to:
  /// **'Parent folder'**
  String get fileParent;

  /// No description provided for @fileDownload.
  ///
  /// In en, this message translates to:
  /// **'Download file'**
  String get fileDownload;

  /// No description provided for @fileUnlock.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get fileUnlock;

  /// No description provided for @fileListEmpty.
  ///
  /// In en, this message translates to:
  /// **'This channel has no files'**
  String get fileListEmpty;

  /// No description provided for @fileDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not download or save the file. Try again.'**
  String get fileDownloadFailed;

  /// No description provided for @fileDownloadSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get fileDownloadSaved;

  /// No description provided for @noticeVoiceInputUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone input is unavailable.'**
  String get noticeVoiceInputUnavailable;

  /// No description provided for @noticeVoiceOutputUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Audio output is unavailable.'**
  String get noticeVoiceOutputUnavailable;

  /// No description provided for @noticeVoiceCodecUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the channel codec.'**
  String get noticeVoiceCodecUnavailable;

  /// No description provided for @noticeVoiceCodecUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The channel codec is not supported.'**
  String get noticeVoiceCodecUnsupported;

  /// No description provided for @noticeVoiceCaptureFailed.
  ///
  /// In en, this message translates to:
  /// **'Audio capture failed.'**
  String get noticeVoiceCaptureFailed;

  /// No description provided for @noticeVoicePlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Audio playback failed.'**
  String get noticeVoicePlaybackFailed;

  /// No description provided for @noticeVoiceCodecFailed.
  ///
  /// In en, this message translates to:
  /// **'The audio codec failed.'**
  String get noticeVoiceCodecFailed;

  /// No description provided for @noticeVoiceSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice state sync failed; it will retry automatically.'**
  String get noticeVoiceSyncFailed;

  /// No description provided for @noticePttHotkeyInAppOnly.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey unavailable; push-to-talk works in-app only'**
  String get noticePttHotkeyInAppOnly;

  /// No description provided for @noticePttHotkeyPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Global hotkey requires Input Monitoring permission; working in-app only'**
  String get noticePttHotkeyPermissionDenied;

  /// No description provided for @noticePttHotkeyPortalPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Global shortcut unauthorized; reset in System Settings'**
  String get noticePttHotkeyPortalPermissionDenied;

  /// No description provided for @noticeConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost.'**
  String get noticeConnectionLost;

  /// No description provided for @noticeKicked.
  ///
  /// In en, this message translates to:
  /// **'You were removed from the server.'**
  String get noticeKicked;

  /// No description provided for @noticeConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server.'**
  String get noticeConnectFailed;

  /// No description provided for @noticeConnectTimeout.
  ///
  /// In en, this message translates to:
  /// **'The connection timed out.'**
  String get noticeConnectTimeout;

  /// No description provided for @noticeConnectDenied.
  ///
  /// In en, this message translates to:
  /// **'The server refused the connection.'**
  String get noticeConnectDenied;

  /// No description provided for @noticeReconnectExhausted.
  ///
  /// In en, this message translates to:
  /// **'Reconnect attempts exhausted.'**
  String get noticeReconnectExhausted;

  /// No description provided for @noticeIdentityReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the identity.'**
  String get noticeIdentityReadFailed;

  /// No description provided for @noticeIdentityUpgradeFailed.
  ///
  /// In en, this message translates to:
  /// **'Identity upgrade failed.'**
  String get noticeIdentityUpgradeFailed;

  /// No description provided for @noticeIdentityThreadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the identity upgrade.'**
  String get noticeIdentityThreadFailed;

  /// No description provided for @noticeHistoryWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save message history.'**
  String get noticeHistoryWriteFailed;

  /// No description provided for @noticeHistoryCompactFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not compact message history.'**
  String get noticeHistoryCompactFailed;

  /// No description provided for @noticeSettingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load settings.'**
  String get noticeSettingsLoadFailed;

  /// No description provided for @noticeActorStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The session engine failed to start.'**
  String get noticeActorStartFailed;

  /// No description provided for @noticeUnknown.
  ///
  /// In en, this message translates to:
  /// **'The operation failed.'**
  String get noticeUnknown;

  /// No description provided for @errorInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'The server address is invalid.'**
  String get errorInvalidAddress;

  /// No description provided for @errorBlockedAddress.
  ///
  /// In en, this message translates to:
  /// **'This address is blocked.'**
  String get errorBlockedAddress;

  /// No description provided for @errorConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server.'**
  String get errorConnectionFailed;

  /// No description provided for @errorInternal.
  ///
  /// In en, this message translates to:
  /// **'An internal error occurred.'**
  String get errorInternal;

  /// No description provided for @fileSizeBytes.
  ///
  /// In en, this message translates to:
  /// **'{count} bytes'**
  String fileSizeBytes(int count);

  /// No description provided for @fileConnectionChanged.
  ///
  /// In en, this message translates to:
  /// **'Connection changed. Start the download again.'**
  String get fileConnectionChanged;

  /// No description provided for @fileCleanupFailed.
  ///
  /// In en, this message translates to:
  /// **'Temporary download files could not be removed'**
  String get fileCleanupFailed;

  /// No description provided for @kickChannel.
  ///
  /// In en, this message translates to:
  /// **'Kick from channel'**
  String get kickChannel;

  /// No description provided for @kickServer.
  ///
  /// In en, this message translates to:
  /// **'Kick from server'**
  String get kickServer;

  /// No description provided for @kickChannelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {nickname} from their current channel? They will return to the server’s default channel.'**
  String kickChannelConfirm(String nickname);

  /// No description provided for @kickServerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Kick {nickname} from the server? This does not ban them.'**
  String kickServerConfirm(String nickname);

  /// No description provided for @kickReason.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get kickReason;

  /// No description provided for @kickConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm kick'**
  String get kickConfirm;

  /// No description provided for @kickSent.
  ///
  /// In en, this message translates to:
  /// **'Kicked {nickname}'**
  String kickSent(String nickname);

  /// No description provided for @kickTargetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The member is offline or has changed channel. Select them again.'**
  String get kickTargetUnavailable;

  /// No description provided for @kickConnectionChanged.
  ///
  /// In en, this message translates to:
  /// **'The connection changed. Close this dialog and try again.'**
  String get kickConnectionChanged;

  /// No description provided for @channelDetails.
  ///
  /// In en, this message translates to:
  /// **'Channel Details'**
  String get channelDetails;

  /// No description provided for @channelDescription.
  ///
  /// In en, this message translates to:
  /// **'Channel Description'**
  String get channelDescription;

  /// No description provided for @channelDescriptionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No description for this channel'**
  String get channelDescriptionEmpty;

  /// No description provided for @channelDescriptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load channel description'**
  String get channelDescriptionFailed;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Yet another teamspeak client, multi-platform and open-source.'**
  String get aboutSubtitle;

  /// No description provided for @aboutSourceAndFeedback.
  ///
  /// In en, this message translates to:
  /// **'Project & Source'**
  String get aboutSourceAndFeedback;

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Project Website'**
  String get aboutWebsite;

  /// No description provided for @aboutWebsiteAction.
  ///
  /// In en, this message translates to:
  /// **'Visit'**
  String get aboutWebsiteAction;

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get aboutSourceCode;

  /// No description provided for @aboutIssueTracker.
  ///
  /// In en, this message translates to:
  /// **'Issue Tracker'**
  String get aboutIssueTracker;

  /// No description provided for @updateAvailableBadge.
  ///
  /// In en, this message translates to:
  /// **'New version {version} available'**
  String updateAvailableBadge(String version);

  /// No description provided for @updateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updateCheck;

  /// No description provided for @updateDiscoverNewVersion.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get updateDiscoverNewVersion;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are already on the latest version'**
  String get updateUpToDate;

  /// No description provided for @updateGoDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateGoDownload;

  /// No description provided for @updateNoLongerRemind.
  ///
  /// In en, this message translates to:
  /// **'Don\'t remind again'**
  String get updateNoLongerRemind;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates. Try again later.'**
  String get updateCheckFailed;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutCopySuccess.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get aboutCopySuccess;

  /// No description provided for @streamSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing screen'**
  String get streamSharing;

  /// No description provided for @streamWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get streamWatch;

  /// No description provided for @streamWatchScreen.
  ///
  /// In en, this message translates to:
  /// **'Watch screen share'**
  String get streamWatchScreen;

  /// No description provided for @streamWatching.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get streamWatching;

  /// No description provided for @streamStopWatching.
  ///
  /// In en, this message translates to:
  /// **'Close stream'**
  String get streamStopWatching;

  /// No description provided for @streamConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to stream…'**
  String get streamConnecting;

  /// No description provided for @streamMute.
  ///
  /// In en, this message translates to:
  /// **'Mute stream'**
  String get streamMute;

  /// No description provided for @streamUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute stream'**
  String get streamUnmute;

  /// No description provided for @streamExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand stream'**
  String get streamExpand;

  /// No description provided for @streamCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse stream'**
  String get streamCollapse;

  /// No description provided for @streamFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Enter fullscreen'**
  String get streamFullscreen;

  /// No description provided for @streamExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get streamExitFullscreen;

  /// No description provided for @streamEndedStopped.
  ///
  /// In en, this message translates to:
  /// **'Screen share has ended'**
  String get streamEndedStopped;

  /// No description provided for @streamEndedRejected.
  ///
  /// In en, this message translates to:
  /// **'Watch request was declined'**
  String get streamEndedRejected;

  /// No description provided for @streamEndedRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from screen share'**
  String get streamEndedRemoved;

  /// No description provided for @streamNegotiationFailed.
  ///
  /// In en, this message translates to:
  /// **'Screen share connection failed. Try again.'**
  String get streamNegotiationFailed;

  /// No description provided for @streamStartShare.
  ///
  /// In en, this message translates to:
  /// **'Share screen'**
  String get streamStartShare;

  /// No description provided for @streamStopShare.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get streamStopShare;

  /// No description provided for @streamPublishing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get streamPublishing;

  /// No description provided for @streamViewerCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 viewers} =1{1 viewer} other{{count} viewers}}'**
  String streamViewerCount(int count);

  /// No description provided for @streamPreviewShow.
  ///
  /// In en, this message translates to:
  /// **'Show local preview'**
  String get streamPreviewShow;

  /// No description provided for @streamPreviewHide.
  ///
  /// In en, this message translates to:
  /// **'Hide local preview'**
  String get streamPreviewHide;

  /// No description provided for @streamPublishFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start screen share. Check screen recording permissions and try again.'**
  String get streamPublishFailed;

  /// No description provided for @streamPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Share your screen'**
  String get streamPickerTitle;

  /// No description provided for @streamPickerScreens.
  ///
  /// In en, this message translates to:
  /// **'Screens'**
  String get streamPickerScreens;

  /// No description provided for @streamPickerWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get streamPickerWindows;

  /// No description provided for @streamPickerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh sources'**
  String get streamPickerRefresh;

  /// No description provided for @streamPickerLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load screens and windows. Check screen recording permissions and try again.'**
  String get streamPickerLoadFailed;

  /// No description provided for @streamPickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No shareable screens or windows found'**
  String get streamPickerEmpty;

  /// No description provided for @streamPickerResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get streamPickerResolution;

  /// No description provided for @streamPickerFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get streamPickerFrameRate;

  /// No description provided for @streamPickerStart.
  ///
  /// In en, this message translates to:
  /// **'Start sharing'**
  String get streamPickerStart;

  /// No description provided for @streamAndroidDefaultSourceName.
  ///
  /// In en, this message translates to:
  /// **'Device screen'**
  String get streamAndroidDefaultSourceName;

  /// No description provided for @settingsScreenShare.
  ///
  /// In en, this message translates to:
  /// **'Screen share'**
  String get settingsScreenShare;

  /// No description provided for @settingsScreenShareCapture.
  ///
  /// In en, this message translates to:
  /// **'Default capture quality'**
  String get settingsScreenShareCapture;

  /// No description provided for @settingsScreenShareResolution.
  ///
  /// In en, this message translates to:
  /// **'Default resolution'**
  String get settingsScreenShareResolution;

  /// No description provided for @settingsScreenShareResolution720p.
  ///
  /// In en, this message translates to:
  /// **'720p'**
  String get settingsScreenShareResolution720p;

  /// No description provided for @settingsScreenShareResolution1080p.
  ///
  /// In en, this message translates to:
  /// **'1080p'**
  String get settingsScreenShareResolution1080p;

  /// No description provided for @settingsScreenShareFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Default frame rate'**
  String get settingsScreenShareFrameRate;

  /// No description provided for @settingsScreenShareFrameRate30.
  ///
  /// In en, this message translates to:
  /// **'30 FPS'**
  String get settingsScreenShareFrameRate30;

  /// No description provided for @settingsScreenShareFrameRate60.
  ///
  /// In en, this message translates to:
  /// **'60 FPS'**
  String get settingsScreenShareFrameRate60;

  /// No description provided for @settingsScreenShareEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding & network'**
  String get settingsScreenShareEncoding;

  /// No description provided for @settingsScreenShareCodec.
  ///
  /// In en, this message translates to:
  /// **'Video codec & hardware acceleration'**
  String get settingsScreenShareCodec;

  /// No description provided for @settingsScreenShareCodecVp8.
  ///
  /// In en, this message translates to:
  /// **'VP8 first'**
  String get settingsScreenShareCodecVp8;

  /// No description provided for @settingsScreenShareCodecH264.
  ///
  /// In en, this message translates to:
  /// **'H.264 first'**
  String get settingsScreenShareCodecH264;

  /// No description provided for @settingsScreenShareDegradation.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth degradation preference'**
  String get settingsScreenShareDegradation;

  /// No description provided for @settingsScreenShareDegradationResolution.
  ///
  /// In en, this message translates to:
  /// **'Maintain resolution'**
  String get settingsScreenShareDegradationResolution;

  /// No description provided for @settingsScreenShareDegradationFramerate.
  ///
  /// In en, this message translates to:
  /// **'Maintain frame rate'**
  String get settingsScreenShareDegradationFramerate;

  /// No description provided for @clientTypeBot.
  ///
  /// In en, this message translates to:
  /// **'Bot'**
  String get clientTypeBot;

  /// No description provided for @clientTypeFlSpeak.
  ///
  /// In en, this message translates to:
  /// **'FlSpeak client'**
  String get clientTypeFlSpeak;

  /// No description provided for @memberClientSoftware.
  ///
  /// In en, this message translates to:
  /// **'Client software'**
  String get memberClientSoftware;

  /// No description provided for @settingsLiquidGlass.
  ///
  /// In en, this message translates to:
  /// **'Liquid Glass'**
  String get settingsLiquidGlass;

  /// No description provided for @settingsLiquidGlassNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get settingsLiquidGlassNone;

  /// No description provided for @settingsLiquidGlassStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get settingsLiquidGlassStandard;

  /// No description provided for @settingsLiquidGlassUltra.
  ///
  /// In en, this message translates to:
  /// **'Ultra'**
  String get settingsLiquidGlassUltra;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get settingsThemeMode;

  /// No description provided for @settingsPureBlackMode.
  ///
  /// In en, this message translates to:
  /// **'Pure black mode'**
  String get settingsPureBlackMode;

  /// No description provided for @settingsPureBlackStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get settingsPureBlackStandard;

  /// No description provided for @settingsPureBlackOn.
  ///
  /// In en, this message translates to:
  /// **'Pure black'**
  String get settingsPureBlackOn;

  /// No description provided for @settingsThemeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme color'**
  String get settingsThemeColor;

  /// No description provided for @settingsColorStyle.
  ///
  /// In en, this message translates to:
  /// **'Color style'**
  String get settingsColorStyle;

  /// No description provided for @settingsColorStyleVivid.
  ///
  /// In en, this message translates to:
  /// **'Vivid'**
  String get settingsColorStyleVivid;

  /// No description provided for @settingsColorStyleTinted.
  ///
  /// In en, this message translates to:
  /// **'Tinted'**
  String get settingsColorStyleTinted;

  /// No description provided for @settingsColorStyleSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get settingsColorStyleSoft;

  /// No description provided for @settingsColorStyleMonochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get settingsColorStyleMonochrome;

  /// No description provided for @settingsAddColor.
  ///
  /// In en, this message translates to:
  /// **'Add color'**
  String get settingsAddColor;

  /// No description provided for @settingsCustomColor.
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get settingsCustomColor;

  /// No description provided for @settingsColorEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get settingsColorEdit;

  /// No description provided for @settingsColorDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsColorDelete;

  /// No description provided for @settingsColorGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get settingsColorGrid;

  /// No description provided for @settingsColorSpectrum.
  ///
  /// In en, this message translates to:
  /// **'Spectrum'**
  String get settingsColorSpectrum;

  /// No description provided for @settingsColorSliders.
  ///
  /// In en, this message translates to:
  /// **'Sliders'**
  String get settingsColorSliders;

  /// No description provided for @settingsColorHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get settingsColorHue;

  /// No description provided for @settingsColorSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get settingsColorSaturation;

  /// No description provided for @settingsColorBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get settingsColorBrightness;

  /// No description provided for @settingsColorHex.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get settingsColorHex;

  /// No description provided for @settingsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsReset;

  /// No description provided for @settingsResetThemeColorsTip.
  ///
  /// In en, this message translates to:
  /// **'Reset theme colors to defaults?'**
  String get settingsResetThemeColorsTip;

  /// No description provided for @settingsDeleteColorTip.
  ///
  /// In en, this message translates to:
  /// **'Delete color {color}?'**
  String settingsDeleteColorTip(String color);

  /// No description provided for @settingsBottomBar.
  ///
  /// In en, this message translates to:
  /// **'Bottom bar'**
  String get settingsBottomBar;

  /// No description provided for @settingsBottomBarFloating.
  ///
  /// In en, this message translates to:
  /// **'Floating'**
  String get settingsBottomBarFloating;

  /// No description provided for @settingsBottomBarDocked.
  ///
  /// In en, this message translates to:
  /// **'Docked'**
  String get settingsBottomBarDocked;

  /// No description provided for @settingsFontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font family'**
  String get settingsFontFamily;

  /// No description provided for @settingsFontDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsFontDefault;

  /// No description provided for @settingsInstalledFonts.
  ///
  /// In en, this message translates to:
  /// **'Installed fonts'**
  String get settingsInstalledFonts;

  /// No description provided for @settingsFontSearch.
  ///
  /// In en, this message translates to:
  /// **'Search fonts'**
  String get settingsFontSearch;

  /// No description provided for @settingsFontNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching fonts'**
  String get settingsFontNoResults;

  /// No description provided for @settingsTextScale.
  ///
  /// In en, this message translates to:
  /// **'Text scaling'**
  String get settingsTextScale;

  /// No description provided for @settingsTextScaleSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsTextScaleSystem;

  /// No description provided for @settingsTextScaleCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsTextScaleCustom;

  /// No description provided for @settingsTextScalePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview text at this size'**
  String get settingsTextScalePreview;

  /// No description provided for @navWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get navWorkspace;

  /// No description provided for @pressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackAgainToExit;

  /// No description provided for @voiceHoldToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk'**
  String get voiceHoldToTalk;

  /// No description provided for @voiceTalking.
  ///
  /// In en, this message translates to:
  /// **'Talking…'**
  String get voiceTalking;

  /// No description provided for @chatSwitchToText.
  ///
  /// In en, this message translates to:
  /// **'Switch to text input'**
  String get chatSwitchToText;

  /// No description provided for @chatSwitchToVoice.
  ///
  /// In en, this message translates to:
  /// **'Switch to voice controls'**
  String get chatSwitchToVoice;

  /// No description provided for @sessionNotificationChannelName.
  ///
  /// In en, this message translates to:
  /// **'Voice session'**
  String get sessionNotificationChannelName;

  /// No description provided for @sessionNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'{server} · {channel}'**
  String sessionNotificationTitle(String server, String channel);

  /// No description provided for @sessionNotificationStatusInVoice.
  ///
  /// In en, this message translates to:
  /// **'In voice'**
  String get sessionNotificationStatusInVoice;

  /// No description provided for @sessionNotificationStatusMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get sessionNotificationStatusMuted;

  /// No description provided for @sessionNotificationStatusDeafened.
  ///
  /// In en, this message translates to:
  /// **'Deafened'**
  String get sessionNotificationStatusDeafened;

  /// No description provided for @sessionNotificationStatusSharingScreen.
  ///
  /// In en, this message translates to:
  /// **'Sharing screen'**
  String get sessionNotificationStatusSharingScreen;

  /// No description provided for @sessionNotificationStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get sessionNotificationStatusReconnecting;

  /// No description provided for @sessionNotificationStatusCombined.
  ///
  /// In en, this message translates to:
  /// **'{primary} · {secondary}'**
  String sessionNotificationStatusCombined(String primary, String secondary);

  /// No description provided for @sessionNotificationDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get sessionNotificationDisconnect;
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
