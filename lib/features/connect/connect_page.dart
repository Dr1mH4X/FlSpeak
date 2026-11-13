import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation_sidebar.dart';
import '../../widgets/prism.dart';
import 'widgets/add_server_dialog.dart';
import 'widgets/connect_header.dart';
import 'widgets/identity_card.dart';
import 'widgets/identity_dialog.dart';
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
      onWorkspace: () => context.go(AppRoutes.workspace),
      onSettings: () => context.push(AppRoutes.settings),
    );

    return Scaffold(
      backgroundColor: context.pageColor,
      body: SafeArea(
        top: !desktop,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              const AppNavigationSidebar(
                selectedDestination: AppNavDestination.home,
              ),
            Expanded(
              child: Material(
                color: context.pageColor,
                borderRadius: BorderRadius.zero,
                clipBehavior: Clip.antiAlias,
                child: SurfaceScope(
                  level: SurfaceLevel.page,
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
    );
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
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.serversTitle,
                        style: context.texts.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ServerSearchControl(
                      maxRowWidth: constraints.maxWidth,
                      onChanged: onSearch,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (context.isCompact)
              ElasticButton(
                child: IconButton.filled(
                  onPressed: onAdd,
                  icon: Icon(Icons.add_rounded, semanticLabel: l10n.serverAdd),
                ),
              )
            else
              ElasticButton(
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: IconSizes.toolbar),
                  label: Text(l10n.serverAdd),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
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
          SurfaceCard(
            clip: true,
            child: Column(
              children: [
                for (var index = 0; index < servers.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: dividerColorOf(context),
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

class _ServerSearchControl extends StatefulWidget {
  const _ServerSearchControl({
    required this.maxRowWidth,
    required this.onChanged,
  });

  final double maxRowWidth;
  final ValueChanged<String> onChanged;

  @override
  State<_ServerSearchControl> createState() => _ServerSearchControlState();
}

class _ServerSearchControlState extends State<_ServerSearchControl>
    with SingleTickerProviderStateMixin {
  static const double _collapsedSize = 40.0;
  static const double _expandedMaxWidth = 260.0;

  bool _expanded = false;
  bool _hasFocus = false;

  late final TextEditingController _controller = TextEditingController()
    ..addListener(_handleTextChanged);
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _handleKeyEvent)
    ..addListener(_handleFocusChanged);
  late final AnimationController _expandController = AnimationController(
    vsync: this,
    duration: Motion.spatialFast,
    reverseDuration: Motion.effectsDefault,
  );
  late final Animation<double> _expandAnimation = CurvedAnimation(
    parent: _expandController,
    curve: Motion.spatialCurve,
    reverseCurve: Motion.effectsDefaultCurve,
  );

  @override
  void dispose() {
    _expandController.dispose();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _animateExpand(bool expand) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _expandController.value = expand ? 1.0 : 0.0;
    } else if (expand) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  void _open() {
    if (!_expanded) {
      setState(() => _expanded = true);
    }
    _animateExpand(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _expanded) {
        _focusNode.requestFocus();
      }
    });
  }

  void _collapseAndClear() {
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      widget.onChanged('');
    }
    if (_expanded) {
      setState(() => _expanded = false);
    }
    _animateExpand(false);
    _focusNode.unfocus();
  }

  void _handleClear() {
    _controller.clear();
    widget.onChanged('');
    _focusNode.requestFocus();
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (_hasFocus != focused) {
      setState(() => _hasFocus = focused);
    }
    if (!focused && _expanded && _controller.text.isEmpty) {
      setState(() => _expanded = false);
      _animateExpand(false);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _expanded) {
      _collapseAndClear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final surfaceFill = context.raisedSurfaceColor;
    final availableWidth = math.max(0.0, widget.maxRowWidth - 12);
    final collapsedWidth = math.min(_collapsedSize, availableWidth);
    final expandedWidth = math.min(
      _expandedMaxWidth,
      math.max(collapsedWidth, availableWidth * 0.65),
    );

    return AnimatedBuilder(
      animation: _expandController,
      builder: (context, _) {
        if (!_expanded && _expandController.isDismissed) {
          return SizedBox(
            width: collapsedWidth,
            height: _collapsedSize,
            child: ElasticButton(
              child: IconButton(
                onPressed: _open,
                style: ButtonStyle.from(
                  backgroundColor: surfaceFill,
                  foregroundColor: scheme.onSurface,
                  fixedSize: Size.square(collapsedWidth),
                  minimumSize: Size.square(collapsedWidth),
                  padding: EdgeInsets.zero,
                  iconSize: IconSizes.toolbar,
                  shape: AppShape.full,
                ),
                icon: Icon(
                  Icons.search_rounded,
                  semanticLabel: l10n.serverSearchLabel,
                ),
              ),
            ),
          );
        }

        final currentWidth = lerpDouble(
          collapsedWidth,
          expandedWidth,
          _expandAnimation.value,
        )!.clamp(collapsedWidth, availableWidth);
        final empty = _controller.text.isEmpty;

        return DecoratedBox(
          decoration: ShapeDecoration(
            color: surfaceFill,
            shape: RoundedSuperellipseBorder(
              borderRadius: AppRadius.full,
              side: _hasFocus
                  ? BorderSide(color: scheme.primary, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: ClipRSuperellipse(
            borderRadius: AppRadius.full,
            child: SizedBox(
              width: currentWidth,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: expandedWidth,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 1,
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.search,
                    onChanged: widget.onChanged,
                    onTapOutside: (_) => _focusNode.unfocus(),
                    style: context.texts.bodyMedium,
                    decoration: InputDecoration(
                      filled: false,
                      hoverColor: Colors.transparent,
                      isDense: true,
                      constraints: const BoxConstraints(
                        minHeight: _collapsedSize,
                      ),
                      hintText: l10n.serverSearchLabel,
                      contentPadding: EdgeInsetsDirectional.fromSTEB(
                        0,
                        8,
                        empty ? 16 : 0,
                        8,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: IconSizes.toolbar,
                        color: scheme.onSurface,
                      ),
                      prefixIconConstraints: const BoxConstraints.tightFor(
                        width: _collapsedSize,
                        height: _collapsedSize,
                      ),
                      suffixIcon: empty
                          ? null
                          : Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: IconButton(
                                onPressed: _handleClear,
                                style: ButtonStyle.from(
                                  foregroundColor: scheme.onSurfaceVariant,
                                  fixedSize: const Size.square(32),
                                  minimumSize: const Size.square(32),
                                  padding: EdgeInsets.zero,
                                  iconSize: IconSizes.medium,
                                  shape: AppShape.full,
                                ),
                                icon: Icon(
                                  Icons.close_rounded,
                                  semanticLabel: l10n.serverSearchClear,
                                ),
                              ),
                            ),
                      suffixIconConstraints: const BoxConstraints(
                        minHeight: _collapsedSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: ShapeDecoration(
                color: scheme.primaryContainer,
                shape: AppShape.xl,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: IconSizes.display,
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
            ElasticButton(
              child: FilledButton.icon(
                onPressed: onAdd,
                style: ButtonStyle.from(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                ),
                icon: const Icon(Icons.add_rounded, size: IconSizes.toolbar),
                label: Text(l10n.serverEmptyAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
