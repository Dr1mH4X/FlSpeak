import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/models.dart';
import '../../../core/image_host.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/monogram.dart';
import 'media_viewer.dart';
import 'message_content.dart';

/// 频道消息：居中的消息流 + 底部胶囊输入框。
///
/// 消息不做气泡：原型的聊天是可读的长文流，气泡会把每行都切碎。
/// 输入框左侧选择本频道、服务器或在线私聊收件人。
class ChatPane extends StatefulWidget {
  const ChatPane({
    required this.channelName,
    required this.messages,
    required this.scope,
    required this.canSendChannel,
    required this.busy,
    required this.onScopeChanged,
    required this.onSend,
    required this.recipients,
    required this.selfUid,
    required this.recipientUid,
    required this.onRecipientChanged,
    required this.onReply,
    this.selfClientId,
    this.recipientId,
    this.onRecipientSelected,
    this.description = '',
    this.onPickImage,
    this.onPasteImage,
    this.onUploadImage,
    this.onConfigureImageHost,
    super.key,
  });

  final String channelName;
  final List<ChatMessage> messages;
  final ChatScope scope;
  final bool canSendChannel;
  final bool busy;
  final ValueChanged<ChatScope> onScopeChanged;
  final Future<bool> Function(String) onSend;
  final String selfUid;
  final int? selfClientId;
  final List<ClientView> recipients;
  final String? recipientUid;
  final int? recipientId;
  final ValueChanged<String> onRecipientChanged;
  final ValueChanged<ClientView>? onRecipientSelected;
  final ValueChanged<ChatMessage> onReply;
  final String description;
  final Future<PickedChatImage?> Function()? onPickImage;
  final Future<PickedChatImage?> Function()? onPasteImage;
  final Future<String?> Function(Uint8List)? onUploadImage;
  final VoidCallback? onConfigureImageHost;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  static const _contentMaxWidth = Sizes.chatContent;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  bool _sending = false;
  PickedChatImage? _image;
  String? _uploadedImageUrl;

  Future<void> _selectImage(Future<PickedChatImage?> Function() pick) async {
    if (_sending || widget.busy) return;
    setState(() => _sending = true);
    try {
      final image = await pick();
      if (mounted && image != null) {
        setState(() {
          _image = image;
          _uploadedImageUrl = null;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  ClientView? get _selectedRecipient {
    if (widget.recipientId != null) {
      for (final peer in widget.recipients) {
        if (peer.id == widget.recipientId && peer.uid == widget.recipientUid) {
          return peer;
        }
      }
      return null;
    }
    final matches = widget.recipients
        .where((peer) => peer.uid == widget.recipientUid)
        .toList();
    return matches.length == 1 ? matches.first : null;
  }

  bool _isOwnMessage(ChatMessage message) {
    if (message.fromId > 0 && widget.selfClientId != null) {
      return message.fromId == widget.selfClientId;
    }
    if (message.scope == ChatScope.direct &&
        widget.selfClientId != null &&
        message.targetId > 0) {
      return message.targetId != widget.selfClientId;
    }
    return widget.selfUid.isNotEmpty && message.fromUid == widget.selfUid;
  }

  bool get _canSend => switch (widget.scope) {
    ChatScope.server => true,
    ChatScope.channel => widget.canSendChannel,
    ChatScope.direct => _selectedRecipient != null,
  };

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
          duration: Motion.effectsFast,
          curve: Motion.effectsFastCurve,
        );
      }
    });
  }

