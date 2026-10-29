import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'widgets/add_server_dialog.dart';
import 'widgets/connect_header.dart';
import 'widgets/identity_card.dart';
import 'widgets/identity_dialog.dart';
import '../workspace/widgets/server_rail.dart';
import 'widgets/remove_server_dialog.dart';
import 'widgets/server_row.dart';

/// 连接页：服务器库、搜索与本机身份，沿用工作区的服务器导航。
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
  String _query = '';

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
    final ok = await ref
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
    if (!ok ||
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
      } else if ((previous != null && next.failureSeq != previous.failureSeq) ||
          (!next.busy &&
              !next.connecting &&
              !next.reconnecting &&
              next.activeServerId != null &&
              next.activeServerId != pending)) {
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
    final filtered = servers
        .where(
          (server) => '${server.label} ${server.host}'.toLowerCase().contains(
            _query.toLowerCase().trim(),
          ),
        )
        .toList();

    final section = _ServerSection(
      servers: filtered,
      hasServers: servers.isNotEmpty,
      onSearch: (value) => setState(() => _query = value),
      lastConnected: preferences.lastConnected,
      connectedId: connectedId,
      connectingId: connectingId,
      enabled: !busy && !view.busy,
      onAdd: _openAddServer,
      onConnect: _connect,
      onRemove: _removeServer,
    );

    final identity = wide
        ? IdentityCard(nickname: preferences.nickname, onManage: _openIdentity)
        : IdentityStrip(
            nickname: preferences.nickname,
            serverCount: view.servers.length,
            onManage: _openIdentity,
          );

    final horizontal = wide ? 40.0 : 20.0;
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.connectTitle, style: context.texts.displaySmall),
        const SizedBox(height: 12),
        Text(
          l10n.connectSubtitle,
          style: context.texts.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontal, wide ? 48 : 28, horizontal, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.connectContent),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [intro, const SizedBox(height: 36), section],
                      ),
                    ),
                    const SizedBox(width: 28),
                    SizedBox(width: Sizes.identityColumn, child: identity),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    intro,
                    const SizedBox(height: 28),
                    identity,
                    const SizedBox(height: 28),
                    section,
                  ],
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

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              ServerRail(
                homeSelected: true,
                onSelect: _connect,
                onAdd: _openAddServer,
                onHome: () {},
                onSettings: () => context.push(AppRoutes.settings),
                onDisconnect: () async {
                  await ref.read(sessionViewProvider.notifier).disconnect();
                },
              ),
            Expanded(
              child: Material(
                color: scheme.surface,
                borderRadius: desktop
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(Radii.xxl),
                      )
                    : BorderRadius.zero,
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
          ],
        ),
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
    required this.hasServers,
    required this.onSearch,
    required this.lastConnected,
    required this.connectedId,
    required this.connectingId,
    required this.enabled,
    required this.onAdd,
    required this.onConnect,
    required this.onRemove,
  });

  final List<ServerProfileView> servers;
  final bool hasServers;
  final ValueChanged<String> onSearch;
  final Map<String, DateTime> lastConnected;
  final String? connectedId;
  final String? connectingId;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<ServerProfileView> onConnect;
  final ValueChanged<ServerProfileView> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.serversTitle, style: context.texts.titleLarge),
            ),
            if (context.isCompact)
              IconButton.filled(
                onPressed: onAdd,
                icon: Icon(Icons.add_rounded, semanticLabel: l10n.serverAdd),
              )
            else
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(l10n.serverAdd),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (hasServers) ...[
          TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              labelText: l10n.serverSearchLabel,
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (!hasServers)
          _EmptyServers(onAdd: onAdd)
        else if (servers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              l10n.serverSearchEmpty,
              style: context.texts.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          HairlineCard(
            clip: true,
            child: Column(
              children: [
                for (var index = 0; index < servers.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: scheme.outlineVariant,
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
    return HairlineCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: Radii.xxlAll,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 36,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.serverEmptyTitle,
              style: context.texts.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.serverEmptyBody,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(l10n.serverEmptyAction),
            ),
          ],
        ),
      ),
    );
  }
}
