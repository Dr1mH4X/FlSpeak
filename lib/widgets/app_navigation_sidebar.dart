// 本文件来源于 FlClash（https://github.com/chen08209/FlClash）项目，原始许可证为 GPL-3.0。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7
// 对应原文件：lib/ui/sidebar.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'shape.dart';
import 'view_scope.dart';
import 'window_header.dart';

const double _compactWidth = 48.0;
const double _expandedWidth = 220.0;
const double _itemSize = 40.0;
const double _itemGap = 4.0;
const double _toggleGap = 8.0;
const double _verticalInset = 4.0;
const double _maxSideInset = 12.0;
const double _iconSize = 24.0;
const double _labelGap = 12.0;
const double _indicatorWidth = 3.0;
const double _indicatorHeight = 16.0;
const Duration _expandDuration = Duration(milliseconds: 250);
final _itemShape = AppShape.all(10);

enum AppNavDestination { home, server, settings }

/// 全局常驻侧边栏：
/// - 尺寸对齐 FlClash：项高 40px、图标 24px、间距 4px、展开 220px；
/// - 收起宽度动态计算：math.max(48.0, windowControls.width)（macOS 避让红绿灯时为 78px，无红绿灯时为 48px）；
/// - 展开交互：宽屏下就地展开/收起；窄屏或空间受限时通过 OverlayPortal 浮层弹出展开。
class AppNavigationSidebar extends ConsumerStatefulWidget {
  const AppNavigationSidebar({
    required this.selectedDestination,
    this.activeServerId,
    this.windowControls,
    super.key,
  });

  static const double compactWidth = _compactWidth;
  static const double expandedWidth = _expandedWidth;

  static double compactWidthOf(BuildContext context) {
    final windowControls = ViewScope.windowControlsOf(context);
    return math.max(_compactWidth, windowControls.width);
  }

  final AppNavDestination selectedDestination;
  final String? activeServerId;
  final Size? windowControls;

  @override
  ConsumerState<AppNavigationSidebar> createState() =>
      _AppNavigationSidebarState();
}

class _AppNavigationSidebarState extends ConsumerState<AppNavigationSidebar>
    with SingleTickerProviderStateMixin {
  static bool _globalExpanded = false;

  final _overlayController = OverlayPortalController();
  late final AnimationController _overlayExpansion = AnimationController(
    vsync: this,
    duration: _expandDuration,
  );
  late final CurvedAnimation _overlayProgress = CurvedAnimation(
    parent: _overlayExpansion,
    curve: Easing.standard,
  );

  @override
  void dispose() {
    _overlayProgress.dispose();
    _overlayExpansion.dispose();
    super.dispose();
  }

  void _hideIfDismissed() {
    if (mounted && _overlayExpansion.isDismissed) {
      _overlayController.hide();
    }
  }

  void _closeOverlay() {
    _overlayExpansion.reverse().whenCompleteOrCancel(_hideIfDismissed);
  }

  void _handleToggle({required bool canExpandInPlace}) {
    if (canExpandInPlace) {
      setState(() {
        _globalExpanded = !_globalExpanded;
      });
    } else if (_overlayExpansion.isForwardOrCompleted) {
      _closeOverlay();
    } else {
      _overlayController.show();
      _overlayExpansion.forward();
    }
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

  Future<void> _changeServerIcon(ServerProfileView server) async {
    final current =
        ref.read(preferencesProvider).serverIcons[server.id] ??
        ServerIcon.community;
    final icon = await showServerIconPicker(context, current);
    if (context.mounted && icon != null) {
      ref.read(preferencesProvider.notifier).setServerIcon(server.id, icon);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(sessionViewProvider);
    final scheme = context.scheme;
    final windowControls =
        widget.windowControls ?? ViewScope.windowControlsOf(context);
    final canExpandInPlace = !context.isCompact;
    final safePadding = MediaQuery.paddingOf(context);

    Widget buildSidebarPane(double progress, {required bool isOverlay}) {
      return _SidebarPane(
        progress: progress,
        windowControls: windowControls,
        expanded: isOverlay ? true : _globalExpanded,
        selectedDestination: widget.selectedDestination,
        activeServerId: widget.activeServerId ?? view.activeServerId,
        servers: view.servers,
        connectedServerId: view.connected ? view.activeServerId : null,
        isConnectingOrReconnecting: view.connecting || view.reconnecting,
        busy: view.busy || view.connecting || view.reconnecting,
        onToggle: () => _handleToggle(canExpandInPlace: canExpandInPlace),
        onHome: () {
          if (isOverlay) _closeOverlay();
          if (widget.selectedDestination != AppNavDestination.home) {
            context.go(AppRoutes.connect);
          }
        },
        onAddServer: () {
          if (isOverlay) _closeOverlay();
          _openAddServer();
        },
        onSettings: () {
          if (isOverlay) _closeOverlay();
          if (widget.selectedDestination != AppNavDestination.settings) {
            context.push(AppRoutes.settings);
          }
        },
        onConnectServer: (server) {
          if (isOverlay) _closeOverlay();
          _connect(server);
        },
        onDisconnectServer: () async {
          await ref.read(sessionViewProvider.notifier).disconnect();
        },
        onChangeServerIcon: (server) => _changeServerIcon(server),
      );
    }

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlayController,
      overlayChildBuilder: (context, info) {
        return _SidebarOverlay(
          anchor: MatrixUtils.transformRect(
            info.childPaintTransform,
            Offset.zero & info.childSize,
          ),
          overlayWidth: info.overlaySize.width,
          progress: _overlayProgress,
          onDismiss: _closeOverlay,
          builder: (progress) => Padding(
            padding: safePadding,
            child: buildSidebarPane(progress, isOverlay: true),
          ),
        );
      },
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: BorderDirectional(
          end: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: (canExpandInPlace && _globalExpanded) ? 1.0 : 0.0),
          duration: _expandDuration,
          curve: Easing.standard,
          builder: (context, progress, _) =>
              buildSidebarPane(progress, isOverlay: false),
        ),
      ),
    );
  }
}

