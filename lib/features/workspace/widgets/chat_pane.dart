import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/monogram.dart';
import 'media_viewer.dart';
import 'message_content.dart';

/// 频道消息：居中的消息流 + 底部胶囊输入框。
///
/// 消息不做气泡：原型的聊天是可读的长文流，气泡会把每行都切碎。
/// 输入框左侧的小按钮切换投递范围（本频道 / 整个服务器）。
class ChatPane extends StatefulWidget {
  const ChatPane({
    required this.channelName,
    required this.messages,
    required this.scope,
    required this.canSendChannel,
    required this.busy,
    required this.onScopeChanged,
    required this.onSend,
    super.key,
  });

  final String channelName;
  final List<ChatMessage> messages;
  final ChatScope scope;
  final bool canSendChannel;
  final bool busy;
  final ValueChanged<ChatScope> onScopeChanged;
  final ValueChanged<String> onSend;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  static const _contentMaxWidth = Sizes.chatContent;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  bool get _canSend =>
      widget.scope == ChatScope.server || widget.canSendChannel;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToEnd();
  }

  @override
  void didUpdateWidget(ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.scope != widget.scope) {
      _scheduleScrollToEnd();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleScrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      final target = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || !_canSend || widget.busy) {
      return;
    }
    _input.clear();
    widget.onSend(text);
    if (mounted) {
      _focus.requestFocus();
    }
  }

  /// 回车发送、Shift+回车换行；输入法组词期间的回车交给输入法提交候选。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (_input.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  /// 正文里的图片交给全屏浏览；浏览列表取当前频道所有图片，翻页才能连续。
  void _openImage(String url) {
    final urls = imageUrlsInMessages(widget.messages);
    final index = urls.indexOf(url);
    if (index < 0) {
      showMediaViewer(context, urls: [url]);
      return;
    }
    showMediaViewer(context, urls: urls, initialIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final horizontal = context.isCompact ? 16.0 : 32.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 24),
            itemCount: widget.messages.length + 1,
            itemBuilder: (context, index) {
              final child = index == 0
                  ? _Welcome(channelName: widget.channelName)
                  : _MessageRow(
                      message: widget.messages[index - 1],
                      onImageTap: _openImage,
                    );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: child,
                ),
              );
            },
          ),
        ),
        _buildComposer(context, l10n),
      ],
    );
  }

  Widget _buildComposer(BuildContext context, AppLocalizations l10n) {
    final scheme = context.scheme;
    final texts = context.texts;
    final horizontal = context.isCompact ? 16.0 : 32.0;
    final bottom = context.isCompact ? 16.0 : 32.0;
    final scope = widget.scope;
    final target = scope == ChatScope.server
        ? l10n.chatScopeServer
        : widget.channelName;
    final showNoChannel = scope == ChatScope.channel && !widget.canSendChannel;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showNoChannel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l10n.chatNoChannel,
                          style: texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(Radii.xxxl),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ScopeButton(
                      scope: scope,
                      onChanged: widget.onScopeChanged,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _handleKeyEvent,
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          enabled: _canSend,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          style: texts.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.chatComposerHintTo(
                              target == l10n.chatScopeServer
                                  ? target
                                  : '#$target',
                            ),
                            hintStyle: texts.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            filled: false,
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            // 文本距弧边的总内边距 = 容器 8 + 22 = 30，
                            // 与有效圆角半径（60 高钳制后的 30）光学对齐。
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _input,
                      builder: (context, value, child) => IconButton.filled(
                        tooltip: l10n.chatSend,
                        onPressed:
                            _canSend &&
                                !widget.busy &&
                                value.text.trim().isNotEmpty
                            ? _send
                            : null,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(Sizes.touch, Sizes.touch),
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 发送范围按钮：图标表示当前范围（# 是本频道，地球是整个服务器），点击
/// 直接切换，没有二级菜单。
class _ScopeButton extends StatelessWidget {
  const _ScopeButton({required this.scope, required this.onChanged});

  final ChatScope scope;
  final ValueChanged<ChatScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final server = scope == ChatScope.server;

    return SizedBox.square(
      dimension: Sizes.touch,
      child: IconButton(
        tooltip:
            '${l10n.chatScopeTitle} · '
            '${server ? l10n.chatScopeServer : l10n.chatScopeChannel}',
        onPressed: () =>
            onChanged(server ? ChatScope.channel : ChatScope.server),
        iconSize: 20,
        icon: Icon(
          server ? Icons.public_rounded : Icons.tag_rounded,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.channelName});

  final String channelName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.chatWelcomeTitle('#$channelName'),
            style: texts.headlineSmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.chatWelcomeBody,
            style: texts.bodyMedium?.copyWith(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({required this.message, required this.onImageTap});

  final ChatMessage message;
  final ValueChanged<String> onImageTap;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    final message = widget.message;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClientAvatar(nickname: message.from, size: AvatarSize.medium),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        message.from,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.labelLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      clockTime(message.at),
                      style: texts.labelSmall?.copyWith(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    if (message.scope == ChatScope.direct) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.chatDirectTag,
                        style: texts.labelSmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                MessageContent(
                  text: message.text,
                  style:
                      texts.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        height: 1.5,
                      ) ??
                      const TextStyle(),
                  onImageTap: widget.onImageTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) {
      return row;
    }
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(_curve),
        child: row,
      ),
    );
  }
}
