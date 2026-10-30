import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/server_icon.dart';
import '../features/connect/widgets/add_server_dialog.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'monogram.dart';
import 'server_icon_picker.dart';
import 'view_scope.dart';
import 'window_header.dart';

const double _compactWidth = Sizes.rail;
const double _expandedWidth = 200.0;
const double _itemSize = 38.0;
const double _itemGap = 6.0;
const double _indicatorWidth = 3.0;
const double _indicatorHeight = 16.0;
const Duration _expandDuration = Duration(milliseconds: 240);

enum AppNavDestination { home, server, settings }

/// 全局常驻侧边栏：收窄态 80px（完全包裹 macOS 78px 红绿灯），展开态 200px。
/// 顺序：顶部（macOS 避让 / 折叠展开）-> 首页 -> 服务器列表（纯自定义图标）-> 弹性空白 -> 添加服务器 -> 设置 -> 底部。
class AppNavigationSidebar extends ConsumerStatefulWidget {
  const AppNavigationSidebar({
    required this.selectedDestination,
    this.activeServerId,
    super.key,
  });

  static const double compactWidth = _compactWidth;
  static const double expandedWidth = _expandedWidth;

  final AppNavDestination selectedDestination;
  final String? activeServerId;

  @override
  ConsumerState<AppNavigationSidebar> createState() =>
      _AppNavigationSidebarState();
}

class _AppNavigationSidebarState extends ConsumerState<AppNavigationSidebar> {
  static bool _globalExpanded = false;

  void _toggleExpand() {
    setState(() {
      _globalExpanded = !_globalExpanded;
    });
  }

  Future<void> _connect(ServerProfileView profile) async {
    final view = ref.read(sessionViewProvider);
    if (view.connected && view.activeServerId == profile.id) {
      if (context.mounted) {
        context.go(AppRoutes.workspace);
      }
      return;
    }
    if (view.busy || view.connecting || view.reconnecting) return;

    final ok = await ref
        .read(sessionViewProvider.notifier)
        .connect(
          id: profile.id,
          nickname: ref.read(preferencesProvider).nickname,
        );
    if (!mounted) return;
    if (ok) {
      ref
          .read(preferencesProvider.notifier)
          .markConnected(profile.id, DateTime.now());
      context.go(AppRoutes.workspace);
    }
  }