class _SidebarColors {
  _SidebarColors(ColorScheme scheme)
    : selectedFill = scheme.onSurface.withValues(alpha: 0.08),
      label = scheme.onSurface,
      icon = scheme.onSurfaceVariant,
      indicator = scheme.primary,
      overlay = WidgetStateProperty.fromMap({
        WidgetState.pressed: scheme.onSurface.withValues(alpha: 0.06),
        WidgetState.focused: scheme.onSurface.withValues(alpha: 0.1),
        WidgetState.hovered: scheme.onSurface.withValues(alpha: 0.04),
        WidgetState.any: Colors.transparent,
      });

  final Color selectedFill;
  final Color label;
  final Color icon;
  final Color indicator;
  final WidgetStateProperty<Color> overlay;
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.colors,
    required this.height,
    required this.sideInset,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.semanticLabel,
    this.onSecondaryTap,
    this.onLongPress,
  });

  final _SidebarColors colors;
  final double height;
  final double sideInset;
  final bool selected;
  final String? semanticLabel;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sideInset,
        vertical: _itemGap / 2,
      ),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        label: semanticLabel,
        child: Material(
          color: selected ? colors.selectedFill : Colors.transparent,
          shape: _itemShape,
          child: InkWell(
            onTap: onTap,
            onSecondaryTap: onSecondaryTap,
            onLongPress: onLongPress,
            customBorder: _itemShape,
            mouseCursor: SystemMouseCursors.basic,
            splashFactory: NoSplash.splashFactory,
            overlayColor: colors.overlay,
            child: IconTheme.merge(
              data: IconThemeData(size: _iconSize, color: colors.icon),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    if (selected)
                      PositionedDirectional(
                        start: 0,
                        top: (height - _indicatorHeight) / 2,
                        width: _indicatorWidth,
                        height: _indicatorHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: colors.indicator,
                              shape: AppShape.full,
                            ),
                          ),
                        ),
                      ),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarPane extends StatelessWidget {
  const _SidebarPane({
    required this.progress,
    required this.windowControls,
    required this.expanded,
    required this.selectedDestination,
    required this.activeServerId,
    required this.servers,
    required this.connectedServerId,
    required this.isConnectingOrReconnecting,
    required this.busy,
    required this.onToggle,
    required this.onHome,
    required this.onAddServer,
    required this.onSettings,
    required this.onConnectServer,
    required this.onDisconnectServer,
    required this.onChangeServerIcon,
  });

  final double progress;
  final Size windowControls;
  final bool expanded;
  final AppNavDestination selectedDestination;
  final String? activeServerId;
  final List<ServerProfileView> servers;
  final String? connectedServerId;
  final bool isConnectingOrReconnecting;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onHome;
  final VoidCallback onAddServer;
  final VoidCallback onSettings;
  final ValueChanged<ServerProfileView> onConnectServer;
  final VoidCallback onDisconnectServer;
  final void Function(ServerProfileView server) onChangeServerIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final colors = _SidebarColors(scheme);
    final labelOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);

    final compactWidth = math.max(_compactWidth, windowControls.width);
    final sideInset = math.min(_maxSideInset, (compactWidth - _itemSize) / 2);
    final itemWidth = compactWidth - sideInset * 2;
    final iconInset = (itemWidth - _iconSize) / 2;
    final rowWidth = _expandedWidth - sideInset * 2;
    final currentWidth = lerpDouble(compactWidth, _expandedWidth, progress)!;

    return SizedBox(
      width: currentWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 窗口避让区
          if (windowControls.height > 0)
            SizedBox(
              height: windowControls.height + _verticalInset,
              child: const WindowDragRegion(child: SizedBox.expand()),
            )
          else
            const SizedBox(height: _verticalInset),

          // 2. 折叠/展开按钮
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _SidebarButton(
              colors: colors,
              height: _itemSize,
              sideInset: sideInset,
              semanticLabel: expanded ? '收起侧边栏' : '展开侧边栏',
              onTap: onToggle,
              child: SizedBox(
                width: itemWidth,
                child: Center(
                  child: Icon(
                    expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                    size: _iconSize,
                    color: colors.icon,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: _toggleGap),

          // 3. 首页导航项
          _SidebarButton(
            colors: colors,
            height: _itemSize,
            sideInset: sideInset,
            selected: selectedDestination == AppNavDestination.home,
            semanticLabel: l10n.homeTitle,
            onTap: onHome,
            child: _SidebarNavRow(
              icon: selectedDestination == AppNavDestination.home
                  ? Icons.home_rounded
                  : Icons.home_outlined,
              label: l10n.homeTitle,
              selected: selectedDestination == AppNavDestination.home,
              width: rowWidth,
              iconInset: iconInset,
              labelOpacity: labelOpacity,
              colors: colors,
            ),
          ),

          // 4. 分割线
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: math.max(6.0, sideInset + 2),
              vertical: 4,
            ),
            child: Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),

          // 5. 服务器列表（中间滚动区）
          Expanded(
            child: servers.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      final isSelected =
                          selectedDestination == AppNavDestination.server &&
                          (activeServerId == server.id);
                      final isConnected = connectedServerId == server.id;
                      final isLoading =
                          activeServerId == server.id &&
                          isConnectingOrReconnecting;

                      return _SidebarServerTile(
                        server: server,
                        selected: isSelected,
                        connected: isConnected,
                        loading: isLoading,
                        itemWidth: itemWidth,
                        rowWidth: rowWidth,
                        iconInset: iconInset,
                        sideInset: sideInset,
                        labelOpacity: labelOpacity,
                        colors: colors,
                        onTap: busy ? null : () => onConnectServer(server),
                        onDisconnect: onDisconnectServer,
                        onChangeIcon: () => onChangeServerIcon(server),
                      );
                    },
                  ),
          ),

          // 6. 添加服务器项
          _SidebarButton(
            colors: colors,
            height: _itemSize,
            sideInset: sideInset,
            semanticLabel: l10n.serverAdd,
            onTap: onAddServer,
            child: _SidebarNavRow(
              icon: Icons.add_rounded,
              label: l10n.serverAdd,
              selected: false,
              width: rowWidth,
              iconInset: iconInset,
              labelOpacity: labelOpacity,
              colors: colors,
            ),
          ),

          // 7. 设置项
          _SidebarButton(
            colors: colors,
            height: _itemSize,
            sideInset: sideInset,
            selected: selectedDestination == AppNavDestination.settings,
            semanticLabel: l10n.settingsTitle,
            onTap: onSettings,
            child: _SidebarNavRow(
              icon: selectedDestination == AppNavDestination.settings
                  ? Icons.settings_rounded
                  : Icons.settings_outlined,
              label: l10n.settingsTitle,
              selected: selectedDestination == AppNavDestination.settings,
              width: rowWidth,
              iconInset: iconInset,
              labelOpacity: labelOpacity,
              colors: colors,
            ),
          ),
          const SizedBox(height: _verticalInset + 4),
        ],
      ),
    );
  }
}

