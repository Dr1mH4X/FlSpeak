import 'dart:async';

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
        PopupMenuItem,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../core/channel_display.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/stream_publisher.dart';
import '../../core/stream_viewer.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glyph_segmented_control.dart';
import '../../widgets/monogram.dart';
import '../../widgets/prism.dart';
import '../../widgets/scaffold/scaffold.dart' as app_scaffold;
import '../../widgets/window_header.dart';
import '../settings/widgets/image_host_dialog.dart';
import 'widgets/chat_pane.dart';
import 'widgets/channel_files_pane.dart';
import 'widgets/channel_details_pane.dart';
import 'widgets/client_actions.dart';
import 'widgets/member_details_pane.dart';
import 'widgets/media_grid.dart';
import 'widgets/media_viewer.dart';
import 'widgets/members_pane.dart';
import 'widgets/member_avatar.dart';
import 'widgets/member_status_flags.dart';
import 'widgets/stream_viewer_pane.dart';
import 'workspace_shell.dart';
import 'workspace_state.dart';

/// 以 `prism_ui` 底部抽屉（窄屏）或侧栏（宽屏）承载工作区详情、文件与媒体面板。
Future<void> showWorkspaceDetailSheet(
  BuildContext context, {
  required String title,
  required Glyph glyph,
  required Widget child,
}) {
  return showSheet<void>(
    context: context,
    builder: (sheetContext) => Material(
      type: MaterialType.transparency,
      child: app_scaffold.Scaffold(
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(glyph, size: IconSizes.medium),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        body: SafeArea(top: false, child: AppBarClearance(child: child)),
      ),
    ),
  );
}

Future<void> showChannelDetailsSheet(
  BuildContext context,
  ChannelView channel,
) {
  return showWorkspaceDetailSheet(
    context,
    title: AppLocalizations.of(context).channelDetails,
    glyph: AppGlyphs.info,
    child: ChannelDetailsPane(channel: channel),
  );
}

Future<void> showChannelFilesSheet(BuildContext context, int channelId) {
  return showWorkspaceDetailSheet(
    context,
    title: AppLocalizations.of(context).chatTabFiles,
    glyph: AppGlyphs.folder,
    child: ChannelFilesPane(channelId: channelId),
  );
}

Future<void> showMemberDetailsSheet(
  BuildContext context,
  ClientView client, {
  bool isOffline = false,
}) {
  return showWorkspaceDetailSheet(
    context,
    title: AppLocalizations.of(context).memberDetails,
    glyph: AppGlyphs.account,
    child: MemberDetailsPane(client: client, isOffline: isOffline),
  );
}

/// 主区域：频道标题 + 消息 / 媒体两个视图，以及掉线后的空状态。
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({this.forceCompact = false, super.key});

  /// 由窄屏频道页路由承载时固定使用单栏布局，窗口变宽也不切成缺少侧栏的宽屏骨架。
  final bool forceCompact;

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

