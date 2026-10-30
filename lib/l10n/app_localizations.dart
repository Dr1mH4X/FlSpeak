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

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

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

  /// No description provided for @settingsMotion.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get settingsMotion;

  /// No description provided for @settingsMotionSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsMotionSystem;

  /// No description provided for @settingsMotionOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsMotionOn;

  /// No description provided for @settingsMotionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsMotionOff;

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
  /// **'My microphone'**
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

  /// No description provided for @settingsStorePath.
  ///
  /// In en, this message translates to:
  /// **'Storage directory'**
  String get settingsStorePath;

  /// No description provided for @connectTitle.
  ///
  /// In en, this message translates to:
  /// **'Find your people'**
  String get connectTitle;

  /// No description provided for @connectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your communities, one conversation away.'**
  String get connectSubtitle;

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

  /// No description provided for @chatReply.
  ///
  /// In en, this message translates to:
  /// **'Reply privately'**
  String get chatReply;

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

  /// No description provided for @chatClipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No image in the clipboard'**
  String get chatClipboardEmpty;

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

  /// No description provided for @chatChooseImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get chatChooseImage;

  /// No description provided for @chatPasteImage.
  ///
  /// In en, this message translates to:
  /// **'Paste image'**
  String get chatPasteImage;

  /// No description provided for @chatRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get chatRemoveImage;

  /// No description provided for @imageHostTitle.
  ///
  /// In en, this message translates to:
  /// **'Image uploads'**
  String get imageHostTitle;

  /// No description provided for @imageHostRequired.
  ///
  /// In en, this message translates to:
  /// **'Configure a self-hosted image host in Image uploads first'**
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
