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
import '../../widgets/monogram.dart';

/// 打开应用看到的第一个界面：录入地址、挑一台已登记的服务器、填昵称。
///
/// 两步式与 Fladder 的登录一致——先选服务器，再进入该服务器的凭据步骤。
class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({this.serverId, super.key});

  /// 从服务器栏跳进来时预选这台服务器，直接落在昵称步骤。
  final String? serverId;

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _address = TextEditingController();
  final _label = TextEditingController();
  final _nickname = TextEditingController();

  String? _selectedId;
  String? _addressError;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.serverId;
  }

  @override
  void dispose() {
    _address.dispose();
    _label.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final address = _address.text.trim();
    if (address.isEmpty) {
      setState(
        () => _addressError = AppLocalizations.of(context).serverInvalidAddress,
      );
      return;
    }
    setState(() => _addressError = null);

    final label = _label.text.trim();
    final profile = await ref
        .read(sessionViewProvider.notifier)
        .addServer(
          label: label.isEmpty ? _hostOf(address) : label,
          address: address,
        );
    if (!mounted || profile == null) {
      return;
    }
    _address.clear();
    _label.clear();
    setState(() => _selectedId = profile.id);
  }

  Future<void> _connect(ServerProfileView profile) async {
    final nickname = _nickname.text.trim();
    ref.read(nicknameProvider.notifier).update(nickname);
    await ref
        .read(sessionViewProvider.notifier)
        .connect(
          id: profile.id,
          nickname: nickname.isEmpty ? ref.read(nicknameProvider) : nickname,
        );
    if (!mounted) {
      return;
    }
    if (ref.read(sessionViewProvider).connected) {
      context.go(AppRoutes.workspace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final controller = ref.read(sessionViewProvider.notifier);
    final selected = _selectedProfile(view);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              connected: view.connected,
              onSettings: () => context.go(AppRoutes.settings),
              onWorkspace: () => context.go(AppRoutes.workspace),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      MediaQuery.sizeOf(context).width < Breakpoints.compact
                          ? 16
                          : 24,
                      8,
                      MediaQuery.sizeOf(context).width < Breakpoints.compact
                          ? 16
                          : 24,
                      32,
                    ),
                    children: [
                      _Wordmark(name: l10n.appName, tagline: l10n.appTagline),
                      const SizedBox(height: 28),
                      if (view.notice != null) ...[
                        NoticeBar(
                          message: view.notice!,
                          dismissTooltip: l10n.commonClose,
                          onDismiss: controller.dismissNotice,
                        ),
                        const SizedBox(height: 20),
                      ],
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            alignment: Alignment.topLeft,
                            child: child,
                          ),
                        ),
                        child: selected == null
                            ? _ServerListStep(
                                key: const ValueKey('servers'),
                                address: _address,
                                label: _label,
                                addressError: _addressError,
                                busy: view.busy,
                                servers: view.servers,
                                activeServerId: view.activeServerId,
                                onAddressSubmitted: _register,
                                onRegister: _register,
                                onPick: (profile) =>
                                    setState(() => _selectedId = profile.id),
                                onRemove: controller.removeServer,
                              )
                            : _NicknameStep(
                                key: ValueKey(selected.id),
                                profile: selected,
                                nickname: _nickname,
                                busy: view.busy || view.connecting,
                                connected:
                                    view.connected &&
                                    view.activeServerId == selected.id,
                                onBack: () =>
                                    setState(() => _selectedId = null),
                                onConnect: () => _connect(selected),
                              ),
                      ),
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

  ServerProfileView? _selectedProfile(SessionView view) {
    final id = _selectedId;
    if (id == null) {
      return null;
    }
    for (final server in view.servers) {
      if (server.id == id) {
        return server;
      }
    }
    return null;
  }
}

