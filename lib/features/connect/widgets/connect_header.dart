import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class ConnectHeader extends StatelessWidget {
  const ConnectHeader({
    required this.desktop,
    required this.connected,
    required this.onWorkspace,
    required this.onSettings,
    super.key,
  });

  final bool desktop;
  final bool connected;
  final VoidCallback onWorkspace;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    return Container(
      height: Sizes.header,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 32 : 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.forum_outlined,
            size: IconSizes.toolbar,
            color: scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              desktop ? l10n.serversTitle : l10n.appName,
              style: context.texts.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (connected) ...[
            const SizedBox(width: 12),
            if (desktop)
              TextButton.icon(
                onPressed: onWorkspace,
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  size: IconSizes.medium,
                ),
                label: Text(l10n.workspaceReturn),
              )
            else
              IconButton(
                onPressed: onWorkspace,
                icon: Icon(
                  Icons.arrow_forward_rounded,
                  semanticLabel: l10n.workspaceReturn,
                ),
              ),
          ],
          if (!desktop)
            IconButton(
              onPressed: onSettings,
              icon: Icon(
                Icons.settings_outlined,
                semanticLabel: l10n.settingsTitle,
              ),
            ),
        ],
      ),
    );
  }
}
