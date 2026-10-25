import 'package:flutter/material.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import 'relative_time.dart';

/// 连接页的一行服务器：整行是主落点，右键弹统一的二级菜单放「从列表移除」。
///
/// 连接中整行变暗（除了正在连接的那行），避免用户连点两个目标。
class ServerRow extends StatefulWidget {
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
  State<ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<ServerRow> {
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
    final animations = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SecondaryMenu(
        openOnSecondaryTap: true,
        items: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.delete_outline_rounded),
            onPressed: connected ? null : widget.onRemove,
            child: Text(l10n.serverRemoveFromList),
          ),
        ],
        builder: (context, menuController) => ColoredBox(
          color: connected
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          child: Semantics(
            button: true,
            enabled: active,
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              hoverColor: scheme.surfaceContainer.withValues(alpha: 0.7),
              child: Opacity(
                opacity: active ? 1 : 0.5,
                child: Padding(
                  // 与身份卡的内容缩进（20）对齐，两卡头像才能落在同一条线上。
                  padding: EdgeInsets.fromLTRB(narrow ? 16 : 20, 12, 20, 12),
                  child: Row(
                    children: [
                      ServerMonogram(
                        id: widget.profile.id,
                        label: widget.profile.label,
                        host: widget.profile.host,
                        size: 44,
                        online: connected,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            lastConnectedLabel(context, widget.lastConnected),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: texts.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: animations,
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
                              : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 2,
            offset: Offset(0, 1),
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
