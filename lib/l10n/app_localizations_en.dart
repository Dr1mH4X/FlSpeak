// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Self-hosted TeamSpeak';

  @override
  String get appName => 'FlSpeak';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDone => 'Done';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied';

  @override
  String get connectTitle => 'Connect to a server';

  @override
  String get connectAddressLabel => 'Server address';

  @override
  String get connectAddressHint => 'ts.example.com or ts.example.com:9987';

  @override
  String get connectNicknameLabel => 'Nickname';

  @override
  String get serverLabelField => 'Label (optional)';

  @override
  String get serverLabelHint => 'For example: Photo club';

  @override
  String get serverAdd => 'Add server';

  @override
  String get serverRemove => 'Remove';

  @override
  String get serverRemoveFromList => 'Remove from list';

  @override
  String get serverRemoveTitle => 'Remove server?';

  @override
  String serverRemoveBody(String label) {
    return '“$label” will be removed from the list; local chat history stays.';
  }

  @override
  String get serverAddAndConnect => 'Add & connect';

  @override
  String get serverAddAndConnecting => 'Adding…';

  @override
  String get serverAddressRequired => 'Enter a server address.';

  @override
  String get serverInvalidAddress => 'Invalid server address.';

  @override
  String get serverDisconnect => 'Disconnect';

  @override
  String get serverEmptyTitle => 'No servers yet';

  @override
  String get serverEmptyAction => 'Add your first server';

  @override
  String get serversTitle => 'Servers';

  @override
  String serversUsedBy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Used by $count servers',
      one: 'Used by 1 server',
    );
    return '$_temp0';
  }

  @override
  String get sessionConnected => 'Connected';

  @override
  String get sessionConnecting => 'Connecting…';

  @override
  String get sessionDisconnected => 'Offline';

  @override
  String sessionConnectedTo(String name) {
    return 'Connected to $name';
  }

  @override
  String sessionConnectingTo(String name) {
    return 'Connecting to $name…';
  }

  @override
  String get sessionLastConnectedNever => 'Never connected';

  @override
  String get sessionLastConnectedJustNow => 'Just now';

  @override
  String sessionLastConnectedMinutes(int count) {
    return '$count min ago';
  }

  @override
  String sessionLastConnectedHours(int count) {
    return '$count h ago';
  }

  @override
  String get sessionLastConnectedYesterday => 'Yesterday';

  @override
  String sessionLastConnectedDays(int count) {
    return '$count days ago';
  }

  @override
  String get workspaceReturn => 'Back to workspace';

  @override
  String get identityCurrent => 'Current identity';

  @override
  String get identityManage => 'Manage identity';

  @override
  String get identityTitle => 'Identity';

  @override
  String get identityRename => 'Rename';

  @override
  String get identitySave => 'Save';

  @override
  String get identityNicknameEmpty => 'Nickname cannot be empty.';

  @override
  String get identityCancel => 'Cancel';

  @override
  String identityUpgrading(int target) {
    return 'Upgrading identity level to $target…';
  }

  @override
  String get channelsEmpty => 'Not connected.';

  @override
  String get channelsSection => 'Channels';

  @override
  String get workspaceNoChannels => 'This server has no channels yet.';

  @override
  String get workspaceOpenMenu => 'Open channel menu';

  @override
  String get workspaceNotConnectedTitle => 'Not connected';

  @override
  String get workspaceNotConnectedBody =>
      'Pick a registered server from the bar on the left, or add a new address.';

  @override
  String get channelPasswordProtected => 'Channel password required';

  @override
  String get channelJoinMenu => 'Join channel';

  @override
  String get channelPaneResize => 'Resize channel pane';

  @override
  String get channelPaneResizeHint => 'Drag to resize, double-click to reset';

  @override
  String get voiceMute => 'Mute';

  @override
  String get voiceUnmute => 'Unmute';

  @override
  String get voiceDeafen => 'Deafen';

  @override
  String get voiceUndeafen => 'Undeafen';

  @override
  String get memberMicMuted => 'Microphone muted';

  @override
  String get memberSpeakerMuted => 'Speaker muted';

  @override
  String get memberAway => 'Away';

  @override
  String memberAwayWith(Object message) {
    return 'Away: $message';
  }

  @override
  String get voiceAway => 'Set away';

  @override
  String get voiceUnaway => 'Unset away';

  @override
  String get voiceMicUnavailable => 'Microphone unavailable';

  @override
  String get voiceSpeakerUnavailable => 'Speaker unavailable';

  @override
  String voiceReconnectingAttempt(int attempt) {
    return 'Reconnecting (attempt $attempt)…';
  }

  @override
  String get chatTabMessages => 'Messages';

  @override
  String get chatTabMedia => 'Media';

  @override
  String chatWelcomeTitle(String channel) {
    return 'Welcome to $channel';
  }

  @override
  String get chatWelcomeBody =>
      'This is the start of the channel. Share text, images and videos.';

  @override
  String chatComposerHintTo(String target) {
    return 'Message $target';
  }

  @override
  String get chatSend => 'Send';

  @override
  String get chatScopeTitle => 'Send to';

  @override
  String get chatScopeChannel => 'This channel';

  @override
  String get chatScopeServer => 'Whole server';

  @override
  String get chatUnsupportedImage => 'Unsupported image format';

  @override
  String get chatImageLoading => 'Loading image…';

  @override
  String get chatImageLoadFailed => 'Image failed to load';

  @override
  String get chatTs6Attachment => 'TS6 official attachment';

  @override
  String get chatTs6AttachmentPolicy =>
      'myTeamSpeak media is not used; showing file metadata only.';

  @override
  String get chatDirectTag => 'Direct';

  @override
  String get mediaEmpty => 'No images or videos in this channel yet';

  @override
  String get mediaViewerTitle => 'Media viewer';

  @override
  String get mediaPrevious => 'Previous';

  @override
  String get mediaNext => 'Next';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsVoice => 'Voice';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get settingsThemeDesc => 'System, light or dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsPttMode => 'Push to talk';

  @override
  String get settingsPttModeDesc => 'When off, voice activation is used';

  @override
  String get settingsPttHotkey => 'Push-to-talk hotkey';

  @override
  String get settingsPttHotkeyNone => 'Not set';

  @override
  String get settingsPttHotkeyRecordTitle => 'Record hotkey';

  @override
  String get settingsPttHotkeyRecordHint => 'Press any key… (Esc to cancel)';

  @override
  String get settingsPttHotkeyUnsupported =>
      'This key is not supported. Try another one.';

  @override
  String get settingsPttHotkeyClear => 'Clear';

  @override
  String get settingsInputDevice => 'Microphone';

  @override
  String get settingsOutputDevice => 'Speaker';

  @override
  String get settingsDeviceDefault => 'System default';

  @override
  String get settingsAudioUnavailable => 'Audio devices unavailable';

  @override
  String get settingsAudioLoading => 'Reading audio devices…';

  @override
  String get settingsStorePath => 'Storage directory';

  @override
  String get settingsStorePathDesc => 'Where profiles and preferences live';

  @override
  String get settingsAboutTagline => 'Self-hosted TeamSpeak client';
}
