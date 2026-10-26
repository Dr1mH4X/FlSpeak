import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'widgets/add_server_dialog.dart';
import 'widgets/connect_header.dart';
import 'widgets/dashed_border.dart';
import 'widgets/identity_card.dart';
import 'widgets/identity_dialog.dart';
import 'widgets/login_rail.dart';
import 'widgets/remove_server_dialog.dart';
import 'widgets/server_row.dart';

/// 打开应用看到的第一页：身份 + 服务器列表。
///
/// 一行服务器就是一次连接，昵称从本机身份里带过去，不再有第二步。
/// 宽屏是「身份卡 + 列表」两列，窄屏把身份压成一条，首屏留给服务器。
class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({this.serverId, super.key});

  /// 从工作区服务器栏跳进来时直接连接这台服务器。
  final String? serverId;

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  /// 正在连接的目标。用来在状态事件到达前就把对应行标成连接中。
  String? _pendingServerId;
  bool _autoConnectTried = false;

  @override
  void didUpdateWidget(ConnectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.serverId != oldWidget.serverId) {
      _autoConnectTried = false;
    }
  }

  Future<void> _connect(ServerProfileView profile) async {
    if (!mounted || _pendingServerId != null) {
      return;
    }
    final view = ref.read(sessionViewProvider);
    if (view.connected && view.activeServerId == profile.id) {
      context.go(AppRoutes.workspace);
      return;
    }
    if (view.connecting || view.busy) {
      return;
    }

    _pendingServerId = profile.id;
    await ref
        .read(sessionViewProvider.notifier)
        .connect(
          id: profile.id,
          nickname: ref.read(preferencesProvider).nickname,
        );
    if (!mounted) {
      return;
    }
    // 正常路径由 build 里的 listen 处理；这里兜住「事件已经处理完」的时序。
    final next = ref.read(sessionViewProvider);
    if (next.connected && next.activeServerId == profile.id) {
      if (_pendingServerId == profile.id) {
        _pendingServerId = null;
        ref
            .read(preferencesProvider.notifier)
            .markConnected(profile.id, DateTime.now());
        context.go(AppRoutes.workspace);
      }
      return;
    }
    if (next.notice != null ||
        (next.activeServerId != null && next.activeServerId != profile.id)) {
      _pendingServerId = null;
    }
  }

  Future<void> _openAddServer() async {
    final profile = await showAddServerDialog(context);
    if (profile != null && mounted) {
      await _connect(profile);
    }
  }

  Future<void> _openIdentity() async {
    await showIdentityDialog(
      context,
      nickname: ref.read(preferencesProvider).nickname,
      onRename: ref.read(preferencesProvider.notifier).setNickname,
    );
  }

  Future<void> _removeServer(ServerProfileView profile) async {
    final confirmed = await showRemoveServerDialog(context, profile);
    if (confirmed && mounted) {
      await ref.read(sessionViewProvider.notifier).removeServer(profile.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final preferences = ref.watch(preferencesProvider);
    final scheme = context.scheme;
    final size = MediaQuery.sizeOf(context);
    final desktop = size.width >= Breakpoints.compact;
    final wide = size.width >= Breakpoints.wide;

    ref.listen<SessionView>(sessionViewProvider, (previous, next) {
      final pending = _pendingServerId;
      if (pending == null) {
        return;
      }
      if (next.connected && next.activeServerId == pending) {
        _pendingServerId = null;
        ref
            .read(preferencesProvider.notifier)
            .markConnected(pending, DateTime.now());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go(AppRoutes.workspace);
          }
        });
      } else if (next.notice != null ||
          (next.activeServerId != null && next.activeServerId != pending)) {
        // 只有明确的失败/换目标才放掉连接中状态；busy 结束不等于连上。
        _pendingServerId = null;
      }
    });

    if (!_autoConnectTried && widget.serverId != null) {
      final target = _serverById(view.servers, widget.serverId!);
      if (target != null) {
        _autoConnectTried = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _connect(target);
          }
        });
      }
    }

    final connectedId = view.connected ? view.activeServerId : null;
    final connectingId =
        _pendingServerId ??
        ((view.connecting || view.reconnecting) ? view.activeServerId : null);
    final busy =
        _pendingServerId != null || view.connecting || view.reconnecting;
    final servers = _orderedServers(view, preferences.lastConnected);

    final section = _ServerSection(
      servers: servers,
      lastConnected: preferences.lastConnected,
      connectedId: connectedId,
      connectingId: connectingId,
      enabled: !busy && !view.busy,
      notice: view.notice,
      onDismissNotice: ref.read(sessionViewProvider.notifier).dismissNotice,
      onAdd: _openAddServer,
      onConnect: _connect,
      onRemove: _removeServer,
    );

    final identity = wide
        ? IdentityCard(
            nickname: preferences.nickname,
            identityCount: 1,
            serverCount: view.servers.length,
            onManage: _openIdentity,
          )
        : IdentityStrip(
            nickname: preferences.nickname,
            serverCount: view.servers.length,
            onManage: _openIdentity,
          );

    final horizontal = wide ? 32.0 : (size.width >= 640 ? 24.0 : 16.0);
    final top = wide ? 40.0 : (size.width >= 640 ? 24.0 : 8.0);
    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.connectContent),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: Sizes.identityColumn, child: identity),
                    const SizedBox(width: 24),
                    Expanded(child: section),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [identity, const SizedBox(height: 20), section],
                ),
        ),
      ),
    );

    final header = ConnectHeader(
      desktop: desktop,
      connected: view.connected,
      status: _statusText(l10n, view),
      statusColor: view.connected
          ? context.status.live
          : (busy ? scheme.primary : scheme.outline),
      onWorkspace: () => context.go(AppRoutes.workspace),
      onSettings: () => context.push(AppRoutes.settings),
    );

    final glow = Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 520,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.1, -1),
              radius: 0.95,
              colors: [
                scheme.primary.withValues(alpha: 0.10),
                scheme.primary.withValues(alpha: 0),
              ],
              stops: const [0, 0.7],
            ),
          ),
        ),
      ),
    );

    if (desktop) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: Stack(
          children: [
            glow,
            SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LoginRail(onSettings: () => context.push(AppRoutes.settings)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                      child: Material(
                        // 不透明面板：半透明会让顶部光晕透进来，暗色下与
                        // 8px 沟槽糊成一片；与工作区面板的做法对齐。
                        color: context.cardColor,
                        borderRadius: Radii.xxxlAll,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            header,
                            Expanded(child: content),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          glow,
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(AppLocalizations l10n, SessionView view) {
    if (view.reconnecting) {
      return l10n.voiceReconnectingAttempt(view.reconnectAttempt ?? 1);
    }
    final active = view.activeServer;
    if (view.connected) {
      return active == null
          ? l10n.sessionConnected
          : l10n.sessionConnectedTo(active.label);
    }
    final pending = _pendingServerId;
    if (pending != null) {
      final target = _serverById(view.servers, pending);
      if (target != null) {
        return l10n.sessionConnectingTo(target.label);
      }
    }
    if ((view.connecting || view.busy) && active != null) {
      return l10n.sessionConnectingTo(active.label);
    }
    return l10n.sessionDisconnected;
  }
}

List<ServerProfileView> _orderedServers(
  SessionView view,
  Map<String, DateTime> lastConnected,
) {
  final order = <String, int>{
    for (var index = 0; index < view.servers.length; index++)
      view.servers[index].id: index,
  };
  final servers = [...view.servers];
  servers.sort((a, b) {
    final aConnected = view.connected && view.activeServerId == a.id;
    final bConnected = view.connected && view.activeServerId == b.id;
    if (aConnected != bConnected) {
      return aConnected ? -1 : 1;
    }
    final aTime = lastConnected[a.id];
    final bTime = lastConnected[b.id];
    if (aTime != null || bTime != null) {
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      final byTime = bTime.compareTo(aTime);
      if (byTime != 0) {
        return byTime;
      }
    }
    return (order[a.id] ?? 0).compareTo(order[b.id] ?? 0);
  });
  return servers;
}

ServerProfileView? _serverById(List<ServerProfileView> servers, String id) {
  for (final server in servers) {
    if (server.id == id) {
      return server;
    }
  }
  return null;
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({
    required this.servers,
    required this.lastConnected,
    required this.connectedId,
    required this.connectingId,
    required this.enabled,
    required this.notice,
    required this.onDismissNotice,
    required this.onAdd,
    required this.onConnect,
    required this.onRemove,
  });

  final List<ServerProfileView> servers;
  final Map<String, DateTime> lastConnected;
  final String? connectedId;
  final String? connectingId;
  final bool enabled;
  final String? notice;
  final VoidCallback onDismissNotice;
  final VoidCallback onAdd;
  final ValueChanged<ServerProfileView> onConnect;
  final ValueChanged<ServerProfileView> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    // 640 以下按钮只留图标，把宽度让给标题与计数。
    final showAddLabel = MediaQuery.sizeOf(context).width >= 640;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      l10n.serversTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.titleLarge,
                    ),
                  ),
                  if (servers.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${servers.length}',
                      style: texts.bodySmall?.copyWith(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (servers.isNotEmpty)
              showAddLabel
                  ? OutlinedButton(
                      onPressed: onAdd,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, Sizes.touch),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        foregroundColor: scheme.onSurface,
                        backgroundColor: scheme.surface,
                        textStyle: texts.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(l10n.serverAdd),
                        ],
                      ),
                    )
                  : IconButton.outlined(
                      tooltip: l10n.serverAdd,
                      onPressed: onAdd,
                      iconSize: 18,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(Sizes.touch, Sizes.touch),
                        maximumSize: const Size(Sizes.touch, Sizes.touch),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.add_rounded),
                    ),
          ],
        ),
        // 通知条平滑展开/收起：出现与消失不再挤压布局。
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Motion.effectsFast,
          curve: Motion.effectsFastCurve,
          alignment: Alignment.topCenter,
          child: notice == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: NoticeBar(
                    message: notice!,
                    dismissTooltip: l10n.commonClose,
                    onDismiss: onDismissNotice,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        if (servers.isEmpty)
          _EmptyServers(onAdd: onAdd)
        else ...[
          // 卡片高度随服务器的增删走 spatial fast：列表重排不再瞬跳。
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.spatialFast,
            curve: Motion.spatialCurve,
            alignment: Alignment.topCenter,
            child: HairlineCard(
              clip: true,
              child: Column(
                children: [
                  for (var index = 0; index < servers.length; index++) ...[
                    if (index > 0)
                      // 分隔线缩进到内容边缘：不顶到卡片圆角区，也和头像对齐。
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 20,
                        endIndent: 20,
                        color: hairlineSide(context).color,
                      ),
                    ServerRow(
                      profile: servers[index],
                      lastConnected: lastConnected[servers[index].id],
                      connected: servers[index].id == connectedId,
                      connecting: servers[index].id == connectingId,
                      enabled: enabled && servers[index].id != connectingId,
                      onTap: () => onConnect(servers[index]),
                      onRemove: () => onRemove(servers[index]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AddServerRow(onTap: onAdd),
        ],
      ],
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return Container(
      decoration: BoxDecoration(
        // 实色：透明叠底在暗色下与页面底板糊在一起，虚线描边才是空态的
        // 视觉信号。
        color: context.cardColor,
        borderRadius: Radii.xxlAll,
      ),
      child: DashedBorder(
        color: context.hairline,
        radius: Radii.xxl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: Radii.xxlAll,
                ),
                child: Icon(
                  Icons.dns_rounded,
                  size: 22,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.serverEmptyTitle,
                style: context.texts.bodyLarge?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(l10n.serverEmptyAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddServerRow extends StatelessWidget {
  const _AddServerRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return HairlineCard(
      clip: true,
      child: InkWell(
        onTap: onTap,
        // M3 state layer：onSurface 8%。
        hoverColor: scheme.onSurface.withValues(alpha: 0.08),
        child: Padding(
          // 内容缩进与服务器行（20）对齐，+ 圆钮和头像落在同一条线上。
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.serverAdd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