enum _MainTab { chat, media, files, details }

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  _MainTab _tab = _MainTab.chat;

  void _selectTab(_MainTab tab) {
    if (tab == _tab) {
      return;
    }
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.forceCompact ||
        MediaQuery.sizeOf(context).width < Breakpoints.compact) {
      return;
    }
    // 频道页只在窄屏作为路由承载；窗口变宽后退回宽屏三栏骨架。
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(Navigator.of(context).maybePop());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final compact =
        widget.forceCompact ||
        MediaQuery.sizeOf(context).width < Breakpoints.compact;
    final channelId = ref.watch(activeChannelIdProvider);
    final detailsTarget = ref.watch(activeDetailsTargetProvider);
    final detailsGlyph = detailsTarget is MemberDetailsTarget
        ? AppGlyphs.account
        : AppGlyphs.info;
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
          if (mounted && _tab != _MainTab.chat) _selectTab(_MainTab.chat);
        });
      },
    );

    ref.listen(selectedMemberProvider, (previous, next) {
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !compact && _tab != _MainTab.details) {
            _selectTab(_MainTab.details);
          }
        });
      }
    });

    // 窄屏二级频道页是推入的路由；连接结束后退回一级频道总览。
    ref.listen<bool>(
      sessionViewProvider.select(
        (view) => view.connected || view.connecting || view.reconnecting,
      ),
      (previous, hasSession) {
        if (hasSession || !mounted || !compact) {
          return;
        }
        final navigator = Navigator.maybeOf(context);
        if (navigator?.canPop() == true) {
          unawaited(navigator!.maybePop());
        }
      },
    );

    final mainPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (identityUpgradeTarget != null)
          WorkspaceIdentityBanner(
            target: identityUpgradeTarget,
            onCancel: ref
                .read(sessionViewProvider.notifier)
                .cancelIdentityUpgrade,
          ),
        const WorkspaceVoiceAlerts(),
        const _WorkspaceStreamViewer(),
        Expanded(
          // 频道或连接变化时整块内容走 crossfade（M3 effects default），不做位移；
          // 页签切换由内层 key 即时替换，指示器与图标动效由 GlyphSegmentedControl 承担。
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
                            activeServerId,
                            connectionEpoch,
                            channelId,
                            connected,
                            connecting || reconnecting,
                          )),
                          child: KeyedSubtree(
                            key: ValueKey((
                              _tab,
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
      final fullScreen = ref.watch(
        streamViewerProvider.select((state) => state.isFullScreen),
      );
      return PopScope(
        canPop: !fullScreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && fullScreen) {
            unawaited(
              ref.read(streamViewerProvider.notifier).setFullScreen(false),
            );
          }
        },
        child: app_scaffold.Scaffold(
          backgroundColor: context.pageColor,
          title: channel != null ? channelDisplayName(channel) : l10n.appName,
          backAction: () => navigateWorkspaceBack(context),
          menuItems: [
            if (channel != null) ...[
              PopupMenuItem(
                glyph: AppGlyphs.info,
                label: l10n.channelDetails,
                onPressed: () =>
                    unawaited(showChannelDetailsSheet(context, channel)),
              ),
              PopupMenuItem(
                glyph: AppGlyphs.folder,
                label: l10n.chatTabFiles,
                onPressed: () =>
                    unawaited(showChannelFilesSheet(context, channel.id)),
              ),
              PopupMenuItem(
                glyph: AppGlyphs.photos,
                label: l10n.chatTabMedia,
                onPressed: () => unawaited(
                  showWorkspaceDetailSheet(
                    context,
                    title: l10n.chatTabMedia,
                    glyph: AppGlyphs.photos,
                    child: _ChannelMediaBody(channelId: channel.id),
                  ),
                ),
              ),
            ],
          ],
          body: Builder(
            builder: (context) => Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: EdgeInsets.only(top: context.appBarInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (identityUpgradeTarget != null)
                      WorkspaceIdentityBanner(
                        target: identityUpgradeTarget,
                        onCancel: ref
                            .read(sessionViewProvider.notifier)
                            .cancelIdentityUpgrade,
                      ),
                    const WorkspaceVoiceAlerts(),
                    const _WorkspaceStreamViewer(),
                    if (channel != null && connected)
                      _CompactChannelMembersStrip(channelId: channel.id),
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
                              activeServerId,
                              connectionEpoch,
                              channelId,
                              connected,
                              connecting || reconnecting,
                            )),
                            child: _buildCompactBody(
                              context,
                              l10n,
                              connected: connected,
                              connecting: connecting,
                              reconnecting: reconnecting,
                              reconnectAttempt: reconnectAttempt,
                              channel: channel,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
          tab: _tab,
          detailsGlyph: detailsGlyph,
          onTabSelected: _selectTab,
        ),
        Expanded(child: SafeArea(top: false, left: false, child: mainPane)),
      ],
    );
  }

  Widget _buildCompactBody(
    BuildContext context,
    AppLocalizations l10n, {
    required bool connected,
    required bool connecting,
    required bool reconnecting,
    required int? reconnectAttempt,
    required ChannelView? channel,
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
      return EmptyState(
        icon: connected ? Icons.forum_rounded : Icons.link_off_rounded,
        body: connected ? l10n.workspaceNoChannels : l10n.workspaceDropped,
      );
    }

    return _ChannelChatBody(channel: channel);
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

class _CompactChannelMembersStrip extends ConsumerWidget {
  const _CompactChannelMembersStrip({required this.channelId});

  final int channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(
      sessionViewProvider.select(
        (view) => view.clients
            .where((client) => client.channelId == channelId)
            .toList(growable: false),
      ),
    );
    if (members.isEmpty) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColorOf(context))),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 50,
          child: PrismListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            gap: 8,
            estimatedItemExtent: 120,
            itemCount: members.length,
            itemBuilder: (context, index) => _CompactMemberChip(
              key: ValueKey(members[index].id),
              member: members[index],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactMemberChip extends ConsumerWidget {
  const _CompactMemberChip({required this.member, super.key});

  final ClientView member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speaking = ref.watch(
      sessionViewProvider.select(
        (view) =>
            view.speaking.contains(member.id) ||
            (member.id == view.selfClientId && view.selfSpeaking),
      ),
    );
    final sharingScreen = ref.watch(
      sessionViewProvider.select((view) => view.isClientSharingScreen(member)),
    );
    return Surface(
      color: context.cardColor,
      shape: AppShape.full,
      clipBehavior: Clip.antiAlias,
      child: ClientActionsButton(
        client: member,
        compactMenuOnTap: true,
        onShowDetails: () => unawaited(showMemberDetailsSheet(context, member)),
        onDirectChat: () {},
        onWatchStream: (_) {},
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SessionMemberAvatar(
                uid: member.uid,
                nickname: member.nickname,
                size: 26,
                speaking: speaking,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Text(
                  member.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelMedium,
                ),
              ),
              MemberStatusFlags(client: member, sharingScreen: sharingScreen),
            ],
          ),
        ),
      ),
    );
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
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.channel,
    required this.tab,
    required this.detailsGlyph,
    required this.onTabSelected,
  });

  final ChannelView? channel;
  final _MainTab tab;
  final Glyph detailsGlyph;
  final ValueChanged<_MainTab> onTabSelected;

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
                  flex: 5,
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
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 184,
                    child: GlyphSegmentedControl<_MainTab>(
                      segments: [
                        GlyphSegment(
                          value: _MainTab.chat,
                          glyph: AppGlyphs.chat,
                          label: l10n.chatTabMessages,
                        ),
                        GlyphSegment(
                          value: _MainTab.media,
                          glyph: AppGlyphs.photos,
                          label: l10n.chatTabMedia,
                        ),
                        GlyphSegment(
                          value: _MainTab.files,
                          glyph: AppGlyphs.folder,
                          label: l10n.chatTabFiles,
                        ),
                        GlyphSegment(
                          value: _MainTab.details,
                          glyph: detailsGlyph,
                          label: l10n.chatTabDetails,
                        ),
                      ],
                      value: tab,
                      onChanged: onTabSelected,
                    ),
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

class WorkspaceIdentityBanner extends StatelessWidget {
  const WorkspaceIdentityBanner({
    required this.target,
    required this.onCancel,
    super.key,
  });

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
class WorkspaceVoiceAlerts extends ConsumerWidget {
  const WorkspaceVoiceAlerts({super.key});

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
