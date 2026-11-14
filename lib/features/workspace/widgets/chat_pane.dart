import 'dart:math' as math;

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        PopupMenuItem,
        Switch,
        TextButton;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/image_host.dart';
import '../../../core/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import '../../../widgets/prism.dart' hide Divider;
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
    this.unreadScopes = const <ChatScope>{},
    this.unreadPeers = const <String>{},
    this.description = '',
    this.onPickImage,
    this.onPasteImage,
    this.onUploadImage,
    this.onConfigureImageHost,
    this.onFetchBotCommands,
    this.avatarBuilder,
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

  /// 当前范围之外收到消息的来源，由输入框范围按钮提示。
  final Set<ChatScope> unreadScopes;
  final Set<String> unreadPeers;
  final String description;
  final Future<PickedChatImage?> Function()? onPickImage;
  final Future<PickedChatImage?> Function()? onPasteImage;
  final Future<String?> Function(Uint8List)? onUploadImage;
  final VoidCallback? onConfigureImageHost;
  final ValueChanged<ClientView>? onFetchBotCommands;
  final Widget Function(ChatMessage message)? avatarBuilder;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  static const _contentMaxWidth = Sizes.chatContent;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _scrollRequest = 0;
  bool _followingMessages = true;
  bool _scrollingToEnd = false;

  bool _sending = false;
  PickedChatImage? _image;
  String? _uploadedImageUrl;
  final _drafts = <_DraftTarget, _ComposerDraft>{};

  _DraftTarget _target(ChatPane pane) => (
    scope: pane.scope,
    uid: pane.scope == ChatScope.direct ? pane.recipientUid : null,
    clientId: pane.scope == ChatScope.direct ? pane.recipientId : null,
    channel: pane.channelName,
  );

  _ComposerDraft _snapshot() => _ComposerDraft(
    value: _input.value,
    image: _image,
    uploadedUrl: _uploadedImageUrl,
  );

  Future<void> _selectImage(Future<PickedChatImage?> Function() pick) async {
    if (_sending || widget.busy) return;
    final destination = _target(widget);
    final draft = _snapshot();
    setState(() => _sending = true);
    try {
      final image = await pick();
      if (mounted && image != null) {
        setState(() {
          if (destination == _target(widget)) {
            _image = image;
            _uploadedImageUrl = null;
          } else {
            _drafts[destination] = _ComposerDraft(
              value: draft.value,
              image: image,
            );
          }
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
    _recipientName = _selectedRecipient?.nickname;
    _input.addListener(_onInputChanged);
    _scheduleScrollToEnd();
  }

  /// 私聊对象离线后仍保留会话标题，历史还能读。
  String? _recipientName;

  void _onInputChanged() {
    if (widget.scope != ChatScope.direct || !_input.text.startsWith('/')) {
      return;
    }
    final recipient = _selectedRecipient;
    if (recipient != null &&
        recipient.capabilities.contains('chat:slash_commands') &&
        recipient.botCommands == null) {
      widget.onFetchBotCommands?.call(recipient);
    }
  }

  @override
  void didUpdateWidget(ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _target(oldWidget);
    final current = _target(widget);
    final changed = previous != current;
    final recipient = _selectedRecipient;
    if (recipient != null) {
      _recipientName = recipient.nickname;
    } else if (oldWidget.recipientUid != widget.recipientUid) {
      _recipientName = null;
    }
    if (changed) {
      if (_input.text.isNotEmpty || _image != null) {
        _drafts[previous] = _snapshot();
      }
      final draft = _drafts.remove(current) ?? const _ComposerDraft();
      _input.value = draft.value;
      _image = draft.image;
      _uploadedImageUrl = draft.uploadedUrl;
    }
    final latest = widget.messages.lastOrNull;
    final newMessage =
        latest != null && !identical(latest, oldWidget.messages.lastOrNull);
    final following =
        _followingMessages &&
        (!_scroll.hasClients ||
            _scroll.position.userScrollDirection == ScrollDirection.idle);
    if (changed || (newMessage && (following || _isOwnMessage(latest)))) {
      _scheduleScrollToEnd();
    }
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleScrollToEnd() {
    final request = ++_scrollRequest;
    _followingMessages = true;
    _scrollingToEnd = true;

    void follow(Duration _) async {
      if (!mounted || request != _scrollRequest || !_scroll.hasClients) {
        return;
      }
      if (_scroll.position.extentAfter < 1) {
        _scrollingToEnd = false;
        return;
      }
      final target = _scroll.position.maxScrollExtent;
      await _scroll.animateTo(
        target,
        duration: Motion.effectsFast,
        curve: Motion.effectsFastCurve,
      );
      if (mounted && request == _scrollRequest) {
        _scrollingToEnd = false;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(follow);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _send() async {
    final draft = _input.value;
    final destination = _target(widget);
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
        if (destination != _target(widget)) {
          final pending = _drafts[destination];
          if (pending != null && identical(pending.image, image)) {
            _drafts[destination] = _ComposerDraft(
              value: pending.value,
              image: image,
              uploadedUrl: url,
            );
          }
          return;
        }
        if (identical(_image, image)) _uploadedImageUrl = url;
        text = [if (text.isNotEmpty) text, '![](<$url>)'].join('\n');
      }
      final sent = await send(text);
      if (mounted && sent && destination != _target(widget)) {
        final pending = _drafts[destination];
        if (pending?.value == draft && identical(pending?.image, image)) {
          _drafts.remove(destination);
        }
      }
      if (mounted &&
          sent &&
          _input.value == draft &&
          identical(_image, image) &&
          destination == _target(widget)) {
        _input.clear();
        setState(() {
          _image = null;
          _uploadedImageUrl = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        if (destination == _target(widget) &&
            (ModalRoute.of(context)?.isCurrent ?? false)) {
          _focus.requestFocus();
        }
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
    final welcomeTitle = switch (widget.scope) {
      ChatScope.channel => l10n.chatWelcomeTitle(widget.channelName),
      ChatScope.server => l10n.chatServerTitle,
      ChatScope.direct => _recipientName ?? l10n.chatScopeDirect,
    };
    final welcomeBody = widget.scope == ChatScope.channel
        ? (widget.description.isEmpty
              ? l10n.chatWelcomeBody
              : widget.description)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              // 富文本、图片与惰性列表布局都可能修正底部的实际位置。
              if (notification.depth == 0 &&
                  _followingMessages &&
                  _scroll.hasClients &&
                  _scroll.position.userScrollDirection ==
                      ScrollDirection.idle) {
                _scheduleScrollToEnd();
              }
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) {
                  if (notification is UserScrollNotification &&
                      notification.direction != ScrollDirection.idle) {
                    _scrollRequest++;
                    _scrollingToEnd = false;
                  }
                  if (notification is ScrollUpdateNotification &&
                      !_scrollingToEnd) {
                    _followingMessages = notification.metrics.extentAfter < 72;
                  }
                }
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                // 拖动消息列表时收起键盘，避免触屏上键盘挡住输入区。
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 24),
                itemCount: widget.messages.length + 1,
                itemBuilder: (context, index) {
                  final child = index == 0
                      ? _Welcome(title: welcomeTitle, body: welcomeBody)
                      : _MessageRow(
                          avatar: widget.avatarBuilder?.call(
                            widget.messages[index - 1],
                          ),
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
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: child,
                    ),
                  );
                },
              ),
            ),
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
                    ClipRSuperellipse(
                      borderRadius: AppRadius.md,
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
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _input,
          builder: (context, value, _) => _buildSlashCommandAutocomplete(
            context,
            _selectedRecipient,
            value.text,
          ),
        ),
        _buildComposer(context, l10n),
      ],
    );
  }

  Widget _buildSlashCommandAutocomplete(
    BuildContext context,
    ClientView? recipient,
    String text,
  ) {
    if (!text.startsWith('/') ||
        widget.scope != ChatScope.direct ||
        text.contains(' ')) {
      return const SizedBox.shrink();
    }
    if (recipient == null ||
        !recipient.capabilities.contains('chat:slash_commands')) {
      return const SizedBox.shrink();
    }
    final commands = recipient.botCommands;
    if (commands == null || commands.isEmpty) {
      return const SizedBox.shrink();
    }

    final query = text.substring(1).toLowerCase();
    final matched = commands
        .where((c) => c.name.toLowerCase().startsWith(query))
        .toList();
    if (matched.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = context.scheme;
    final horizontal = context.isCompact ? 16.0 : 32.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _contentMaxWidth,
            maxHeight: 220,
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Surface(
              color: scheme.surfaceContainerHighest,
              clipBehavior: Clip.antiAlias,
              shape: AppShape.xl.copyWith(
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: SurfaceScope(
                level: floatingSurfaceLevelFor(scheme),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: matched.length,
                  itemBuilder: (context, index) {
                    final cmd = matched[index];
                    return AnimatedInkWell(
                      customBorder: AppShape.sm,
                      onTap: () {
                        final completed = '/${cmd.name} ';
                        _input.value = TextEditingValue(
                          text: completed,
                          selection: TextSelection.collapsed(
                            offset: completed.length,
                          ),
                        );
                        _focus.requestFocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '/${cmd.name}',
                              style: context.texts.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (cmd.args.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                cmd.args,
                                style: context.texts.bodySmall?.copyWith(
                                  color: scheme.tertiary,
                                ),
                              ),
                            ],
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                cmd.desc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
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
          child: DecoratedBox(
            decoration: ShapeDecoration(
              // 暗色主面板本身就是 surfaceContainer，输入条往上一级
              // （Highest）才浮得出来；亮色维持原状。
              color: scheme.surfaceContainerHigh,
              shape: RoundedSuperellipseBorder(
                borderRadius: AppRadius.xl,
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ScopeButton(
                    scope: scope,
                    onChanged: widget.onScopeChanged,
                    recipients: widget.recipients,
                    onRecipientChanged: widget.onRecipientChanged,
                    onRecipientSelected: widget.onRecipientSelected,
                    selectedRecipient: _selectedRecipient,
                    unreadScopes: widget.unreadScopes,
                    unreadPeers: widget.unreadPeers,
                    enabled: !_sending && !widget.busy,
                  ),
                  if (widget.onPickImage != null || widget.onPasteImage != null)
                    SecondaryMenu(
                      enabled: !_sending && !widget.busy,
                      items: [
                        if (widget.onPickImage != null)
                          PopupMenuItem(
                            label: l10n.chatChooseImage,
                            onPressed: () => _selectImage(widget.onPickImage!),
                          ),
                        if (widget.onPasteImage != null)
                          PopupMenuItem(
                            label: l10n.chatPasteImage,
                            onPressed: () => _selectImage(widget.onPasteImage!),
                          ),
                        if (widget.onConfigureImageHost != null)
                          PopupMenuItem(
                            label: l10n.imageHostTitle,
                            onPressed: widget.onConfigureImageHost,
                          ),
                      ],
                      builder: (context, openMenu) => IconButton(
                        onPressed: openMenu,
                        icon: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: IconSizes.toolbar,
                          semanticLabel: l10n.chatAttachImage,
                        ),
                      ),
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
                    builder: (context, value, child) => IconButton(
                      onPressed:
                          !widget.busy &&
                              !_sending &&
                              _canSend &&
                              (value.text.trim().isNotEmpty || _image != null)
                          ? _send
                          : null,
                      style: ButtonStyle.from(foregroundColor: scheme.primary),
                      icon: Icon(
                        Icons.send_rounded,
                        size: IconSizes.toolbar,
                        semanticLabel: l10n.chatSend,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _DraftTarget = ({
  ChatScope scope,
  String? uid,
  int? clientId,
  String channel,
});

class _ComposerDraft {
  const _ComposerDraft({
    this.value = TextEditingValue.empty,
    this.image,
    this.uploadedUrl,
  });
  final TextEditingValue value;
  final PickedChatImage? image;
  final String? uploadedUrl;
}

class _ScopeButton extends StatelessWidget {
  const _ScopeButton({
    required this.scope,
    required this.onChanged,
    required this.recipients,
    required this.onRecipientChanged,
    required this.enabled,
    required this.unreadScopes,
    required this.unreadPeers,
    this.selectedRecipient,
    this.onRecipientSelected,
  });

  final ChatScope scope;
  final ValueChanged<ChatScope> onChanged;
  final List<ClientView> recipients;
  final ValueChanged<String> onRecipientChanged;
  final ValueChanged<ClientView>? onRecipientSelected;
  final ClientView? selectedRecipient;
  final bool enabled;
  final Set<ChatScope> unreadScopes;
  final Set<String> unreadPeers;

  bool get _hasUnread => unreadScopes.isNotEmpty || unreadPeers.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final isDirect = scope == ChatScope.direct;
    return IconButton(
      onPressed: !enabled
          ? null
          : () {
              final navigator = Navigator.of(context, rootNavigator: true);
              final capturedThemes = InheritedTheme.capture(
                from: context,
                to: navigator.context,
              );
              navigator.push<void>(
                SnapSheetRoute<void>(
                  fitsContent: true,
                  sheetBarrierColor: scheme.scrim.withValues(alpha: 0.32),
                  barrierLabel: MaterialLocalizations.of(context)
                      .modalBarrierDismissLabel,
                  builder: (context, _) => capturedThemes.wrap(
                    SurfaceScope(
                      level: SurfaceLevel.page,
                      child: Material(
                        type: MaterialType.transparency,
                        child: SafeArea(
                          top: false,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.sizeOf(context).height * .7,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SheetDragHandle(),
                                const SizedBox(height: 8),
                                Flexible(
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
                                        _ScopeOptionRow(
                                          icon: entry.$3,
                                          title: entry.$2,
                                          unread: unreadScopes.contains(
                                            entry.$1,
                                          ),
                                          selected: scope == entry.$1,
                                          onTap: () {
                                            Navigator.pop(context);
                                            onChanged(entry.$1);
                                          },
                                        ),
                                      if (recipients.isNotEmpty) ...[
                                        Divider(
                                          color: dividerColorOf(context),
                                          height: 1,
                                        ),
                                        ExpansionTile(
                                          leading: const Icon(
                                            Icons.person_rounded,
                                          ),
                                          title: Row(
                                            children: [
                                              Text(l10n.chatScopeDirect),
                                              if (unreadPeers.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                const _UnreadDot(),
                                              ],
                                            ],
                                          ),
                                          initiallyExpanded: false,
                                          shape: const Border(),
                                          collapsedShape: const Border(),
                                          textColor: isDirect
                                              ? scheme.primary
                                              : null,
                                          iconColor: isDirect
                                              ? scheme.primary
                                              : null,
                                          collapsedTextColor: isDirect
                                              ? scheme.primary
                                              : null,
                                          collapsedIconColor: isDirect
                                              ? scheme.primary
                                              : null,
                                          children: [
                                            for (final peer in recipients)
                                              _ScopeOptionRow(
                                                icon: Icons.person_rounded,
                                                title: peer.nickname,
                                                subtitle: l10n.chatDirectTag,
                                                unread: unreadPeers.contains(
                                                  peer.uid,
                                                ),
                                                selected:
                                                    isDirect &&
                                                    peer.uid ==
                                                        selectedRecipient?.uid,
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  if (onRecipientSelected !=
                                                      null) {
                                                    onRecipientSelected!(peer);
                                                  } else {
                                                    onRecipientChanged(
                                                      peer.uid,
                                                    );
                                                  }
                                                },
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
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
            },
      icon: Badge(
        isLabelVisible: _hasUnread,
        smallSize: 8,
        backgroundColor: scheme.error,
        child: Icon(
          switch (scope) {
            ChatScope.server => Icons.public_rounded,
            ChatScope.channel => Icons.chat_bubble_rounded,
            ChatScope.direct => Icons.person_rounded,
          },
          size: IconSizes.toolbar,
          semanticLabel: _hasUnread
              ? l10n.chatScopeUnread
              : l10n.chatScopeTitle,
        ),
      ),
    );
  }
}

class _ScopeOptionRow extends StatelessWidget {
  const _ScopeOptionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool unread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final foreground = selected ? scheme.onPrimaryContainer : null;
    final row = DecoratedBox(
      decoration: ShapeDecoration(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: AppShape.none,
      ),
      child: AnimatedInkWell(
        onTap: onTap,
        child: ListRow(
          leading: Icon(icon, color: foreground),
          title: Text(
            title,
            style: foreground != null ? TextStyle(color: foreground) : null,
          ),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: unread ? const _UnreadDot() : null,
        ),
      ),
    );
    return row;
  }
}

/// 未读提示的小圆点；随行文字一起读出，不额外占用文案。
class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.circle,
      size: 8,
      color: context.scheme.error,
      semanticLabel: AppLocalizations.of(context).chatUnread,
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
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
              title,
              style: texts.headlineSmall?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              MessageContent(
                text: body,
                style:
                    texts.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ) ??
                    const TextStyle(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    this.avatar,
    required this.message,
    required this.onImageTap,
    required this.onReply,
  });

  final ChatMessage message;
  final Widget? avatar;
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
          widget.avatar ??
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
                    if (message.scope == ChatScope.direct &&
                        widget.onReply != null)
                      IconButton(
                        onPressed: widget.onReply == null
                            ? null
                            : () => widget.onReply!(message),
                        icon: Icon(
                          Icons.reply_rounded,
                          size: IconSizes.medium,
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
