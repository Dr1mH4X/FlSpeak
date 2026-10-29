import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/channel_display.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/channel_icon.dart';
import '../../../widgets/common.dart';
import 'message_content.dart';

Future<void> showChannelDetailsDialog(
  BuildContext context,
  ChannelView channel,
) async {
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  await showAppModal<void>(
    context,
    title: l10n.channelDetails,
    builder: (_) => ChannelDetailsDialog(channel: channel),
  );
}

class ChannelDetailsDialog extends ConsumerWidget {
  const ChannelDetailsDialog({required this.channel, super.key});

  final ChannelView channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    final descriptionAsync = ref.watch(channelDescriptionProvider(channel.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ChannelIcon(iconId: channel.iconId, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                channelDisplayName(channel),
                style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.channelDescription,
          style: texts.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80, maxHeight: 320),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: Radii.largeAll,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: descriptionAsync.when(
            loading: () => const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.channelDescriptionFailed,
                    style: texts.bodySmall?.copyWith(color: scheme.error),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () =>
                        ref.invalidate(channelDescriptionProvider(channel.id)),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(l10n.commonRetry),
                  ),
                ],
              ),
            ),
            data: (description) {
              final trimmed = description.trim();
              if (trimmed.isEmpty) {
                return Center(
                  child: Text(
                    l10n.channelDescriptionEmpty,
                    style: texts.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return SingleChildScrollView(
                child: MessageContent(
                  text: trimmed,
                  style: texts.bodyMedium ?? const TextStyle(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
