// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '自托管 TeamSpeak';

  @override
  String get appName => 'FlSpeak';

  @override
  String get appTagline => '自托管 TeamSpeak 客户端';

  @override
  String get connectTitle => '连接服务器';

  @override
  String get connectAddressLabel => '服务器地址';

  @override
  String get connectAddressHint => 'ts.example.com 或 ts.example.com:9987';

  @override
  String get connectAddressHelp => '完整域名或 IP，端口默认 9987。';

  @override
  String get connectAction => '连接';

  @override
  String get connectKnownServers => '已登记的服务器';

  @override
  String get connectNoServers => '还没有服务器。在上面填入地址，登记第一台。';

  @override
  String get connectNewServerTitle => '登记新服务器';

  @override
  String get connectBack => '返回服务器列表';

  @override
  String get connectNicknameLabel => '昵称';

  @override
  String get connectNicknameHelp => '其他人看到的名字，不需要注册账号。';

  @override
  String get serverLabelField => '备注名（可选）';

  @override
  String get serverAdd => '添加服务器';

  @override
  String get serverRemove => '删除';

  @override
  String get serverDisconnect => '断开';

  @override
  String get serverInvalidAddress => '服务器地址非法。';

  @override
  String get railServers => '服务器';

  @override
  String get railCollapse => '收起服务器栏';

  @override
  String get channelsTitle => '频道';

  @override
  String get chatTitle => '聊天';

  @override
  String get channelsEmpty => '尚未连接。';

  @override
  String get channelExpand => '展开';

  @override
  String get channelCollapse => '收起';

  @override
  String get channelJoin => '加入';

  @override
  String get channelCurrent => '当前所在';

  @override
  String workspaceOnlineCount(int count) {
    return '$count 人在线';
  }

  @override
  String get workspaceNotConnectedTitle => '未连接服务器';

  @override
  String get workspaceNotConnectedBody => '从左侧服务器栏选择一台已登记的服务器，或添加新地址。';

  @override
  String get workspaceReturn => '返回工作区';

  @override
  String get workspaceRefresh => '刷新';

  @override
  String get chatScopeChannel => '本频道';

  @override
  String get chatScopeServer => '整个服务器';

  @override
  String get chatComposerHint => '输入消息';

  @override
  String get chatSend => '发送';

  @override
  String get chatEmptyChannel => '本频道还没有消息。';

  @override
  String get chatEmptyServer => '服务器上还没有广播消息。';

  @override
  String get chatDirectTag => '私聊';

  @override
  String get chatNoChannel => '先进入一个频道再发送频道消息。';

  @override
  String get sessionConnected => '已连接';

  @override
  String get voiceRustNote =>
      '采集、播放与 Opus 编解码都在 Rust 侧（core/audio）。音频帧不经过 FFI；把它们接进会话 actor 是下一个里程碑。';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsLocale => '语言';

  @override
  String get settingsLocaleSystem => '跟随系统';

  @override
  String get settingsStorePath => '核心状态文件';

  @override
  String get settingsValidateTitle => '校验地址';

  @override
  String get settingsValidateHint => 'host 或 host:port';

  @override
  String get settingsValidate => '校验';

  @override
  String get settingsValidateOk => '允许，归一化为';

  @override
  String get settingsAudioTitle => '语音';

  @override
  String get complianceTitle => '合规';

  @override
  String get compliancePolicy => '本客户端只连接你手动录入的服务器，且不会访问任何 TeamSpeak 官方服务。';

  @override
  String get commonClose => '关闭';

  @override
  String get commonMore => '更多';
}
