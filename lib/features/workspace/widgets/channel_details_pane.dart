import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/channel_display.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/channel_icon.dart';
import 'message_content.dart';

class ChannelDetailsPane extends ConsumerWidget {
  const ChannelDetailsPane({required this.channel, super.key});

  final ChannelView channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    final descriptionAsync = ref.watch(channelDescriptionProvider(channel.id));
    final compact = context.isCompact;
    final padding = EdgeInsets.all(compact ? 16.0 : 24.0);

    return SizedBox.expand(
      child: SingleChildScrollView(
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 896),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: Radii.largeAll,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      ChannelIcon(
                        iconId: channel.iconId,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          channelDisplayName(channel),
                          style: texts.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: Radii.largeAll,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: descriptionAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    error: (error, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.channelDescriptionFailed,
                              style: texts.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => ref.invalidate(
                                channelDescriptionProvider(channel.id),
                              ),
                              icon: const Icon(
                                Icons.refresh_rounded,
                                size: IconSizes.small,
                              ),
                              label: Text(l10n.commonRetry),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (description) {
                      final trimmed = description.trim();
                      if (trimmed.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              l10n.channelDescriptionEmpty,
                              style: texts.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      }
                      return MessageContent(
                        text: trimmed,
                        style: texts.bodyMedium ?? const TextStyle(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
