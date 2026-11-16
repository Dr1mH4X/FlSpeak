import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        Checkbox,
        Chip,
        Divider,
        FilledButton,
        IconButton,
        LinearProgressIndicator,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../core/channel_display.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/stream_publisher.dart';
import '../../core/stream_viewer.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/monogram.dart';
import '../../widgets/prism.dart';
import '../../widgets/scaffold/scaffold.dart' as app_scaffold;
import '../../widgets/window_header.dart';
import '../settings/widgets/image_host_dialog.dart';
import 'widgets/chat_pane.dart';
import 'widgets/channel_files_pane.dart';
import 'widgets/channel_details_pane.dart';
import 'widgets/member_details_pane.dart';
import 'widgets/media_grid.dart';
import 'widgets/media_viewer.dart';
import 'widgets/members_pane.dart';
import 'widgets/member_avatar.dart';
import 'widgets/stream_viewer_pane.dart';
import 'workspace_state.dart';

/// 主区域：频道标题 + 消息 / 媒体两个视图，以及掉线后的空状态。
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

enum _MainTab { chat, media, files, details }

class _WorkspacePageState extends ConsumerState<WorkspacePage>
    with SingleTickerProviderStateMixin {
  // M3 primary tabs：页签状态由 TabController 持有，指示器动画随组件自带。
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  )..addListener(_handleTabChanged);
  _MainTab _tab = _MainTab.chat;

  void _handleTabChanged() {
    // 目标内容与指示器同时切换，不等待指示器动画结束。
    final tab = _MainTab.values[_tabController.index];
    if (tab != _tab) {
      if (tab == _MainTab.chat) {
        final selectedMember = ref.read(selectedMemberProvider);
        if (selectedMember != null &&
            selectedMember.serverId ==
                ref.read(sessionViewProvider).activeServerId) {
          ref
              .read(sessionViewProvider.notifier)
              .selectDirectRecipient(
                selectedMember.uid,
                clientId: selectedMember.clientId,
              );
        }
      }
      setState(() => _tab = tab);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final channelId = ref.watch(activeChannelIdProvider);
    final detailsTarget = ref.watch(activeDetailsTargetProvider);
    final isMemberDetails = detailsTarget is MemberDetailsTarget;
    final (
      :connected,
      :connecting,
      :reconnecting,
      :reconnectAttempt,
      :activeServerId,
      :connectionEpoch,
      :identityUpgradeTarget,
      :channel,
    ) = ref.watch(
      sessionViewProvider.select(
        (view) => (
          connected: view.connected,
          connecting: view.connecting,
          reconnecting: view.reconnecting,
          reconnectAttempt: view.reconnectAttempt,
          activeServerId: view.activeServerId,
          connectionEpoch: view.connectionEpoch,
          identityUpgradeTarget: view.identityUpgradeTarget,
          channel: channelId == null ? null : view.channelById(channelId),
        ),
      ),
    );

    ref.listen(
      sessionViewProvider.select(
        (view) =>
            (view.chatScope, view.directRecipientUid, view.directRecipientId),
      ),
      (previous, next) {
        if (next.$1 != ChatScope.direct) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tabController.index != 0) _tabController.index = 0;
        });
      },
    );

    ref.listen(selectedMemberProvider, (previous, next) {
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tabController.index != 3) {
            _tabController.index = 3;
          }
        });
      }
    });

    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    final mainPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (identityUpgradeTarget != null)
          _IdentityBanner(
            target: identityUpgradeTarget,
            onCancel: ref
                .read(sessionViewProvider.notifier)
                .cancelIdentityUpgrade,
          ),
        const _VoiceAlerts(),
        const _WorkspaceStreamViewer(),
        Expanded(
          // 视图替换走 crossfade（M3 effects default）：同一容器内换内容
          // 不做位移，避免整块内容跳来跳去。
          child: RepaintBoundary(
            child: WidthBuilder(
              builder: (context, width) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: RepaintBoundary(
                      child: AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : Motion.effectsDefault,
                        switchInCurve: Motion.effectsDefaultCurve,
                        switchOutCurve: Motion.effectsDefaultCurve.flipped,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.center,
                          children: [
                            for (final child in previous)
                              ExcludeFocus(
                                child: IgnorePointer(
                                  child: ExcludeSemantics(child: child),
                                ),
                              ),
                            ?current,
                          ],
                        ),
                        child: KeyedSubtree(
                          key: ValueKey((
                            _tab,
                            activeServerId,
                            connectionEpoch,
                            channelId,
                            connected,
                            connecting || reconnecting,
                            _tab == _MainTab.details ? detailsTarget : null,
                          )),
                          child: _buildBody(
                            context,
                            l10n,
                            connected: connected,
                            connecting: connecting,
                            reconnecting: reconnecting,
                            reconnectAttempt: reconnectAttempt,
                            connectionEpoch: connectionEpoch,
                            channel: channel,
                            detailsTarget: detailsTarget,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (width >= 900 && channel != null && connected)
                    MembersPane(channelId: channel.id),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (compact) {
      return app_scaffold.Scaffold(
        backgroundColor: context.pageColor,
        title: channel != null ? channelDisplayName(channel) : l10n.appName,
        backAction: () => _navigateBack(context),
        actions: [
          IconButton(
            onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
            icon: Icon(
              Icons.menu_rounded,
              semanticLabel: l10n.workspaceOpenMenu,
            ),
          ),
        ],
        body: Builder(
          builder: (context) => Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: EdgeInsets.only(top: context.appBarInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (channel != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: dividerColorOf(context)),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _ViewTabs(
                              tabs: _tabSpecs(
                                l10n,
                                isMemberDetails: isMemberDetails,
                              ),
                              controller: _tabController,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: SafeArea(top: false, child: mainPane)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelHeader(
          channel: channel,
          tabController: _tabController,
          isMemberDetails: isMemberDetails,
        ),
        Expanded(child: SafeArea(top: false, left: false, child: mainPane)),
      ],
    );
  }

  void _navigateBack(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (router != null) {
      router.go(AppRoutes.connect);
    }
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n, {
    required bool connected,
    required bool connecting,
    required bool reconnecting,
    required int? reconnectAttempt,
    required int connectionEpoch,
    required ChannelView? channel,
    required DetailsTarget? detailsTarget,
  }) {
    if (connecting || reconnecting) {
      final scheme = context.scheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ActivityIndicator(size: 36),
            const SizedBox(height: 16),
            Text(
              reconnecting
                  ? l10n.voiceReconnectingAttempt(reconnectAttempt ?? 1)
                  : l10n.sessionConnecting,
              style: context.texts.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (channel == null) {
      if (_tab == _MainTab.details && detailsTarget is MemberDetailsTarget) {
        return MemberDetailsPane(
          key: ValueKey((
            detailsTarget.client.id,
            detailsTarget.client.uid,
            detailsTarget.isOffline,
            connectionEpoch,
          )),
          client: detailsTarget.client,
          isOffline: detailsTarget.isOffline,
        );
      }
      return EmptyState(
        icon: connected ? Icons.forum_rounded : Icons.link_off_rounded,
        body: connected ? l10n.workspaceNoChannels : l10n.workspaceDropped,
      );
    }

    switch (_tab) {
      case _MainTab.details:
        if (detailsTarget is MemberDetailsTarget) {
          return MemberDetailsPane(
            key: ValueKey((
              detailsTarget.client.id,
              detailsTarget.client.uid,
              detailsTarget.isOffline,
              connectionEpoch,
            )),
            client: detailsTarget.client,
            isOffline: detailsTarget.isOffline,
          );
        }
        return ChannelDetailsPane(
          key: ValueKey((channel.id, channel.iconId, channel.name)),
          channel: channel,
        );
      case _MainTab.files:
        return ChannelFilesPane(
          key: ValueKey((connectionEpoch, channel.id)),
          channelId: channel.id,
        );
      case _MainTab.media:
        return _ChannelMediaBody(channelId: channel.id);
      case _MainTab.chat:
        return _ChannelChatBody(channel: channel);
    }
  }
}

class _WorkspaceStreamViewer extends ConsumerWidget {
  const _WorkspaceStreamViewer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasStreamContext = ref.watch(
      sessionViewProvider.select(
        (view) =>
            view.connected &&
            (view.streams.isNotEmpty || view.watchingStreamId != null),
      ),
    );
    final isPublishing = ref.watch(
      streamPublisherProvider.select((state) => state.isActive),
    );
    final isViewerActive = ref.watch(
      streamViewerProvider.select((state) => state.isActive),
    );
    if (!hasStreamContext && !isPublishing && !isViewerActive) {
      return const SizedBox.shrink();
    }
    final view = ref.watch(sessionViewProvider);
    return RepaintBoundary(child: StreamViewerSection(view: view));
  }
}

class _ChannelMediaBody extends ConsumerWidget {
  const _ChannelMediaBody({required this.channelId});

  final int channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (
      :messages,
      :chatScope,
      :directRecipientUid,
      :directRecipientId,
      :selfClientId,
      :clients,
      :selfChannelId,
    ) = ref.watch(
      sessionViewProvider.select(
        (view) => (
          messages: view.messages,
          chatScope: view.chatScope,
          directRecipientUid: view.directRecipientUid,
          directRecipientId: view.directRecipientId,
          selfClientId: view.selfClientId,
          clients: view.clients,
          selfChannelId: view.selfChannelId,
        ),
      ),
    );
    final scopedView = SessionView(
      state: selfClientId != null
          ? CoreSessionState.connected(
              clientId: selfClientId,
              channelId: selfChannelId ?? 0,
            )
          : const CoreSessionState.disconnected(),
      messages: messages,
      clients: clients,
      chatScope: chatScope,
      directRecipientUid: directRecipientUid,
      directRecipientId: directRecipientId,
    );
    final urls = imageUrlsInMessages(
      scopedView.visibleMessages(channelId: channelId),
    );
    return MediaGrid(
      urls: urls,
      onOpen: (index) =>
          showMediaViewer(context, urls: urls, initialIndex: index),
    );
  }
}

class _ChannelChatBody extends ConsumerStatefulWidget {
  const _ChannelChatBody({required this.channel});

  final ChannelView channel;

  @override
  ConsumerState<_ChannelChatBody> createState() => _ChannelChatBodyState();
}

class _ChannelChatBodyState extends ConsumerState<_ChannelChatBody> {
  List<ChatMessage>? _lastMessages;
  List<ClientView>? _lastClients;
  ChatScope? _lastScope;
  String? _lastRecipientUid;
  int? _lastSelfClientId;
  int _lastChannelId = -1;
  List<ChatMessage> _cachedVisible = const [];
  List<ClientView> _cachedRecipients = const [];

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final (
      :activeServerId,
      :messages,
      :clients,
      :chatScope,
      :selfChannelId,
      :selfClientId,
      :busy,
      :directRecipientUid,
      :directRecipientId,
      :unreadScopes,
      :unreadPeers,
    ) = ref.watch(
      sessionViewProvider.select(
        (view) => (
          activeServerId: view.activeServerId,
          messages: view.messages,
          clients: view.clients,
          chatScope: view.chatScope,
          selfChannelId: view.selfChannelId,
          selfClientId: view.selfClientId,
          busy: view.busy,
          directRecipientUid: view.directRecipientUid,
          directRecipientId: view.directRecipientId,
          unreadScopes: view.unreadScopes,
          unreadPeers: view.unreadPeers,
        ),
      ),
    );

    if (!identical(_lastClients, clients) ||
        _lastSelfClientId != selfClientId) {
      _lastClients = clients;
      _cachedRecipients = clients
          .where((peer) => peer.id != selfClientId && peer.uid.isNotEmpty)
          .toList(growable: false);
    }

    final scopedView = SessionView(
      state: selfClientId != null
          ? CoreSessionState.connected(
              clientId: selfClientId,
              channelId: selfChannelId ?? 0,
            )
          : const CoreSessionState.disconnected(),
      messages: messages,
      clients: clients,
      chatScope: chatScope,
      directRecipientUid: directRecipientUid,
      directRecipientId: directRecipientId,
    );

    if (!identical(_lastMessages, messages) ||
        _lastScope != chatScope ||
        _lastRecipientUid != directRecipientUid ||
        _lastSelfClientId != selfClientId ||
        _lastChannelId != channel.id) {
      _lastMessages = messages;
      _lastScope = chatScope;
      _lastRecipientUid = directRecipientUid;
      _lastSelfClientId = selfClientId;
      _lastChannelId = channel.id;
      _cachedVisible = scopedView.visibleMessages(channelId: channel.id);
    }

    final controller = ref.read(sessionViewProvider.notifier);
    return ChatPane(
      avatarBuilder: (message) =>
          message.scope == ChatScope.server &&
              message.fromId == 0 &&
              message.fromUid.isEmpty &&
              activeServerId != null
          ? ServerBadge(id: activeServerId, size: AvatarSize.medium)
          : SessionMemberAvatar(uid: message.fromUid, nickname: message.from),
      key: ValueKey(channel.id),
      channelName: channelDisplayName(channel),
      messages: _cachedVisible,
      scope: chatScope,
      canSendChannel: selfChannelId == channel.id,
      busy: busy,
      onScopeChanged: controller.selectChatScope,
      onSend: controller.prepareMessageSender(),
      onPickImage: () => controller.pickChatImage(paste: false),
      onPasteImage: () => controller.pickChatImage(paste: true),
      onUploadImage: controller.uploadChatImage,
      onConfigureImageHost: () => showImageHostSettings(context),
      description: channel.description,
      recipients: _cachedRecipients,
      recipientUid: directRecipientUid,
      recipientId: directRecipientId,
      unreadScopes: unreadScopes,
      unreadPeers: unreadPeers,
      selfUid: scopedView.selfUid,
      selfClientId: selfClientId,
      selfChannelId: selfChannelId,
      onRecipientChanged: controller.selectDirectRecipient,
      onRecipientSelected: (peer) =>
          controller.selectDirectRecipient(peer.uid, clientId: peer.id),
      onFetchBotCommands: (peer) =>
          controller.fetchBotCommands(peer.id, peer.uid),
      onReply: controller.replyToMessage,
    );
  }
}

class _TabSpec {
  const _TabSpec({required this.tab, required this.label, required this.icon});

  final _MainTab tab;
  final String label;
  final IconData icon;
}

List<_TabSpec> _tabSpecs(
  AppLocalizations l10n, {
  required bool isMemberDetails,
}) => [
  _TabSpec(
    tab: _MainTab.chat,
    label: l10n.chatTabMessages,
    icon: Icons.chat_bubble_rounded,
  ),
  _TabSpec(
    tab: _MainTab.media,
    label: l10n.chatTabMedia,
    icon: Icons.photo_library_rounded,
  ),
  _TabSpec(
    tab: _MainTab.files,
    label: l10n.chatTabFiles,
    icon: Icons.folder_rounded,
  ),
  _TabSpec(
    tab: _MainTab.details,
    label: isMemberDetails ? l10n.memberDetails : l10n.channelDetails,
    icon: Icons.info_outline_rounded,
  ),
];

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.channel,
    required this.tabController,
    required this.isMemberDetails,
  });

  final ChannelView? channel;
  final TabController tabController;
  final bool isMemberDetails;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasChannel = channel != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColorOf(context))),
      ),
      child: SafeArea(
        bottom: false,
        left: false,
        child: SizedBox(
          height: Sizes.header,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: WindowDragRegion(
                    child: Semantics(
                      header: true,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          channel != null
                              ? channelDisplayName(channel!)
                              : l10n.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasChannel) ...[
                  const SizedBox(width: 6),
                  _ViewTabs(
                    tabs: _tabSpecs(l10n, isMemberDetails: isMemberDetails),
                    controller: tabController,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 频道头里的视图切换：M3 primary tabs（`TabBar`），是同级视图切换的规范组件，
/// 指示器动画与语义由组件自带。
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.tabs, required this.controller});

  final List<_TabSpec> tabs;
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      // M3 scrollable tabs 的默认对齐：首签偏移一个 tab 边距。
      tabAlignment: TabAlignment.start,
      // 频道头为 48 高，页签压到 36 垂直居中。
      splashBorderRadius: Radii.pillAll,
      tabs: [
        for (final tab in tabs)
          Tab(
            height: 36,
            child: Icon(
              tab.icon,
              size: IconSizes.medium,
              semanticLabel: tab.label,
            ),
          ),
      ],
    );
  }
}