  Future<void> _openAddServer() async {
    final profile = await showAddServerDialog(context);
    if (profile != null && mounted) {
      await _connect(profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final view = ref.watch(sessionViewProvider);
    final windowControls = ViewScope.windowControlsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: _globalExpanded ? 1.0 : 0.0),
      duration: _expandDuration,
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        final currentWidth = lerpDouble(
          _compactWidth,
          _expandedWidth,
          progress,
        )!;
        final labelOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);

        return Material(
          color: scheme.surfaceContainerLowest,
          shape: BorderDirectional(
            end: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: SizedBox(
            width: currentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 顶部避让与折叠/展开按钮
                if (windowControls.height > 0)
                  const WindowDragRegion(child: SizedBox(height: Sizes.header)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Semantics(
                    button: true,
                    label: _globalExpanded ? '收起侧边栏' : '展开侧边栏',
                    child: InkWell(
                      borderRadius: Radii.mediumAll,
                      onTap: _toggleExpand,
                      child: SizedBox(
                        height: _itemSize,
                        child: Row(
                          children: [
                            SizedBox(
                              width: _compactWidth - 10,
                              child: Center(
                                child: Icon(
                                  _globalExpanded
                                      ? Icons.menu_open_rounded
                                      : Icons.menu_rounded,
                                  size: IconSizes.toolbar,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 2. 首页项
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _SidebarNavButton(
                    icon: widget.selectedDestination == AppNavDestination.home
                        ? Icons.home_rounded
                        : Icons.home_outlined,
                    label: l10n.homeTitle,
                    selected:
                        widget.selectedDestination == AppNavDestination.home,
                    labelOpacity: labelOpacity,
                    onTap: () {
                      if (widget.selectedDestination !=
                          AppNavDestination.home) {
                        context.go(AppRoutes.connect);
                      }
                    },
                  ),
                ),

                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),

                // 3. 服务器列表（仅显示自定义图标，无服务器名称文字）
                Expanded(
                  child: view.servers.isEmpty
                      ? const SizedBox.shrink()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          itemCount: view.servers.length,
                          itemBuilder: (context, index) {
                            final server = view.servers[index];
                            final isCurrent =
                                widget.selectedDestination ==
                                    AppNavDestination.server &&
                                (widget.activeServerId == server.id ||
                                    view.activeServerId == server.id);
                            final connected =
                                view.connected &&
                                view.activeServerId == server.id;
                            final loading =
                                server.id == view.activeServerId &&
                                (view.connecting || view.reconnecting);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: _itemGap),
                              child: _SidebarServerTile(
                                server: server,
                                selected: isCurrent,
                                connected: connected,
                                loading: loading,
                                labelOpacity: labelOpacity,
                                onTap:
                                    view.busy ||
                                        view.connecting ||
                                        view.reconnecting
                                    ? null
                                    : () => _connect(server),
                                onDisconnect: () async {
                                  await ref
                                      .read(sessionViewProvider.notifier)
                                      .disconnect();
                                },
                              ),
                            );
                          },
                        ),
                ),

                // 4. 弹性间隔之后的操作项
                // 5. 添加服务器项
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _SidebarNavButton(
                    icon: Icons.add_rounded,
                    label: l10n.serverAdd,
                    selected: false,
                    labelOpacity: labelOpacity,
                    onTap: _openAddServer,
                  ),
                ),
                const SizedBox(height: 6),

                // 6. 设置项
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _SidebarNavButton(
                    icon:
                        widget.selectedDestination == AppNavDestination.settings
                        ? Icons.settings_rounded
                        : Icons.settings_outlined,
                    label: l10n.settingsTitle,
                    selected:
                        widget.selectedDestination ==
                        AppNavDestination.settings,
                    labelOpacity: labelOpacity,
                    onTap: () {
                      if (widget.selectedDestination !=
                          AppNavDestination.settings) {
                        context.push(AppRoutes.settings);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarNavButton extends StatelessWidget {
  const _SidebarNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.labelOpacity,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double labelOpacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: Radii.mediumAll,
        onTap: onTap,
        child: Container(
          height: _itemSize,
          decoration: BoxDecoration(
            color: selected
                ? scheme.secondaryContainer.withValues(alpha: 0.8)
                : Colors.transparent,
            borderRadius: Radii.mediumAll,
          ),
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: (_itemSize - _indicatorHeight) / 2,
                  child: Container(
                    width: _indicatorWidth,
                    height: _indicatorHeight,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              Row(
                children: [
                  SizedBox(
                    width: _compactWidth - 10,
                    child: Center(
                      child: Icon(
                        icon,
                        size: IconSizes.toolbar,
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (labelOpacity > 0.05)
                    Expanded(
                      child: Opacity(
                        opacity: labelOpacity,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: texts.bodyMedium?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: selected
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarServerTile extends ConsumerWidget {
  const _SidebarServerTile({
    required this.server,
    required this.selected,
    required this.connected,
    required this.loading,
    required this.labelOpacity,
    required this.onTap,
    required this.onDisconnect,
  });

  final ServerProfileView server;
  final bool selected;
  final bool connected;
  final bool loading;
  final double labelOpacity;
  final VoidCallback? onTap;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return SecondaryMenu(
      openOnSecondaryTap: true,
      items: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.palette_outlined),
          onPressed: () async {
            final current =
                ref.read(preferencesProvider).serverIcons[server.id] ??
                ServerIcon.community;
            final icon = await showServerIconPicker(context, current);
            if (context.mounted && icon != null) {
              ref
                  .read(preferencesProvider.notifier)
                  .setServerIcon(server.id, icon);
            }
          },
          child: Text(l10n.serverIconChange),
        ),
        if (connected)
          MenuItemButton(
            leadingIcon: const Icon(Icons.logout_rounded),
            onPressed: onDisconnect,
            child: Text(l10n.serverDisconnect),
          ),
      ],
      builder: (context, menuController) => Semantics(
        button: true,
        selected: selected,
        label: '${server.label} · ${server.host}:${server.port}',
        child: InkWell(
          borderRadius: Radii.mediumAll,
          onTap: onTap,
          onLongPress: menuController.open,
          child: Container(
            height: _itemSize,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.secondaryContainer.withValues(alpha: 0.6)
                  : Colors.transparent,
              borderRadius: Radii.mediumAll,
            ),
            child: Stack(
              children: [
                if (selected)
                  Positioned(
                    left: 0,
                    top: (_itemSize - _indicatorHeight) / 2,
                    child: Container(
                      width: _indicatorWidth,
                      height: _indicatorHeight,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    SizedBox(
                      width: _compactWidth - 10,
                      child: Center(
                        child: ServerBadge(
                          id: server.id,
                          size: 32,
                          selected: selected,
                          loading: loading,
                          online: connected,
                        ),
                      ),
                    ),
                    if (labelOpacity > 0.05)
                      Expanded(
                        child: Opacity(
                          opacity: labelOpacity,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              server.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodyMedium?.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: selected
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
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