class _SidebarNavRow extends StatelessWidget {
  const _SidebarNavRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.width,
    required this.iconInset,
    required this.labelOpacity,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double width;
  final double iconInset;
  final double labelOpacity;
  final _SidebarColors colors;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: width,
        maxWidth: width,
        child: Row(
          children: [
            SizedBox(width: iconInset),
            Icon(
              icon,
              size: _iconSize,
              color: selected ? colors.indicator : colors.icon,
            ),
            const SizedBox(width: _labelGap),
            Expanded(
              child: Opacity(
                opacity: labelOpacity,
                alwaysIncludeSemantics: true,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    color: colors.label,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _labelGap),
          ],
        ),
      ),
    );
  }
}

class _SidebarServerTile extends StatelessWidget {
  const _SidebarServerTile({
    required this.server,
    required this.selected,
    required this.connected,
    required this.loading,
    required this.itemWidth,
    required this.rowWidth,
    required this.iconInset,
    required this.sideInset,
    required this.labelOpacity,
    required this.colors,
    required this.onTap,
    required this.onDisconnect,
    required this.onChangeIcon,
  });

  final ServerProfileView server;
  final bool selected;
  final bool connected;
  final bool loading;
  final double itemWidth;
  final double rowWidth;
  final double iconInset;
  final double sideInset;
  final double labelOpacity;
  final _SidebarColors colors;
  final VoidCallback? onTap;
  final VoidCallback onDisconnect;
  final VoidCallback onChangeIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SecondaryMenu(
      openOnSecondaryTap: true,
      items: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.palette_outlined),
          onPressed: onChangeIcon,
          child: Text(l10n.serverIconChange),
        ),
        if (connected)
          MenuItemButton(
            leadingIcon: const Icon(Icons.logout_rounded),
            onPressed: onDisconnect,
            child: Text(l10n.serverDisconnect),
          ),
      ],
      builder: (context, menuController) => _SidebarButton(
        colors: colors,
        height: _itemSize,
        sideInset: sideInset,
        selected: selected,
        semanticLabel: '${server.label} · ${server.host}:${server.port}',
        onTap: () => onTap?.call(),
        onSecondaryTap: menuController.open,
        onLongPress: menuController.open,
        child: _SidebarServerRow(
          server: server,
          selected: selected,
          connected: connected,
          loading: loading,
          width: rowWidth,
          itemWidth: itemWidth,
          labelOpacity: labelOpacity,
          colors: colors,
        ),
      ),
    );
  }
}

