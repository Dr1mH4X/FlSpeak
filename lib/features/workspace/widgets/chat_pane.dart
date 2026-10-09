import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';

/// 聊天栏：范围选择 + 消息流 + 输入框。
///
/// 列表用 `reverse: true`，新消息天然出现在底部，视口也自然停在最新一条，
/// 不需要自己算滚动位置。
class ChatPane extends ConsumerStatefulWidget {
  const ChatPane({super.key});

  @override
  ConsumerState<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends ConsumerState<ChatPane> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) {
      return;
    }
    _input.clear();
    _focus.requestFocus();
    await ref.read(sessionViewProvider.notifier).sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final view = ref.watch(sessionViewProvider);
    final controller = ref.read(sessionViewProvider.notifier);
    final messages = view.visibleMessages();
    final canSendChannel = view.selfChannelId != null;
    final blocked = view.chatScope == ChatScope.channel && !canSendChannel;

    return PaneShell(
      title: l10n.chatTitle,
      trailing: SegmentedButton<ChatScope>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: ChatScope.channel,
            label: Text(l10n.chatScopeChannel),
          ),
          ButtonSegment(
            value: ChatScope.server,
            label: Text(l10n.chatScopeServer),
          ),
        ],
        selected: {view.chatScope},
        onSelectionChanged: (selection) =>
            controller.selectChatScope(selection.first),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: messages.isEmpty
                ? EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    body: view.chatScope == ChatScope.server
                        ? l10n.chatEmptyServer
                        : l10n.chatEmptyChannel,
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      return _MessageTile(
                        message: message,
                        isSelf:
                            view.selfUid.isNotEmpty &&
                            message.fromUid == view.selfUid,
                        now: DateTime.now(),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        enabled: !blocked,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: l10n.chatComposerHint,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: l10n.chatSend,
                      onPressed: blocked ? null : _send,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                  ],
                ),
                if (blocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Text(
                      l10n.chatNoChannel,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.isSelf,
    required this.now,
  });

  final ChatMessage message;
  final bool isSelf;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final metaColor = isSelf
        ? scheme.onPrimaryContainer.withValues(alpha: 0.75)
        : scheme.onSurfaceVariant;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isSelf ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isSelf ? Radii.medium : 4),
          topRight: Radius.circular(isSelf ? 4 : Radii.medium),
          bottomLeft: Radii.mediumAll.topLeft,
          bottomRight: Radii.mediumAll.topRight,
        ),
        border: isSelf ? null : Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isSelf) ...[
                  Text(
                    message.from,
                    style: text.labelSmall?.copyWith(color: metaColor),
                  ),
                  const SizedBox(width: 6),
                ],
                if (message.scope == ChatScope.direct) ...[
                  Text(
                    l10n.chatDirectTag,
                    style: text.labelSmall?.copyWith(
                      color: isSelf ? metaColor : scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  relativeTime(message.at, now),
                  style: text.labelSmall?.copyWith(
                    color: metaColor,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          SelectableText(
            message.text,
            style: text.bodyMedium?.copyWith(
              color: isSelf ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isSelf
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isSelf) ...[
            ClientAvatar(nickname: message.from, size: 28),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}
