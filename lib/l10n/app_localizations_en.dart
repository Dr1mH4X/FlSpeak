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
  String get appTagline => 'Self-hosted TeamSpeak client';

  @override
  String get connectTitle => 'Connect to a server';

  @override
  String get connectAddressLabel => 'Server address';

  @override
  String get connectAddressHint => 'ts.example.com or ts.example.com:9987';

  @override
  String get connectAddressHelp =>
      'A full host name or IP. Port defaults to 9987.';

  @override
  String get connectAction => 'Connect';

  @override
  String get connectKnownServers => 'Registered servers';

  @override
  String get connectNoServers =>
      'No server yet. Type an address above to register the first one.';

  @override
  String get connectNewServerTitle => 'Register a new server';

  @override
  String get connectBack => 'Back to all servers';

  @override
  String get connectNicknameLabel => 'Nickname';

  @override
  String get connectNicknameHelp => 'The name others see. No account needed.';

  @override
  String get serverLabelField => 'Label (optional)';

  @override
  String get serverAdd => 'Add server';

  @override
  String get serverRemove => 'Remove';

  @override
  String get serverDisconnect => 'Disconnect';

  @override
  String get serverInvalidAddress => 'Invalid server address.';

  @override
  String get railServers => 'Servers';

  @override
  String get railCollapse => 'Collapse server bar';

  @override
  String get channelsTitle => 'Channels';

  @override
  String get chatTitle => 'Chat';

  @override
  String get channelsEmpty => 'Not connected.';

  @override
  String get channelExpand => 'Expand';

  @override
  String get channelCollapse => 'Collapse';

  @override
  String get channelJoin => 'Join';

  @override
  String get channelCurrent => 'You are here';

  @override
  String workspaceOnlineCount(int count) {
    return '$count online';
  }

  @override
  String get workspaceNotConnectedTitle => 'Not connected';

  @override
  String get workspaceNotConnectedBody =>
      'Pick a registered server from the bar on the left, or add a new address.';

  @override
  String get workspaceReturn => 'Back to workspace';

  @override
  String get workspaceRefresh => 'Refresh';

  @override
  String get chatScopeChannel => 'This channel';

  @override
  String get chatScopeServer => 'Whole server';

  @override
  String get chatComposerHint => 'Message';

  @override
  String get chatSend => 'Send';

  @override
  String get chatEmptyChannel => 'No messages in this channel yet.';

  @override
  String get chatEmptyServer => 'No server-wide messages yet.';

  @override
  String get chatDirectTag => 'Direct';

  @override
  String get chatNoChannel => 'Join a channel before sending channel messages.';

  @override
  String get sessionConnected => 'Connected';

  @override
  String get voiceRustNote =>
      'Capture, playback and the Opus codec live in Rust (core/audio). Audio frames never cross the FFI boundary; routing them through the session actor is the next milestone.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsLocale => 'Language';

  @override
  String get settingsLocaleSystem => 'System';

  @override
  String get settingsStorePath => 'Core state file';

  @override
  String get settingsValidateTitle => 'Check an address';

  @override
  String get settingsValidateHint => 'host or host:port';

  @override
  String get settingsValidate => 'Check';

  @override
  String get settingsValidateOk => 'Allowed, normalized to';

  @override
  String get settingsAudioTitle => 'Voice';

  @override
  String get complianceTitle => 'Compliance';

  @override
  String get compliancePolicy =>
      'This client only connects to servers you entered yourself and never contacts official TeamSpeak services.';

  @override
  String get commonClose => 'Close';

  @override
  String get commonMore => 'More';
}
