import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';

/// 最左侧的服务器栏：品牌标记、已登记的服务器、添加与设置。
///
/// 宽度固定 80：它是全局导航，不参与内容区的伸缩；品牌标记与设置按钮上下夹住
/// 服务器列表，扫视顺序稳定。设置放在最底部是用户明确要求的位置
/// （`设置按钮移动到左下角`），这样频道栏底部就留给了语音状态。
class ServerRail extends ConsumerWidget {
  const ServerRail({
    required this.onSelect,
    required this.onAdd,
    required this.onSettings,
    super.key,
  });

  static const width = 80.0;

  final ValueChanged<ServerProfileView> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final view = ref.watch(sessionViewProvider);

    // 抽屉里必须先收起再跳转：抽屉不属于路由栈，直接跳转会让旧页面的抽屉
    // 盖在新页面上。桌面没有打开中的抽屉，这一步是空操作。
    void runFromRail(VoidCallback action) {
      Scaffold.maybeOf(context)?.closeDrawer();
      action();
    }

    return ColoredBox(
      color: scheme.surfaceContainer,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Tooltip(
              message: l10n.appName,
              child: Container(
                width: Sizes.railTile,
                height: Sizes.railTile,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: Radii.largeAll,
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: 26,
                  color: scheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
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
                      onDisconnect: () => runFromRail(
                        () =>
                            ref.read(sessionViewProvider.notifier).disconnect(),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Tooltip(
                message: l10n.serverAdd,
                child: Material(
                  color: context.cardColor,
                  elevation: 1,
                  // 投影色交回 scheme.shadow，暗色下才画得出来。
                  shadowColor: scheme.shadow,
                  borderRadius: Radii.largeAll,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => runFromRail(onAdd),
                    child: SizedBox(
                      width: Sizes.railTile,
                      height: Sizes.railTile,
                      child: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
              child: SizedBox(
                width: Sizes.touch,
                height: Sizes.touch,
                child: IconButton(
                  tooltip: l10n.settingsTitle,
                  onPressed: () => runFromRail(onSettings),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  style: IconButton.styleFrom(
                    backgroundColor: context.cardColor,
                    foregroundColor: scheme.onSurfaceVariant,
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(Icons.settings_rounded),
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
  });

  final ServerProfileView server;

  /// 选中高亮：连接中/重连中也保持，锚定“当前目标”。
  final bool online;

  /// 已连上：侧边栏唯一的连接状态表达（右下角状态点）+ 右键菜单的开关。
  final bool connected;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    final monogram = serverMonogram(server.label, server.host);

    final tooltip = StringBuffer(
      '${server.label}\n${server.host}:${server.port}',
    );
    if (connected) {
      tooltip.write('\n${l10n.sessionConnected}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SecondaryMenu(
        enabled: connected,
        openOnSecondaryTap: true,
        items: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.logout_rounded),
            onPressed: onDisconnect,
            child: Text(l10n.serverDisconnect),
          ),
        ],
        builder: (context, menuController) => Tooltip(
          message: tooltip.toString(),
          waitDuration: const Duration(milliseconds: 400),
          child: Semantics(
            button: true,
            selected: online,
            excludeSemantics: true,
            label: '${server.label} · ${server.host}:${server.port}',
            child: InkWell(
              onTap: onTap,
              borderRadius: Radii.largeAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : Motion.effectsFast,
                          curve: Motion.effectsFastCurve,
                          width: 56,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: online
                                ? scheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: Radii.pillAll,
                          ),
                          child: Text(
                            monogram,
                            style: texts.labelLarge?.copyWith(
                              color: online
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (connected)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: StatusDot(
                              color: context.status.live,
                              ringColor: scheme.surfaceContainer,
                              size: 10,
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
                          fontWeight: online
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
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