String _hostOf(String address) {
  final withoutScheme = address.contains('://')
      ? address.split('://').last
      : address;
  final host = withoutScheme.split(':').first;
  return host.isEmpty ? address : host;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.connected,
    required this.onSettings,
    required this.onWorkspace,
  });

  final bool connected;
  final VoidCallback onSettings;
  final VoidCallback onWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Spacer(),
          if (connected)
            TextButton.icon(
              onPressed: onWorkspace,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(l10n.workspaceReturn),
            ),
          IconButton(
            tooltip: l10n.settingsTitle,
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.name, required this.tagline});

  final String name;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: scheme.onPrimary,
            size: 30,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: text.displaySmall),
              const SizedBox(height: 2),
              Text(
                tagline,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 第一步：登记新服务器，并列出已登记的档案。
class _ServerListStep extends StatelessWidget {
  const _ServerListStep({
    required this.address,
    required this.label,
    required this.addressError,
    required this.busy,
    required this.servers,
    required this.activeServerId,
    required this.onAddressSubmitted,
    required this.onRegister,
    required this.onPick,
    required this.onRemove,
    super.key,
  });

  final TextEditingController address;
  final TextEditingController label;
  final String? addressError;
  final bool busy;
  final List<ServerProfileView> servers;
  final String? activeServerId;
  final VoidCallback onAddressSubmitted;
  final VoidCallback onRegister;
  final ValueChanged<ServerProfileView> onPick;
  final Future<void> Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.connectNewServerTitle, style: text.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: address,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => onAddressSubmitted(),
          decoration: InputDecoration(
            labelText: l10n.connectAddressLabel,
            hintText: l10n.connectAddressHint,
            helperText: l10n.connectAddressHelp,
            errorText: addressError,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: label,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => onRegister(),
                decoration: InputDecoration(labelText: l10n.serverLabelField),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.icon(
                onPressed: busy ? null : onRegister,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.serverAdd),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(l10n.connectKnownServers, style: text.titleMedium),
            ),
            if (servers.isNotEmpty)
              Text(
                '${servers.length}',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (servers.isEmpty)
          Text(
            l10n.connectNoServers,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          _ServerGrid(
            servers: servers,
            activeServerId: activeServerId,
            onPick: onPick,
            onRemove: onRemove,
          ),
      ],
    );
  }
}

class _ServerGrid extends StatelessWidget {
  const _ServerGrid({
    required this.servers,
    required this.activeServerId,
    required this.onPick,
    required this.onRemove,
  });

  final List<ServerProfileView> servers;
  final String? activeServerId;
  final ValueChanged<ServerProfileView> onPick;
  final Future<void> Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 520 ? 2 : 1;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final server in servers)
              SizedBox(
                width: width,
                child: ServerCard(
                  profile: server,
                  online: server.id == activeServerId,
                  onPressed: () => onPick(server),
                  onRemove: () => onRemove(server.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 已登记服务器的卡片。默认只描边，悬停/聚焦才抬起高度，避免每张卡都长一样。
class ServerCard extends StatefulWidget {
  const ServerCard({
    required this.profile,
    required this.online,
    required this.onPressed,
    required this.onRemove,
    super.key,
  });

  final ServerProfileView profile;
  final bool online;
  final VoidCallback onPressed;
  final VoidCallback onRemove;

  @override
  State<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<ServerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final profile = widget.profile;
    final raised = _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: raised ? scheme.surfaceContainer : scheme.surfaceContainerLow,
        borderRadius: Radii.mediumAll,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: Radii.mediumAll,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: Radii.mediumAll,
              border: Border.all(
                color: widget.online ? scheme.primary : scheme.outline,
                width: widget.online ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                ServerMonogram(
                  id: profile.id,
                  label: profile.label,
                  host: profile.host,
                  size: 40,
                  online: widget.online,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${profile.host}:${profile.port}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (widget.online) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusDot(
                              color: context.status.live,
                              ringColor: scheme.surfaceContainerLow,
                              size: 8,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.sessionConnected,
                              style: text.labelSmall?.copyWith(
                                color: context.status.live,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.serverRemove,
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  onSelected: (_) => widget.onRemove(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      enabled: !widget.online,
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded, size: 18),
                          const SizedBox(width: 10),
                          Text(l10n.serverRemove),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 第二步：昵称，然后连接。连接目标只能来自档案，所以这里不再有地址输入。
class _NicknameStep extends StatelessWidget {
  const _NicknameStep({
    required this.profile,
    required this.nickname,
    required this.busy,
    required this.connected,
    required this.onBack,
    required this.onConnect,
    super.key,
  });

  final ServerProfileView profile;
  final TextEditingController nickname;
  final bool busy;
  final bool connected;
  final VoidCallback onBack;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox.square(
              dimension: 48,
              child: IconButton.filledTonal(
                tooltip: l10n.connectBack,
                onPressed: busy ? null : onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(width: 12),
            ServerMonogram(
              id: profile.id,
              label: profile.label,
              host: profile.host,
              size: 48,
              online: connected,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge,
                  ),
                  Text(
                    '${profile.host}:${profile.port}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        TextField(
          controller: nickname,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: busy ? null : (_) => onConnect(),
          decoration: InputDecoration(
            labelText: l10n.connectNicknameLabel,
            hintText: 'ts-client',
            helperText: l10n.connectNicknameHelp,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy || connected ? null : onConnect,
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      connected ? l10n.sessionConnected : l10n.connectAction,
                    ),
                    if (!connected) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.login_rounded, size: 18),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
