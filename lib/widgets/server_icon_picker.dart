import 'package:flutter/material.dart';

import '../core/server_icon.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'expressive_frame.dart';

Future<ServerIcon?> showServerIconPicker(
  BuildContext context,
  ServerIcon selected,
) => showAppModal<ServerIcon>(
  context,
  title: AppLocalizations.of(context).serverIconTitle,
  builder: (context) => ServerIconGrid(
    selected: selected,
    onSelected: (icon) => Navigator.of(context).pop(icon),
  ),
);

class ServerIconGrid extends StatelessWidget {
  const ServerIconGrid({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ServerIcon selected;
  final ValueChanged<ServerIcon> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final icon in ServerIcon.values)
          SizedBox(
            width: 80,
            child: Semantics(
              button: true,
              selected: selected == icon,
              child: InkWell(
                onTap: () => onSelected(icon),
                borderRadius: Radii.largeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ExpressiveFrame(
                        size: 48,
                        shapeSeed: icon.index,
                        color: selected == icon
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHigh,
                        child: Icon(
                          icon.icon,
                          color: selected == icon
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        icon.label(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelMedium?.copyWith(
                          color: selected == icon
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
      ],
    );
  }
}
