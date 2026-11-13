import 'dart:typed_data';

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        Checkbox,
        Chip,
        Divider,
        FilledButton,
        IconButton,
        LinearProgressIndicator,
        OutlinedButton,
        Switch,
        TextButton;

import '../core/server_icon.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'expressive_frame.dart';
import 'monogram.dart';
import 'prism.dart';

Future<ServerIconChoice?> showServerIconPicker(
  BuildContext context,
  ServerIconChoice selected, {
  Uint8List? serverIconBytes,
}) => showAppModal<ServerIconChoice>(
  context,
  title: AppLocalizations.of(context).serverIconTitle,
  builder: (context) => ServerIconGrid(
    selected: selected,
    serverIconBytes: serverIconBytes,
    onSelected: (icon) => Navigator.of(context).pop(icon),
  ),
);

class ServerIconGrid extends StatelessWidget {
  const ServerIconGrid({
    required this.selected,
    required this.onSelected,
    this.serverIconBytes,
    super.key,
  });

  final ServerIconChoice selected;
  final ValueChanged<ServerIconChoice> onSelected;
  final Uint8List? serverIconBytes;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final l10n = AppLocalizations.of(context);
    final choices = <ServerIconChoice>[
      ServerIconChoice.auto,
      for (final preset in ServerIcon.values) ServerIconChoice.preset(preset),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final icon in choices)
          SizedBox(
            width: 80,
            child: Semantics(
              button: true,
              selected: selected == icon,
              child: AnimatedInkWell(
                onTap: () => onSelected(icon),
                borderRadius: Radii.largeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ExpressiveFrame(
                        size: 48,
                        color: selected == icon
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHigh,
                        child: ServerIconGlyph(
                          choice: icon,
                          serverIconBytes: serverIconBytes,
                          size: 48,
                          useAutoGlyph: true,
                          fallbackColor: selected == icon
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