  Future<void> _send() async {
    final draft = _input.value;
    final destination = (
      widget.scope,
      widget.recipientUid,
      widget.recipientId,
      widget.channelName,
    );
    final send = widget.onSend;
    var text = draft.text.trim();
    final image = _image;
    if ((text.isEmpty && image == null) ||
        widget.busy ||
        _sending ||
        !_canSend) {
      return;
    }
    setState(() => _sending = true);
    try {
      if (image != null) {
        final url =
            _uploadedImageUrl ?? await widget.onUploadImage?.call(image.bytes);
        if (!mounted || url == null) return;
        if (identical(_image, image)) _uploadedImageUrl = url;
        if (destination !=
            (
              widget.scope,
              widget.recipientUid,
              widget.recipientId,
              widget.channelName,
            )) {
          return;
        }
        text = [if (text.isNotEmpty) text, '![](<$url>)'].join('\n');
      }
      final sent = await send(text);
      if (mounted &&
          sent &&
          _input.value == draft &&
          destination ==
              (
                widget.scope,
                widget.recipientUid,
                widget.recipientId,
                widget.channelName,
              )) {
        _input.clear();
        setState(() {
          _image = null;
          _uploadedImageUrl = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focus.requestFocus();
      }
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
            // 拖动消息列表时收起键盘，避免触屏上键盘挡住输入区。
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 24),
            itemCount: widget.messages.length + 1,
            itemBuilder: (context, index) {
              final child = index == 0
                  ? _Welcome(
                      channelName: widget.channelName,
                      description: widget.description,
                    )
                  : _MessageRow(
                      message: widget.messages[index - 1],
                      onImageTap: _openImage,
                      onReply:
                          _sending ||
                              widget.busy ||
                              _isOwnMessage(widget.messages[index - 1])
                          ? null
                          : widget.onReply,
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
        // 没有当前投递目标时保留范围选择入口，禁止发送。
        if (_image != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: Radii.mediumAll,
                      child: Image.memory(
                        _image!.bytes,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.square(
                              dimension: 64,
                              child: Icon(Icons.broken_image_rounded),
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _image!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () => setState(() {
                              _image = null;
                              _uploadedImageUrl = null;
                            }),
                      icon: Icon(
                        Icons.close_rounded,
                        semanticLabel: l10n.chatRemoveImage,
                      ),
                    ),
                  ],
                ),
              ),
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
    final bottom = context.isCompact ? 16.0 : 24.0;
    final scope = widget.scope;
    final target = switch (scope) {
      ChatScope.server => l10n.chatScopeServer,
      ChatScope.channel => widget.channelName,
      ChatScope.direct =>
        _selectedRecipient?.nickname ?? l10n.chatRecipientUnavailable,
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              // 暗色主面板本身就是 surfaceContainer，输入条往上一级
              // （Highest）才浮得出来；亮色维持原状。
              color: scheme.surfaceContainerHigh,
              borderRadius: Radii.xlAll,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ScopeButton(
                  scope: scope,
                  onChanged: widget.onScopeChanged,
                  recipients: widget.recipients,
                  onRecipientChanged: widget.onRecipientChanged,
                  onRecipientSelected: widget.onRecipientSelected,
                  enabled: !_sending && !widget.busy,
                ),
                if (widget.onPickImage != null || widget.onPasteImage != null)
                  MenuAnchor(
                    builder: (context, menu, child) => IconButton(
                      onPressed: _sending || widget.busy
                          ? null
                          : () => menu.isOpen ? menu.close() : menu.open(),
                      icon: Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 20,
                        semanticLabel: l10n.chatAttachImage,
                      ),
                    ),
                    menuChildren: [
                      if (widget.onPickImage != null)
                        MenuItemButton(
                          onPressed: () => _selectImage(widget.onPickImage!),
                          child: Text(l10n.chatChooseImage),
                        ),
                      if (widget.onPasteImage != null)
                        MenuItemButton(
                          onPressed: () => _selectImage(widget.onPasteImage!),
                          child: Text(l10n.chatPasteImage),
                        ),
                      if (widget.onConfigureImageHost != null)
                        MenuItemButton(
                          onPressed: widget.onConfigureImageHost,
                          child: Text(l10n.imageHostTitle),
                        ),
                    ],
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final hintStyle = texts.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      );
                      var hintText = l10n.chatComposerHintTo(target);
                      if (scope == ChatScope.channel) {
                        final textWidth = math.max(
                          0.0,
                          constraints.maxWidth - 44,
                        );
                        final painter = TextPainter(
                          text: TextSpan(text: hintText, style: hintStyle),
                          maxLines: 1,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout(maxWidth: textWidth);
                        final overflows = painter.didExceedMaxLines;
                        painter.dispose();
                        if (overflows) {
                          hintText = l10n.chatComposerHintTo(
                            l10n.chatScopeChannel,
                          );
                        }
                      }
                      return Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _handleKeyEvent,
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          enabled: !_sending && !widget.busy && _canSend,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          // 触屏没有 Tab 键：点输入框外收起键盘。
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style: texts.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: hintText,
                            hintMaxLines: 1,
                            hintStyle: hintStyle,
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
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, value, child) => IconButton.filled(
                    onPressed:
                        !widget.busy &&
                            !_sending &&
                            _canSend &&
                            (value.text.trim().isNotEmpty || _image != null)
                        ? _send
                        : null,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(Sizes.touch, Sizes.touch),
                      shape: const CircleBorder(),
                    ),
                    icon: Icon(
                      Icons.send_rounded,
                      size: 20,
                      semanticLabel: l10n.chatSend,
                    ),
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

class _ScopeButton extends StatelessWidget {
  const _ScopeButton({
    required this.scope,
    required this.onChanged,
    required this.recipients,
    required this.onRecipientChanged,
    required this.enabled,
    this.onRecipientSelected,
  });

  final ChatScope scope;
  final ValueChanged<ChatScope> onChanged;
  final List<ClientView> recipients;
  final ValueChanged<String> onRecipientChanged;
  final ValueChanged<ClientView>? onRecipientSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      onPressed: !enabled
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .7,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in [
                        (
                          ChatScope.channel,
                          l10n.chatScopeChannel,
                          Icons.chat_bubble_rounded,
                        ),
                        (
                          ChatScope.server,
                          l10n.chatScopeServer,
                          Icons.public_rounded,
                        ),
                      ])
                        ListTile(
                          leading: Icon(entry.$3),
                          title: Text(entry.$2),
                          selected: scope == entry.$1,
                          onTap: () {
                            Navigator.pop(context);
                            onChanged(entry.$1);
                          },
                        ),
                      if (recipients.isNotEmpty) const Divider(),
                      for (final peer in recipients)
                        ListTile(
                          leading: const Icon(Icons.person_rounded),
                          title: Text(peer.nickname),
                          subtitle: Text(l10n.chatDirectTag),
                          onTap: () {
                            Navigator.pop(context);
                            if (onRecipientSelected != null) {
                              onRecipientSelected!(peer);
                            } else {
                              onRecipientChanged(peer.uid);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
      icon: Icon(
        switch (scope) {
          ChatScope.server => Icons.public_rounded,
          ChatScope.channel => Icons.chat_bubble_rounded,
          ChatScope.direct => Icons.person_rounded,
        },
        size: 20,
        semanticLabel: l10n.chatScopeTitle,
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.channelName, required this.description});

  final String channelName;
  final String description;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chatWelcomeTitle(channelName),
              style: texts.headlineSmall?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            MessageContent(
              text: description.isEmpty ? l10n.chatWelcomeBody : description,
              style:
                  texts.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ) ??
                  const TextStyle(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.onImageTap,
    required this.onReply,
  });

  final ChatMessage message;
  final ValueChanged<String> onImageTap;
  final ValueChanged<ChatMessage>? onReply;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow>
    with SingleTickerProviderStateMixin {
  // 入场是位移+淡入：位移按 M3 spatial fast 档，曲线带轻微回弹。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.spatialFast,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.spatialCurve,
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
                    if (message.scope == ChatScope.direct &&
                        widget.onReply != null)
                      IconButton(
                        onPressed: widget.onReply == null
                            ? null
                            : () => widget.onReply!(message),
                        icon: Icon(
                          Icons.reply_rounded,
                          size: 18,
                          semanticLabel: l10n.chatReply,
                        ),
                      ),
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
