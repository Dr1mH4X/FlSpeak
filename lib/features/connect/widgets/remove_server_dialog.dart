import 'package:flutter/material.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';

/// 移除档案需要确认。地址重新录入成本不低，但历史消息不受影响，
/// 所以确认文案要说清「只从列表消失」。
Future<bool> showRemoveServerDialog(
  BuildContext context,
  ServerProfileView server,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showAppModal<bool>(
    context,
    title: l10n.serverRemoveTitle,
    description: l10n.serverRemoveBody(server.label),
    builder: (context) => _ServerPreview(server: server),
    footer: (context) {
      final scheme = context.scheme;
      return Flexible(
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.serverRemove),
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}

class _ServerPreview extends StatelessWidget {
  const _ServerPreview({required this.server});

  final ServerProfileView server;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: Radii.xxlAll,
      ),
      child: Row(
        children: [
          ServerMonogram(
            id: server.id,
            label: server.label,
            host: server.host,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyLarge?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${server.host}:${server.port}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
