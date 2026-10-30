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
  String get homeTitle => 'Home';

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
  String get commonRetry => 'Retry';

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
  String identityUpgraded(int level) {
    return 'Identity upgraded to level $level. Reconnecting…';
  }

  @override
  String get workspaceDropped => 'Disconnected';

  @override
  String get workspaceRetrying => 'Retrying…';

  @override
  String get channelsSection => 'Channels';

  @override
  String get workspaceNoChannels => 'This server has no channels yet.';

  @override
  String get workspaceOpenMenu => 'Open channel menu';

  @override
  String get channelPasswordProtected => 'Channel password required';

  @override
  String get channelJoinMenu => 'Join channel';

  @override
  String get channelPaneResize => 'Resize channel pane';

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
  String get memberSpeaking => 'Speaking';

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
  String get chatScopeDirect => 'Direct';

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
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsMotion => 'Motion';

  @override
  String get settingsMotionSystem => 'System';

  @override
  String get settingsMotionOn => 'On';

  @override
  String get settingsMotionOff => 'Off';

  @override
  String get settingsPttMode => 'Push to talk';

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
  String get settingsVoiceMeter => 'Audio display';

  @override
  String get settingsVoiceMeterMic => 'My microphone';

  @override
  String get settingsVoiceMeterReceived => 'Received audio';

  @override
  String get settingsDeviceDefault => 'System default';

  @override
  String get settingsAudioUnavailable => 'Audio devices unavailable';

  @override
  String get settingsAudioLoading => 'Reading audio devices…';

  @override
  String get settingsStorePath => 'Storage directory';

  @override
  String get connectTitle => 'Find your people';

  @override
  String get connectSubtitle => 'Your communities, one conversation away.';

  @override
  String get serverEmptyBody =>
      'Add a server address to join your people in a channel.';

  @override
  String get serverSearchLabel => 'Search servers';

  @override
  String get serverSearchEmpty => 'No matching servers';

  @override
  String get membersTitle => 'Channel members';

  @override
  String get voiceConnected => 'Voice connected';

  @override
  String get memberListening => 'In this channel';

  @override
  String get appearancePreview => 'Appearance';

  @override
  String get serverIconTitle => 'Choose server icon';

  @override
  String get serverIconChange => 'Change icon';

  @override
  String get serverIconCommunity => 'Community';

  @override
  String get serverIconGaming => 'Gaming';

  @override
  String get serverIconMusic => 'Music';

  @override
  String get serverIconWork => 'Work';

  @override
  String get serverIconTerminal => 'Terminal';

  @override
  String get serverIconFavorite => 'Favorite';

  @override
  String get serverIconPlanet => 'Planet';

  @override
  String get serverIconCoffee => 'Coffee';

  @override
  String get serverIconRocket => 'Rocket';

  @override
  String get serverIconScience => 'Explore';

  @override
  String get channelIconRetry => 'Retry channel icon';

  @override
  String get chatReply => 'Reply privately';

  @override
  String get chatRecipientUnavailable =>
      'Recipient is offline. Choose another recipient.';

  @override
  String get chatChannelUnavailable =>
      'Join this channel before sending a message.';

  @override
  String get chatDirectAction => 'Direct message';

  @override
  String get pokeAction => 'Poke';

  @override
  String get pokeMessage => 'Message';

  @override
  String pokeTitle(String name) {
    return 'Poke $name';
  }

  @override
  String pokeSent(String name) {
    return 'Poked $name';
  }

  @override
  String pokeReceived(String name, String message) {
    return '$name poked you: $message';
  }

  @override
  String memberActions(String name) {
    return 'Actions for $name';
  }

  @override
  String get chatDestinationChanged =>
      'The destination changed. Your draft was kept; confirm the recipient and retry.';

  @override
  String get chatImageTooLarge => 'Images must be no larger than 20 MiB';

  @override
  String get chatClipboardEmpty => 'No image in the clipboard';

  @override
  String get chatImageInputFailed =>
      'Could not read the image. Please choose it again.';

  @override
  String get chatAttachImage => 'Attach image';

  @override
  String get chatChooseImage => 'Choose image';

  @override
  String get chatPasteImage => 'Paste image';

  @override
  String get chatRemoveImage => 'Remove image';

  @override
  String get imageHostTitle => 'Image uploads';

  @override
  String get imageHostRequired =>
      'Configure a self-hosted image host in Image uploads first';

  @override
  String get imageHostStorageFailed =>
      'Could not access secure storage for image uploads';

  @override
  String get imageHostUploadBase => 'HTTP PUT upload base URL';

  @override
  String get imageHostPublicBase => 'Public image base URL';

  @override
  String get imageHostToken => 'Bearer token (optional)';

  @override
  String get imageHostRemove => 'Clear configuration';

  @override
  String get imageHostSave => 'Save';

  @override
  String get imageHostUploadHint => 'https://upload.example.com/images/';

  @override
  String get imageHostPublicHint => 'https://images.example.com/';

  @override
  String get channelPasswordTitle => 'Channel password required';

  @override
  String get channelPasswordLabel => 'Channel password';

  @override
  String get channelPasswordWrong => 'Incorrect password. Try again.';

  @override
  String get memberPermissions => 'Manage permissions';

  @override
  String get permissionsUnavailable => 'Permissions are unavailable';

  @override
  String get serverGroups => 'Server groups';

  @override
  String get channelGroups => 'Channel groups';

  @override
  String get groupCurrent => 'Current';

  @override
  String get groupAssign => 'Assign';

  @override
  String get chatTabFiles => 'Files';

  @override
  String get fileParent => 'Parent folder';

  @override
  String get fileDownload => 'Download file';

  @override
  String get fileUnlock => 'Open';

  @override
  String get fileListEmpty => 'This channel has no files';

  @override
  String get fileDownloadFailed =>
      'Could not download or save the file. Try again.';

  @override
  String get fileDownloadSaved => 'File saved';

  @override
  String fileSizeBytes(int count) {
    return '$count bytes';
  }

  @override
  String get fileConnectionChanged =>
      'Connection changed. Start the download again.';

  @override
  String get fileCleanupFailed =>
      'Temporary download files could not be removed';

  @override
  String get kickChannel => 'Kick from channel';

  @override
  String get kickServer => 'Kick from server';

  @override
  String kickChannelConfirm(String nickname) {
    return 'Remove $nickname from their current channel? They will return to the server’s default channel.';
  }

  @override
  String kickServerConfirm(String nickname) {
    return 'Kick $nickname from the server? This does not ban them.';
  }

  @override
  String get kickReason => 'Reason (optional)';

  @override
  String get kickConfirm => 'Confirm kick';

  @override
  String kickSent(String nickname) {
    return 'Kicked $nickname';
  }

  @override
  String get kickTargetUnavailable =>
      'The member is offline or has changed channel. Select them again.';

  @override
  String get kickConnectionChanged =>
      'The connection changed. Close this dialog and try again.';

  @override
  String get channelDetails => 'Channel Details';

  @override
  String get channelDescription => 'Channel Description';

  @override
  String get channelDescriptionEmpty => 'No description for this channel';

  @override
  String get channelDescriptionFailed => 'Failed to load channel description';

  @override
  String get aboutSubtitle =>
      'Yet another teamspeak client, multi-platform and open-source.';

  @override
  String get aboutSourceAndFeedback => 'Project & Source';

  @override
  String get aboutSourceCode => 'Source Code';

  @override
  String get aboutIssueTracker => 'Issue Tracker';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutCopySuccess => 'Link copied to clipboard';
}