class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner({required this.target, required this.onCancel});

  final int target;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        // 与页面级横幅同一档圆角。
        borderRadius: Radii.xxlAll,
      ),
      child: Row(
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            size: IconSizes.medium,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.identityUpgrading(target),
              style: context.texts.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(onPressed: onCancel, child: Text(l10n.identityCancel)),
        ],
      ),
    );
  }
}

/// 语音设备状态 chip，任何页签下都可见。瞬时语音错误走右上角提示。
class _VoiceAlerts extends ConsumerWidget {
  const _VoiceAlerts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:connected, :voiceInputReady, :voiceOutputReady) = ref.watch(
      sessionViewProvider.select(
        (view) => (
          connected: view.connected,
          voiceInputReady: view.voiceInputReady,
          voiceOutputReady: view.voiceOutputReady,
        ),
      ),
    );
    if (!connected || (voiceInputReady && voiceOutputReady)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!voiceInputReady)
                _DeviceChip(
                  icon: Icons.mic_off_rounded,
                  label: l10n.voiceMicUnavailable,
                ),
              if (!voiceOutputReady)
                _DeviceChip(
                  icon: Icons.volume_off_rounded,
                  label: l10n.voiceSpeakerUnavailable,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 设备不可用的状态 chip。
class _DeviceChip extends StatelessWidget {
  const _DeviceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // container 语义对：透明度叠底在暗色下发浊，正文对比不稳。
        color: scheme.errorContainer,
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: IconSizes.state, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
