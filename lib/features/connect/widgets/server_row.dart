import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/server_icon.dart';
import '../../../widgets/server_icon_picker.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import 'relative_time.dart';
import '../../../widgets/press_feedback.dart';

/// 连接页的一行服务器：整行是主落点，右键弹统一的二级菜单放「从列表移除」。
///
/// 连接中整行变暗（除了正在连接的那行），避免用户连点两个目标。
class ServerRow extends ConsumerStatefulWidget {
  const ServerRow({
    required this.profile,
    required this.lastConnected,
    required this.connected,
    required this.connecting,
    required this.enabled,
    required this.onTap,
    required this.onRemove,
    super.key,
  });

  final ServerProfileView profile;
  final DateTime? lastConnected;
  final bool connected;
  final bool connecting;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  ConsumerState<ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends ConsumerState<ServerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    final connected = widget.connected;
    final active = widget.enabled || connected || widget.connecting;
    // 640 以下把「上次连接」让位给服务器名，否则窄屏只剩省略号。
    final narrow = MediaQuery.sizeOf(context).width < 640;
    final showLastConnected = !narrow;
    // M3 effects default：行状态（高亮、整行降透明度）都是颜色/透明度动画。
    final animations = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.effectsDefault;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SecondaryMenu(
        openOnSecondaryTap: true,
        items: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.palette_outlined),
            onPressed: () async {
              final current =
                  ref
                      .read(preferencesProvider)
                      .serverIcons[widget.profile.id] ??
                  ServerIcon.community;
              final icon = await showServerIconPicker(context, current);
              if (icon != null) {
                ref
                    .read(preferencesProvider.notifier)
                    .setServerIcon(widget.profile.id, icon);
              }
            },
            child: Text(l10n.serverIconChange),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.delete_rounded),
            onPressed: connected ? null : widget.onRemove,
            child: Text(l10n.serverRemoveFromList),
          ),
        ],
        builder: (context, menuController) => AnimatedContainer(
          duration: animations,
          curve: Motion.effectsDefaultCurve,
          color: connected
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  enabled: active,
                  child: AnimatedInkWell(
                    onTap: widget.enabled ? widget.onTap : null,
                    // M3 state layer：hover 是 onSurface 8%，不再自定底色。
                    hoverColor: scheme.onSurface.withValues(alpha: 0.08),
                    child: AnimatedOpacity(
                      duration: animations,
                      curve: Motion.effectsDefaultCurve,
                      opacity: active ? 1 : 0.5,
                      child: Padding(
                        // 与身份卡的内容缩进（20）对齐，两卡头像才能落在同一条线上。
                        padding: EdgeInsets.fromLTRB(
                          narrow ? 16 : 20,
                          12,
                          !connected && !widget.connecting ? 4 : 20,
                          12,
                        ),
                        child: Row(
                          children: [
                            ServerBadge(
                              id: widget.profile.id,
                              size: 44,
                              online: connected,
                              selected: connected,
                              loading: widget.connecting,
                            ),
                            SizedBox(width: narrow ? 12 : 16),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.profile.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: texts.titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${widget.profile.host}:${widget.profile.port}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: texts.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontFeatures: tabularFigures,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (widget.connecting)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.sessionConnecting,
                                    style: texts.labelMedium?.copyWith(
                                      fontSize: 12,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              )
                            else if (connected)
                              _ConnectedChip(label: l10n.sessionConnected)
                            else if (showLastConnected)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: Text(
                                  lastConnectedLabel(
                                    context,
                                    widget.lastConnected,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: texts.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            // hover 反馈按 M3 归到 effects fast：nudge 只有 2px，
                            // 用 slow 的 spatial 档反而拖沓。
                            AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : Motion.effectsFast,
                              curve: Motion.effectsFastCurve,
                              transform: Matrix4.translationValues(
                                _hovered && active ? 2 : 0,
                                0,
                                0,
                              ),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: connected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 右键菜单在触屏和键盘上不可达；这里给出同一条目的可见入口。
              if (!connected && !widget.connecting)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    onPressed: menuController.open,
                    iconSize: 18,
                    color: scheme.onSurfaceVariant,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(Sizes.touch, Sizes.touch),
                      maximumSize: const Size(Sizes.touch, Sizes.touch),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      semanticLabel: MaterialLocalizations.of(context)
                          .showMenuTooltip,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedChip extends StatelessWidget {
  const _ConnectedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: Radii.pillAll,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: context.isDark ? 0.24 : 0.08,
            ),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(
            color: context.status.live,
            ringColor: context.cardColor,
            size: 6,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
