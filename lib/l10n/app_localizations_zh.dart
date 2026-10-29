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
  String get homeTitle => '主页';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDone => '完成';

  @override
  String get commonCopy => '复制';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonRetry => '重试';

  @override
  String get connectAddressLabel => '服务器地址';

  @override
  String get connectAddressHint => 'ts.example.com 或 ts.example.com:9987';

  @override
  String get connectNicknameLabel => '昵称';

  @override
  String get serverLabelField => '备注名（可选）';

  @override
  String get serverLabelHint => '例如：旅行摄影社';

  @override
  String get serverAdd => '添加服务器';

  @override
  String get serverRemove => '移除';

  @override
  String get serverRemoveFromList => '从列表移除';

  @override
  String get serverRemoveTitle => '移除服务器？';

  @override
  String serverRemoveBody(String label) {
    return '“$label”会从列表移除；本机聊天记录仍会保留。';
  }

  @override
  String get serverAddAndConnect => '添加并连接';

  @override
  String get serverAddAndConnecting => '正在添加…';

  @override
  String get serverAddressRequired => '请输入服务器地址。';

  @override
  String get serverInvalidAddress => '服务器地址非法。';

  @override
  String get serverDisconnect => '断开';

  @override
  String get serverEmptyTitle => '还没有服务器';

  @override
  String get serverEmptyAction => '添加第一台服务器';

  @override
  String get serversTitle => '服务器';

  @override
  String serversUsedBy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '用于 $count 台服务器',
    );
    return '$_temp0';
  }

  @override
  String get sessionConnected => '已连接';

  @override
  String get sessionConnecting => '正在连接…';

  @override
  String get sessionDisconnected => '未连接';

  @override
  String sessionConnectedTo(String name) {
    return '已连接到 $name';
  }

  @override
  String sessionConnectingTo(String name) {
    return '正在连接 $name…';
  }

  @override
  String get sessionLastConnectedNever => '还没连接过';

  @override
  String get sessionLastConnectedJustNow => '刚刚';

  @override
  String sessionLastConnectedMinutes(int count) {
    return '$count 分钟前';
  }

  @override
  String sessionLastConnectedHours(int count) {
    return '$count 小时前';
  }

  @override
  String get sessionLastConnectedYesterday => '昨天';

  @override
  String sessionLastConnectedDays(int count) {
    return '$count 天前';
  }

  @override
  String get workspaceReturn => '返回工作区';

  @override
  String get identityCurrent => '当前身份';

  @override
  String get identityManage => '管理身份';

  @override
  String get identityTitle => '身份';

  @override
  String get identityRename => '修改昵称';

  @override
  String get identitySave => '保存';

  @override
  String get identityNicknameEmpty => '昵称不能为空。';

  @override
  String get identityCancel => '取消';

  @override
  String identityUpgrading(int target) {
    return '正在把身份等级提升到 $target…';
  }

  @override
  String identityUpgraded(int level) {
    return '身份等级已提升到 $level，正在重连…';
  }

  @override
  String get workspaceDropped => '连接丢失';

  @override
  String get workspaceRetrying => '正在重试…';

  @override
  String get channelsSection => '频道';

  @override
  String get workspaceNoChannels => '服务器还没有频道。';

  @override
  String get workspaceOpenMenu => '打开频道菜单';

  @override
  String get channelPasswordProtected => '需要频道密码';

  @override
  String get channelJoinMenu => '加入频道';

  @override
  String get channelPaneResize => '调整频道栏宽度';

  @override
  String get voiceMute => '静音';

  @override
  String get voiceUnmute => '取消静音';

  @override
  String get voiceDeafen => '关闭声音';

  @override
  String get voiceUndeafen => '取消闭麦';

  @override
  String get memberMicMuted => '麦克风已静音';

  @override
  String get memberSpeakerMuted => '扬声器已静音';

  @override
  String get memberAway => '离开';

  @override
  String memberAwayWith(Object message) {
    return '离开：$message';
  }

  @override
  String get memberSpeaking => '正在说话';

  @override
  String get voiceAway => '标记离开';

  @override
  String get voiceUnaway => '取消离开';

  @override
  String get voiceMicUnavailable => '麦克风不可用';

  @override
  String get voiceSpeakerUnavailable => '扬声器不可用';

  @override
  String voiceReconnectingAttempt(int attempt) {
    return '正在重连（第 $attempt 次）…';
  }

  @override
  String get chatTabMessages => '消息';

  @override
  String get chatTabMedia => '媒体';

  @override
  String chatWelcomeTitle(String channel) {
    return '欢迎来到 $channel';
  }

  @override
  String get chatWelcomeBody => '这是频道的起点，分享文字、图片和视频吧。';

  @override
  String chatComposerHintTo(String target) {
    return '发送到 $target';
  }

  @override
  String get chatSend => '发送';

  @override
  String get chatScopeTitle => '发送范围';

  @override
  String get chatScopeChannel => '本频道';

  @override
  String get chatScopeServer => '整个服务器';

  @override
  String get chatUnsupportedImage => '不支持的图片格式';

  @override
  String get chatImageLoading => '正在加载图片…';

  @override
  String get chatImageLoadFailed => '图片加载失败';

  @override
  String get chatTs6Attachment => 'TS6 官方附件';

  @override
  String get chatTs6AttachmentPolicy => '当前策略不连接 myTeamSpeak 媒体服务，仅显示文件信息。';

  @override
  String get chatDirectTag => '私聊';

  @override
  String get mediaEmpty => '这个频道还没有图片或视频';

  @override
  String get mediaViewerTitle => '媒体浏览';

  @override
  String get mediaPrevious => '上一个';

  @override
  String get mediaNext => '下一个';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsGeneral => '通用';

  @override
  String get settingsVoice => '语音';

  @override
  String get settingsData => '数据';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsTheme => '外观';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsPttMode => '按住说话';

  @override
  String get settingsPttHotkey => '按住说话快捷键';

  @override
  String get settingsPttHotkeyNone => '未设置';

  @override
  String get settingsPttHotkeyRecordTitle => '录制快捷键';

  @override
  String get settingsPttHotkeyRecordHint => '按下任意键…（Esc 取消）';

  @override
  String get settingsPttHotkeyUnsupported => '该按键不支持，请换一个。';

  @override
  String get settingsPttHotkeyClear => '清除';

  @override
  String get settingsInputDevice => '麦克风';

  @override
  String get settingsOutputDevice => '扬声器';

  @override
  String get settingsVoiceMeter => '音频显示';

  @override
  String get settingsVoiceMeterMic => '自己麦克风';

  @override
  String get settingsVoiceMeterReceived => '接收到的音频';

  @override
  String get settingsDeviceDefault => '系统默认';

  @override
  String get settingsAudioUnavailable => '音频设备不可用';

  @override
  String get settingsAudioLoading => '正在读取音频设备…';

  @override
  String get settingsStorePath => '存储目录';

  @override
  String get connectTitle => '找到你的声音';

  @override
  String get connectSubtitle => '加入熟悉的频道，让对话自然发生。';

  @override
  String get serverEmptyBody => '添加服务器地址，和伙伴在同一个频道相聚。';

  @override
  String get serverSearchLabel => '搜索服务器';

  @override
  String get serverSearchEmpty => '没有匹配的服务器';

  @override
  String get connectIdentityBody => '一个身份，连接你熟悉的每个社区。';

  @override
  String get connectLocalIdentity => '身份保存在本机';

  @override
  String get membersTitle => '频道成员';

  @override
  String get voiceConnected => '语音已连接';

  @override
  String get memberListening => '正在频道中';

  @override
  String get appearancePreview => '外观';

  @override
  String get serverIconTitle => '选择服务器图标';

  @override
  String get serverIconChange => '更换图标';

  @override
  String get serverIconCommunity => '社区';

  @override
  String get serverIconGaming => '游戏';

  @override
  String get serverIconMusic => '音乐';

  @override
  String get serverIconWork => '工作';

  @override
  String get serverIconTerminal => '终端';

  @override
  String get serverIconFavorite => '喜爱';

  @override
  String get serverIconPlanet => '星球';

  @override
  String get serverIconCoffee => '咖啡';

  @override
  String get serverIconRocket => '火箭';

  @override
  String get serverIconScience => '探索';

  @override
  String get channelIconRetry => '重新加载频道图标';

  @override
  String get chatReply => '回复私聊';

  @override
  String get chatRecipientUnavailable => '私聊对象已离线，请重新选择';

  @override
  String get chatChannelUnavailable => '请先进入此频道再发送消息';

  @override
  String get pokeAction => '戳一下';

  @override
  String get pokeMessage => '消息';

  @override
  String pokeTitle(String name) {
    return '戳一下 $name';
  }

  @override
  String pokeSent(String name) {
    return '已戳了 $name 一下';
  }

  @override
  String pokeReceived(String name, String message) {
    return '$name 戳了你一下：$message';
  }

  @override
  String memberActions(String name) {
    return '$name 的操作';
  }

  @override
  String get chatDestinationChanged => '发送目标已改变，草稿已保留，请确认后重试';

  @override
  String get chatImageTooLarge => '图片不能超过 20 MiB';

  @override
  String get chatClipboardEmpty => '剪贴板中没有图片';

  @override
  String get chatImageInputFailed => '无法读取图片，请重新选择';

  @override
  String get chatAttachImage => '添加图片';

  @override
  String get chatChooseImage => '选择图片';

  @override
  String get chatPasteImage => '粘贴图片';

  @override
  String get chatRemoveImage => '移除图片';

  @override
  String get imageHostTitle => '图片上传';

  @override
  String get imageHostRequired => '请先在图片上传设置中配置自托管图床';

  @override
  String get imageHostStorageFailed => '无法访问图片上传的安全存储';

  @override
  String get imageHostUploadBase => 'HTTP PUT 上传地址';

  @override
  String get imageHostPublicBase => '图片访问地址';

  @override
  String get imageHostToken => '访问令牌（可选）';

  @override
  String get imageHostRemove => '清除配置';

  @override
  String get imageHostSave => '保存';

  @override
  String get imageHostUploadHint => 'https://upload.example.com/images/';

  @override
  String get imageHostPublicHint => 'https://images.example.com/';

  @override
  String get channelPasswordTitle => '频道需要密码';

  @override
  String get channelPasswordLabel => '频道密码';

  @override
  String get channelPasswordWrong => '密码不正确，请重试';

  @override
  String get memberPermissions => '权限管理';

  @override
  String get permissionsUnavailable => '暂时无法读取权限';

  @override
  String get serverGroups => '服务器权限组';

  @override
  String get channelGroups => '频道权限组';

  @override
  String get groupCurrent => '当前';

  @override
  String get groupAssign => '设置';

  @override
  String get chatTabFiles => '文件';

  @override
  String get fileParent => '上级目录';

  @override
  String get fileDownload => '下载文件';

  @override
  String get fileUnlock => '打开';

  @override
  String get fileListEmpty => '此频道暂无文件';

  @override
  String get fileDownloadFailed => '文件下载或保存失败，请重试';

  @override
  String get fileDownloadSaved => '文件已保存';

  @override
  String fileSizeBytes(int count) {
    return '$count 字节';
  }

  @override
  String get fileConnectionChanged => '连接已变化，请重新下载';

  @override
  String get fileCleanupFailed => '临时下载文件未能清理';

  @override
  String get kickChannel => '踢出频道';

  @override
  String get kickServer => '踢出服务器';

  @override
  String kickChannelConfirm(String nickname) {
    return '将 $nickname 移出当前频道？对方将返回服务器默认频道。';
  }

  @override
  String kickServerConfirm(String nickname) {
    return '将 $nickname 踢出服务器？此操作不会封禁对方。';
  }

  @override
  String get kickReason => '原因（可选）';

  @override
  String get kickConfirm => '确认踢出';

  @override
  String kickSent(String nickname) {
    return '已踢出 $nickname';
  }

  @override
  String get kickTargetUnavailable => '成员已离线或更换频道，请重新选择';

  @override
  String get kickConnectionChanged => '连接已变化，请关闭后重新操作';
}
