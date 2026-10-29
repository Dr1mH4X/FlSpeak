import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/providers.dart';
import '../../../core/server_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import '../../../widgets/server_icon_picker.dart';
import '../../../widgets/view_scope.dart';
import '../../../widgets/window_header.dart';

/// Discord 式服务器栏：顶部社区入口、服务器磁贴与底部设置。
class ServerRail extends ConsumerWidget {
  const ServerRail({
    required this.onSelect,
    required this.onAdd,
    required this.onSettings,
    required this.onDisconnect,
    this.onHome,
    this.homeSelected = false,
    super.key,
  });

  static const width = 80.0;

  final ValueChanged<ServerProfileView> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onSettings;
  final VoidCallback? onHome;
  final bool homeSelected;

  /// 断开当前连接；外壳负责断开后回到服务器列表。
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final view = ref.watch(sessionViewProvider);
    // 宽屏时红绿灯压在轨道左上角，列表整体让到 32px 之下；
    // 窄屏与全屏由标题条或系统接管，保持原来的 16px。
    final windowControls = ViewScope.windowControlsOf(context);

    // 抽屉里必须先收起再跳转：抽屉不属于路由栈，直接跳转会让旧页面的抽屉
    // 盖在新页面上。桌面没有打开中的抽屉，这一步是空操作。
    void runFromRail(VoidCallback action) {
      Scaffold.maybeOf(context)?.closeDrawer();
      action();
    }

    return Material(
      color: scheme.surfaceContainerLowest,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            WindowDragRegion(
              child: SizedBox(
                width: double.infinity,
                height: windowControls.isEmpty ? 16 : windowControls.height + 4,
              ),
            ),
            Semantics(
              button: true,
              selected: homeSelected,
              label: l10n.homeTitle,
              excludeSemantics: true,
              onTap: () => runFromRail(onHome ?? onAdd),
              child: InkWell(
                onTap: () => runFromRail(onHome ?? onAdd),
                borderRadius: Radii.largeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Ink(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: homeSelected
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHigh,
                          borderRadius: Radii.largeAll,
                        ),
                        child: Icon(
                          homeSelected
                              ? Icons.home_rounded
                              : Icons.home_outlined,
                          color: homeSelected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 48,
                        child: Text(
                          l10n.homeTitle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelSmall?.copyWith(
                            color: homeSelected
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Divider(color: scheme.outlineVariant),
            ),
            Expanded(
              child: ListView.builder(
                // 底部 12 把最后一个服务器与下面的添加槽位分开：列表结束 /
                // 空槽 / chrome 三段各自断开。
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                itemCount: view.servers.length,
                itemBuilder: (context, index) {
                  final server = view.servers[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ServerTile(
                      server: server,
                      online: server.id == view.activeServerId,
                      connected:
                          view.connected && server.id == view.activeServerId,
                      onTap: () => runFromRail(() => onSelect(server)),
                      onDisconnect: () => runFromRail(onDisconnect),
                      loading:
                          server.id == view.activeServerId &&
                          (view.connecting || view.reconnecting),
                      onChangeIcon: () async {
                        final current =
                            ref
                                .read(preferencesProvider)
                                .serverIcons[server.id] ??
                            ServerIcon.community;
                        final icon = await showServerIconPicker(
                          context,
                          current,
                        );
                        if (icon != null) {
                          ref
                              .read(preferencesProvider.notifier)
                              .setServerIcon(server.id, icon);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // 空槽位：与服务器磁贴同几何（48 / r16），不描边、不填充，
              // 识别落在 20px 的 + 图标上（rail 上 5.24:1 / 9.31:1）。
              child: IconButton(
                onPressed: () => runFromRail(onAdd),
                icon: Icon(Icons.add_rounded, semanticLabel: l10n.serverAdd),
                style: ButtonStyle(
                  // 键盘焦点仍需可见：2px primary 环，未聚焦时同宽全透明。
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      width: 2,
                      color: states.contains(WidgetState.focused)
                          ? scheme.primary
                          : Colors.transparent,
                    ),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: Radii.largeAll),
                  ),
                  backgroundColor: WidgetStatePropertyAll(
                    scheme.secondaryContainer,
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    scheme.onSecondaryContainer,
                  ),
                  // M3 state layer：hover 8%、press 12%，不换底色。
                  overlayColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.pressed)
                        ? scheme.onSurface.withValues(alpha: 0.12)
                        : states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.focused)
                        ? scheme.onSurface.withValues(alpha: 0.08)
                        : Colors.transparent,
                  ),
                  iconSize: const WidgetStatePropertyAll(20),
                  fixedSize: const WidgetStatePropertyAll(
                    Size(Sizes.railTile, Sizes.railTile),
                  ),
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
              // 连接页与工作区共享同一个设置入口。
              child: IconButton(
                onPressed: () => runFromRail(onSettings),
                iconSize: IconSizes.toolbar,
                color: scheme.onSurfaceVariant,
                style: IconButton.styleFrom(
                  minimumSize: const Size(Sizes.touch, Sizes.touch),
                  maximumSize: const Size(Sizes.touch, Sizes.touch),
                  padding: EdgeInsets.zero,
                  overlayColor: scheme.onSurfaceVariant,
                ),
                icon: Icon(
                  Icons.settings_rounded,
                  semanticLabel: l10n.settingsTitle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.online,
    required this.connected,
    required this.onTap,
    required this.onDisconnect,
    required this.onChangeIcon,
    required this.loading,
  });

  final ServerProfileView server;

  /// 选中高亮：连接中/重连中也保持，锚定“当前目标”。
  final bool online;

  /// 已连上：侧边栏唯一的连接状态表达（右下角状态点）+ 右键菜单的开关。
  final bool connected;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;
  final VoidCallback onChangeIcon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;

    final semanticsLabel = StringBuffer(
      '${server.label} · ${server.host}:${server.port}',
    );
    if (connected) {
      semanticsLabel.write(' · ${l10n.sessionConnected}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SecondaryMenu(
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
        builder: (context, menuController) => Semantics(
          button: true,
          selected: online,
          excludeSemantics: true,
          label: semanticsLabel.toString(),
          // `excludeSemantics` 会丢掉 InkWell 的点击动作，必须在这里补回来；
          // 否则读屏用户听到「按钮」却无法选中服务器。
          onTap: onTap,
          customSemanticsActions: connected
              ? {
                  CustomSemanticsAction(label: l10n.serverDisconnect):
                      onDisconnect,
                }
              : null,
          child: InkWell(
            onTap: onTap,
            // 触屏没有右键：长按打开同一个断开菜单。
            onLongPress: menuController.open,
            borderRadius: Radii.largeAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ServerBadge(
                        id: server.id,
                        size: 48,
                        selected: online,
                        loading: loading,
                        online: connected,
                      ),
                      if (online)
                        Positioned(
                          left: -16,
                          top: 10,
                          bottom: 10,
                          child: Container(
                            width: 4,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: Radii.pillAll,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 64,
                    child: Text(
                      server.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: texts.labelSmall?.copyWith(
                        fontSize: 11,
                        color: online
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: online ? FontWeight.w600 : FontWeight.w500,
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
}