class _SidebarServerRow extends StatelessWidget {
  const _SidebarServerRow({
    required this.server,
    required this.selected,
    required this.connected,
    required this.loading,
    required this.width,
    required this.itemWidth,
    required this.labelOpacity,
    required this.colors,
  });

  final ServerProfileView server;
  final bool selected;
  final bool connected;
  final bool loading;
  final double width;
  final double itemWidth;
  final double labelOpacity;
  final _SidebarColors colors;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: width,
        maxWidth: width,
        child: Row(
          children: [
            SizedBox(
              width: itemWidth,
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
            const SizedBox(width: _labelGap),
            Expanded(
              child: Opacity(
                opacity: labelOpacity,
                alwaysIncludeSemantics: true,
                child: Text(
                  server.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    color: colors.label,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _labelGap),
          ],
        ),
      ),
    );
  }
}

class _SidebarOverlay extends StatelessWidget {
  const _SidebarOverlay({
    required this.anchor,
    required this.overlayWidth,
    required this.progress,
    required this.onDismiss,
    required this.builder,
  });

  final Rect anchor;
  final double overlayWidth;
  final Animation<double> progress;
  final VoidCallback onDismiss;
  final Widget Function(double progress) builder;

  @override
  Widget build(BuildContext context) {
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    final scheme = context.scheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: isLtr ? anchor.left : null,
          right: isLtr ? null : overlayWidth - anchor.right,
          top: anchor.top,
          height: anchor.height,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    onDismiss();
                    return null;
                  },
                ),
              },
              child: FocusScope(
                autofocus: true,
                child: Material(
                  color: scheme.surfaceContainerLowest,
                  shape: BorderDirectional(
                    end: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  elevation: 8,
                  shadowColor: scheme.shadow,
                  child: AnimatedBuilder(
                    animation: progress,
                    builder: (_, _) => builder(progress.value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
