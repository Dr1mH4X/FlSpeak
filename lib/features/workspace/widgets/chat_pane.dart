import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        InputBorder,
        InputDecoration,
        OutlinedButton,
        PopupMenuItem,
        Switch,
        TextButton,
        TextField;
import 'package:flutter/rendering.dart' show RenderProxyBox, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/image_host.dart';
import '../../../core/models.dart';
import '../../../core/providers.dart';
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
    this.selfClientId,
    this.selfChannelId,
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
  final int? selfChannelId;
  final List<ClientView> recipients;
  final String? recipientUid;
  final int? recipientId;
  final ValueChanged<String> onRecipientChanged;
  final ValueChanged<ClientView>? onRecipientSelected;

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
  final _dockInset = ValueNotifier<double>(90);
  int _scrollRequest = 0;
  bool _followingMessages = true;
  bool _scrollingToEnd = false;
  ChatMessage? _animatedMessage;

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

  String _commandPrefixFor(ClientView bot) {
    final prefix = bot.botCommandPrefix;
    return (prefix != null && prefix.isNotEmpty) ? prefix : '/';
  }

  List<ClientView> get _commandBots {
    switch (widget.scope) {
      case ChatScope.direct:
        final recipient = _selectedRecipient;
        if (recipient == null ||
            !recipient.capabilities.contains('chat:slash_commands')) {
          return const [];
        }
        return [recipient];
      case ChatScope.channel:
        if (!widget.canSendChannel || widget.selfChannelId == null) {
          return const [];
        }
        return widget.recipients
            .where(
              (peer) =>
                  peer.channelId == widget.selfChannelId &&
                  peer.id != widget.selfClientId &&
                  peer.capabilities.contains('chat:slash_commands'),
            )
            .toList();
      case ChatScope.server:
        return const [];
    }
  }

  void _onInputChanged() {
    final text = _input.text;
    if (text.isEmpty || text.contains(' ')) {
      return;
    }
    for (final bot in _commandBots) {
      if (bot.botCommands == null) {
        widget.onFetchBotCommands?.call(bot);
      }
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
    if (!changed && newMessage) {
      _animatedMessage = latest;
    } else if (changed) {
      _animatedMessage = null;
    }
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
    _dockInset.dispose();
    super.dispose();
  }

  void _handleDockHeightChanged(double height) {
    if (!mounted || (height - _dockInset.value).abs() <= 0.5) {
      return;
    }
    _dockInset.value = height;
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
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        await _scroll.animateTo(
          target,
          duration: Motion.effectsFast,
          curve: Motion.effectsFastCurve,
        );
      }
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
    var uploadedUrl = _uploadedImageUrl;
    if ((text.isEmpty && image == null) ||
        widget.busy ||
        _sending ||
        !_canSend) {
      return;
    }
    if ((ModalRoute.of(context)?.isCurrent ?? false) && !_focus.hasFocus) {
      _focus.requestFocus();
    }
    _input.clear();
    setState(() {
      _sending = true;
      _image = null;
      _uploadedImageUrl = null;
    });

    void restoreDraft() {
      if (!mounted) return;
      if (destination == _target(widget)) {
        if (_input.text.isEmpty && _image == null) {
          _input.value = draft;
          setState(() {
            _image = image;
            _uploadedImageUrl = uploadedUrl;
          });
        }
      } else {
        _drafts.putIfAbsent(
          destination,
          () => _ComposerDraft(
            value: draft,
            image: image,
            uploadedUrl: uploadedUrl,
          ),
        );
      }
    }

    var sent = false;
    try {
      if (image != null) {
        uploadedUrl ??= await widget.onUploadImage?.call(image.bytes);
        if (!mounted || uploadedUrl == null || destination != _target(widget)) {
          return;
        }
        text = [if (text.isNotEmpty) text, '![](<$uploadedUrl>)'].join('\n');
      }
      sent = await send(text);
    } finally {
      if (!sent) {
        restoreDraft();
      }
      if (mounted) {
        setState(() => _sending = false);
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

    return Stack(
      children: [
        Positioned.fill(
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
              child: ValueListenableBuilder<double>(
                valueListenable: _dockInset,
                builder: (context, dockInset, _) => PrismListView(
                  controller: _scroll,
                  // 拖动消息列表时收起键盘，避免触屏上键盘挡住输入区。
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    24,
                    horizontal,
                    24 + dockInset,
                  ),
                  estimatedItemExtent: 84,
                  itemCount: widget.messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _contentMaxWidth,
                          ),
                          child: _Welcome(
                            title: welcomeTitle,
                            body: welcomeBody,
                          ),
                        ),
                      );
                    }
                    final message = widget.messages[index - 1];
                    final animateEntry = identical(message, _animatedMessage);
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _contentMaxWidth,
                        ),
                        child: MemoBuilder(
                          inputs: [message, animateEntry, context.isCompact],
                          builder: (context) => _MessageRow(
                            avatar: widget.avatarBuilder?.call(message),
                            message: message,
                            onImageTap: _openImage,
                            animateEntry: animateEntry,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (context, value, _) =>
                    _buildSlashCommandAutocomplete(context, value.text),
              ),
              _MeasureDockHeight(
                onHeightChanged: _handleDockHeightChanged,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 没有当前投递目标时保留范围选择入口，禁止发送。
                    if (_image != null) _buildImagePreview(context, l10n),
                    context.isCompact
                        ? _CompactWorkspaceBottomBar(
                            input: _input,
                            focusNode: _focus,
                            canSend: _canSend,
                            sending: _sending,
                            busy: widget.busy,
                            hasImage: _image != null,
                            hintText: _composerHintText(context, l10n),
                            scope: widget.scope,
                            onScopeChanged: widget.onScopeChanged,
                            recipients: widget.recipients,
                            onRecipientChanged: widget.onRecipientChanged,
                            onRecipientSelected: widget.onRecipientSelected,
                            selectedRecipient: _selectedRecipient,
                            unreadScopes: widget.unreadScopes,
                            unreadPeers: widget.unreadPeers,
                            onSend: _send,
                            onKeyEvent: _handleKeyEvent,
                            onPickImage: widget.onPickImage == null
                                ? null
                                : () => _selectImage(widget.onPickImage!),
                            onPasteImage: widget.onPasteImage == null
                                ? null
                                : () => _selectImage(widget.onPasteImage!),
                            onConfigureImageHost: widget.onConfigureImageHost,
                          )
                        : _buildComposer(context, l10n),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingContainer(
    BuildContext context, {
    required LiquidGlassStyle glassStyle,
    required Color fallbackColor,
    required List<BoxShadow> shadows,
    bool clip = false,
    required Widget child,
  }) {
    final scheme = context.scheme;
    final content = clip
        ? ClipRSuperellipse(borderRadius: AppRadius.xl, child: child)
        : child;
    if (LiquidGlassScope.of(context)) {
      return LiquidGlass(
        style: glassStyle,
        borderRadius: AppRadius.xl,
        shadows: shadows,
        child: content,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fallbackColor,
        shape: AppShape.xl.copyWith(side: BorderSide(color: scheme.outline)),
        shadows: shadows,
      ),
      child: content,
    );
  }

  Widget _buildImagePreview(BuildContext context, AppLocalizations l10n) {
    final scheme = context.scheme;
    final horizontal = context.isCompact ? 16.0 : 32.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: _buildFloatingContainer(
            context,
            glassStyle: glassPillStyleOf(context),
            fallbackColor: scheme.surfaceContainerHigh,
            shadows: dockShadowsOf(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRSuperellipse(
                    borderRadius: AppRadius.md,
                    child: Image.memory(
                      _image!.bytes,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(1, 256),
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
      ),
    );
  }

  Widget _buildSlashCommandAutocomplete(BuildContext context, String text) {
    if (text.isEmpty || text.contains(' ')) {
      return const SizedBox.shrink();
    }
    final bots = _commandBots;
    if (bots.isEmpty) {
      return const SizedBox.shrink();
    }

    final matched =
        <({ClientView bot, String prefix, BotCommandView command})>[];
    for (final bot in bots) {
      final commands = bot.botCommands;
      if (commands == null || commands.isEmpty) continue;
      final prefix = _commandPrefixFor(bot);
      if (!text.startsWith(prefix)) continue;
      final query = text.substring(prefix.length).toLowerCase();
      for (final cmd in commands) {
        if (cmd.name.toLowerCase().startsWith(query)) {
          matched.add((bot: bot, prefix: prefix, command: cmd));
        }
      }
    }
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
            child: _buildFloatingContainer(
              context,
              glassStyle: glassMenuStyleOf(context),
              fallbackColor: scheme.surfaceContainerHighest,
              shadows: menuShadowsOf(context),
              clip: true,
              child: SurfaceScope(
                level: floatingSurfaceLevelFor(scheme),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: matched.length,
                  itemBuilder: (context, index) {
                    final item = matched[index];
                    final cmd = item.command;
                    return AnimatedInkWell(
                      customBorder: AppShape.sm,
                      onTap: () {
                        final completed = '${item.prefix}${cmd.name} ';
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
                              '${item.prefix}${cmd.name}',
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
                            if (widget.scope == ChatScope.channel) ...[
                              const SizedBox(width: 8),
                              Text(
                                item.bot.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
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

  String _composerHintText(BuildContext context, AppLocalizations l10n) {
    final target = switch (widget.scope) {
      ChatScope.server => l10n.chatScopeServer,
      ChatScope.channel => widget.channelName,
      ChatScope.direct =>
        _selectedRecipient?.nickname ?? l10n.chatRecipientUnavailable,
    };
    return l10n.chatComposerHintTo(target);
  }

  Widget _buildComposer(BuildContext context, AppLocalizations l10n) {
    final scheme = context.scheme;
    final texts = context.texts;
    final horizontal = context.isCompact ? 16.0 : 32.0;
    final bottom = context.isCompact ? 16.0 : 24.0;
    final scope = widget.scope;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: TextFieldTapRegion(
            child: _buildFloatingContainer(
              context,
              glassStyle: glassPillStyleOf(context),
              // 暗色主面板本身就是 surfaceContainer，输入条往上一级
              // （Highest）才浮得出来；亮色维持原状。
              fallbackColor: scheme.surfaceContainerHigh,
              shadows: dockShadowsOf(context),
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
                    if (widget.onPickImage != null ||
                        widget.onPasteImage != null)
                      SecondaryMenu(
                        enabled: !_sending && !widget.busy,
                        items: [
                          if (widget.onPickImage != null)
                            PopupMenuItem(
                              label: l10n.chatChooseImage,
                              onPressed: () =>
                                  _selectImage(widget.onPickImage!),
                            ),
                          if (widget.onPasteImage != null)
                            PopupMenuItem(
                              label: l10n.chatPasteImage,
                              onPressed: () =>
                                  _selectImage(widget.onPasteImage!),
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
                      child: WidthBuilder(
                        builder: (context, width) {
                          final hintStyle = texts.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          );
                          var hintText = _composerHintText(context, l10n);
                          if (scope == ChatScope.channel) {
                            final textWidth = math.max(0.0, width - 44);
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
                              enabled: _canSend,
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
                                hoverColor: Colors.transparent,
                                isDense: true,
                                border: const NoInputBorder(),
                                enabledBorder: const NoInputBorder(),
                                focusedBorder: const NoInputBorder(),
                                disabledBorder: const NoInputBorder(),
                                errorBorder: const NoInputBorder(),
                                focusedErrorBorder: const NoInputBorder(),
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
                        style: ButtonStyle.from(
                          foregroundColor: scheme.primary,
                        ),
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
      ),
    );
  }
}

class _CompactWorkspaceBottomBar extends ConsumerStatefulWidget {
  const _CompactWorkspaceBottomBar({
    required this.input,
    required this.focusNode,
    required this.canSend,
    required this.sending,
    required this.busy,
    required this.hasImage,
    required this.hintText,
    required this.scope,
    required this.onScopeChanged,
    required this.recipients,
    required this.onRecipientChanged,
    required this.onRecipientSelected,
    required this.selectedRecipient,
    required this.unreadScopes,
    required this.unreadPeers,
    required this.onSend,
    required this.onKeyEvent,
    this.onPickImage,
    this.onPasteImage,
    this.onConfigureImageHost,
  });

  final TextEditingController input;
  final FocusNode focusNode;
  final bool canSend;
  final bool sending;
  final bool busy;
  final bool hasImage;
  final String hintText;
  final ChatScope scope;
  final ValueChanged<ChatScope> onScopeChanged;
  final List<ClientView> recipients;
  final ValueChanged<String> onRecipientChanged;
  final ValueChanged<ClientView>? onRecipientSelected;
  final ClientView? selectedRecipient;
  final Set<ChatScope> unreadScopes;
  final Set<String> unreadPeers;
  final Future<void> Function() onSend;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback? onPickImage;
  final VoidCallback? onPasteImage;
  final VoidCallback? onConfigureImageHost;

  @override
  ConsumerState<_CompactWorkspaceBottomBar> createState() =>
      _CompactWorkspaceBottomBarState();
}

class _CompactWorkspaceBottomBarState
    extends ConsumerState<_CompactWorkspaceBottomBar> {
  static const double _slotHeight = 48.0;

  late bool _voiceControlMode = ref.read(sessionViewProvider).pttMode;
  SessionController? _pttOwner;

  bool get _hasUnread =>
      widget.unreadScopes.isNotEmpty || widget.unreadPeers.isNotEmpty;

  void _setPttHeld(bool active) {
    if (!active) {
      final owner = _pttOwner;
      _pttOwner = null;
      if (owner != null) {
        unawaited(owner.setPttActive(false));
      }
      return;
    }
    if (_pttOwner != null) {
      return;
    }
    final owner = ref.read(sessionViewProvider.notifier);
    _pttOwner = owner;
    unawaited(owner.setPttActive(true));
  }

  @override
  void dispose() {
    _setPttHeld(false);
    super.dispose();
  }

  void _switchToVoiceControl() {
    widget.focusNode.unfocus();
    setState(() => _voiceControlMode = true);
  }

  void _switchToTextInput() {
    _setPttHeld(false);
    setState(() => _voiceControlMode = false);
  }

  Widget _buildSlotSurface(
    BuildContext context, {
    required bool floating,
    required OutlinedBorder shape,
    required BorderRadius glassRadius,
    Color? color,
    required Widget child,
  }) {
    final scheme = context.scheme;
    final glass = floating && LiquidGlassScope.of(context);
    final fill =
        color ??
        (floating
            ? surfaceColorFor(floatingSurfaceLevelFor(scheme), scheme)
            : context.raisedSurfaceColor);
    if (glass && color == null) {
      return LiquidGlass(
        style: glassPillStyleOf(context),
        borderRadius: glassRadius,
        shadows: dockShadowsOf(context),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fill,
        shape: shape,
        shadows: floating ? dockShadowsOf(context) : const [],
      ),
      child: child,
    );
  }

  Widget _buildCircleSlot(
    BuildContext context, {
    required bool floating,
    Color? color,
    required Widget child,
  }) {
    return SizedBox.square(
      dimension: _slotHeight,
      child: _buildSlotSurface(
        context,
        floating: floating,
        shape: AppShape.full,
        glassRadius: AppRadius.full,
        color: color,
        child: ClipRSuperellipse(borderRadius: AppRadius.full, child: child),
      ),
    );
  }

  Widget _buildTextLeftButton(
    BuildContext context,
    AppLocalizations l10n, {
    required bool floating,
  }) {
    final canAttach = widget.onPickImage != null || widget.onPasteImage != null;
    final enabled = canAttach && !widget.sending && !widget.busy;
    final scheme = context.scheme;
    return _buildCircleSlot(
      context,
      floating: floating,
      child: canAttach
          ? SecondaryMenu(
              enabled: enabled,
              items: [
                if (widget.onPickImage != null)
                  PopupMenuItem(
                    label: l10n.chatChooseImage,
                    onPressed: widget.onPickImage,
                  ),
                if (widget.onPasteImage != null)
                  PopupMenuItem(
                    label: l10n.chatPasteImage,
                    onPressed: widget.onPasteImage,
                  ),
                if (widget.onConfigureImageHost != null)
                  PopupMenuItem(
                    label: l10n.imageHostTitle,
                    onPressed: widget.onConfigureImageHost,
                  ),
              ],
              builder: (context, openMenu) => IconButton(
                onPressed: openMenu,
                style: ButtonStyle.from(
                  foregroundColor: scheme.onSurface,
                  minimumSize: const Size.square(_slotHeight),
                  padding: EdgeInsets.zero,
                ),
                icon: Icon(
                  Icons.add_photo_alternate_outlined,
                  size: IconSizes.toolbar,
                  semanticLabel: l10n.chatAttachImage,
                ),
              ),
            )
          : IconButton(
              onPressed: null,
              style: ButtonStyle.from(
                minimumSize: const Size.square(_slotHeight),
                padding: EdgeInsets.zero,
              ),
              icon: Icon(
                Icons.add_photo_alternate_outlined,
                size: IconSizes.toolbar,
                semanticLabel: l10n.chatAttachImage,
              ),
            ),
    );
  }

  Widget _buildTextCenterCapsule(
    BuildContext context,
    AppLocalizations l10n, {
    required bool floating,
  }) {
    final scheme = context.scheme;
    final texts = context.texts;
    return _buildSlotSurface(
      context,
      floating: floating,
      shape: AppShape.xl,
      glassRadius: AppRadius.xl,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _slotHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: widget.onKeyEvent,
                  child: TextField(
                    controller: widget.input,
                    focusNode: widget.focusNode,
                    enabled: widget.canSend,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: texts.bodyMedium?.copyWith(color: scheme.onSurface),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintMaxLines: 1,
                      hintStyle: texts.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      filled: false,
                      hoverColor: Colors.transparent,
                      isDense: true,
                      border: const NoInputBorder(),
                      enabledBorder: const NoInputBorder(),
                      focusedBorder: const NoInputBorder(),
                      disabledBorder: const NoInputBorder(),
                      errorBorder: const NoInputBorder(),
                      focusedErrorBorder: const NoInputBorder(),
                      contentPadding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    ),
                  ),
                ),
              ),
              _ScopeButton(
                scope: widget.scope,
                onChanged: widget.onScopeChanged,
                recipients: widget.recipients,
                onRecipientChanged: widget.onRecipientChanged,
                onRecipientSelected: widget.onRecipientSelected,
                selectedRecipient: widget.selectedRecipient,
                unreadScopes: widget.unreadScopes,
                unreadPeers: widget.unreadPeers,
                enabled: !widget.sending && !widget.busy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextRightButton(
    BuildContext context,
    AppLocalizations l10n, {
    required bool floating,
    required bool pttMode,
    required bool muted,
    required bool selfSpeaking,
  }) {
    final scheme = context.scheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.input,
      builder: (context, value, _) {
        final hasContent = value.text.trim().isNotEmpty || widget.hasImage;
        if (hasContent) {
          final canSubmit = !widget.busy && !widget.sending && widget.canSend;
          return _buildCircleSlot(
            context,
            floating: floating,
            color: canSubmit ? scheme.primary : null,
            child: IconButton(
              onPressed: canSubmit ? () => unawaited(widget.onSend()) : null,
              style: ButtonStyle.from(
                foregroundColor: canSubmit
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
                minimumSize: const Size.square(_slotHeight),
                padding: EdgeInsets.zero,
              ),
              icon: Icon(
                Icons.send_rounded,
                size: IconSizes.toolbar,
                semanticLabel: l10n.chatSend,
              ),
            ),
          );
        }

        if (!pttMode) {
          final Color? bgColor = muted
              ? scheme.errorContainer
              : selfSpeaking
              ? scheme.primaryContainer
              : null;
          final Color fgColor = muted
              ? scheme.onErrorContainer
              : selfSpeaking
              ? scheme.onPrimaryContainer
              : scheme.onSurface;
          return _buildCircleSlot(
            context,
            floating: floating,
            color: bgColor,
            child: Semantics(
              button: true,
              label: muted ? l10n.voiceUnmute : l10n.voiceMute,
              child: AnimatedInkWell(
                customBorder: AppShape.full,
                onTap: () => unawaited(
                  ref.read(sessionViewProvider.notifier).setMuted(!muted),
                ),
                onLongPress: () {
                  HapticFeedback.selectionClick();
                  _switchToVoiceControl();
                },
                child: Center(
                  child: Icon(
                    muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: IconSizes.toolbar,
                    color: fgColor,
                  ),
                ),
              ),
            ),
          );
        }

        final pttActive = _pttOwner != null || selfSpeaking;
        return _buildCircleSlot(
          context,
          floating: floating,
          color: pttActive ? scheme.primary : null,
          child: Semantics(
            button: true,
            label: l10n.voiceHoldToTalk,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _switchToVoiceControl,
              onLongPressStart: (_) {
                HapticFeedback.selectionClick();
                _setPttHeld(true);
              },
              onLongPressEnd: (_) => _setPttHeld(false),
              onLongPressCancel: () => _setPttHeld(false),
              child: Center(
                child: Icon(
                  pttActive ? Icons.mic_rounded : Icons.mic_none_rounded,
                  size: IconSizes.toolbar,
                  color: pttActive ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceLeftButton(
    BuildContext context,
    AppLocalizations l10n, {
    required bool floating,
  }) {
    final scheme = context.scheme;
    return _buildCircleSlot(
      context,
      floating: floating,
      child: IconButton(
        onPressed: _switchToTextInput,
        style: ButtonStyle.from(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.square(_slotHeight),
          padding: EdgeInsets.zero,
        ),
        icon: Badge(
          isLabelVisible: _hasUnread,
          smallSize: 8,
          backgroundColor: scheme.error,
          child: Icon(
            Icons.keyboard_alt_outlined,
            size: IconSizes.toolbar,
            semanticLabel: l10n.chatSwitchToText,
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceCenterCapsule(
    BuildContext context,
    AppLocalizations l10n, {
    required bool floating,
    required bool pttMode,
    required bool muted,
    required bool deafened,
    required bool selfSpeaking,
  }) {
    final scheme = context.scheme;
    if (pttMode) {
      final active = _pttOwner != null || selfSpeaking;
      return SizedBox(
        height: _slotHeight,
        child: _buildSlotSurface(
          context,
          floating: floating,
          shape: AppShape.full,
          glassRadius: AppRadius.full,
          color: active ? scheme.primary : null,
          child: ClipRSuperellipse(
            borderRadius: AppRadius.full,
            child: Semantics(
              button: true,
              label: active ? l10n.voiceTalking : l10n.voiceHoldToTalk,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _setPttHeld(true),
                onPointerUp: (_) => _setPttHeld(false),
                onPointerCancel: (_) => _setPttHeld(false),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active ? Icons.mic_rounded : Icons.mic_none_rounded,
                        size: IconSizes.toolbar,
                        color: active ? scheme.onPrimary : scheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          active ? l10n.voiceTalking : l10n.voiceHoldToTalk,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelLarge?.copyWith(
                            color: active ? scheme.onPrimary : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _slotHeight,
      child: _buildSlotSurface(
        context,
        floating: floating,
        shape: AppShape.full,
        glassRadius: AppRadius.full,
        child: ClipRSuperellipse(
          borderRadius: AppRadius.full,
          child: Row(
            children: [
              Expanded(
                child: _VoiceControlSegment(
                  icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: muted ? l10n.voiceUnmute : l10n.voiceMute,
                  backgroundColor: muted
                      ? scheme.errorContainer
                      : selfSpeaking
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  foregroundColor: muted
                      ? scheme.onErrorContainer
                      : selfSpeaking
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  onTap: () => unawaited(
                    ref.read(sessionViewProvider.notifier).setMuted(!muted),
                  ),
                ),
              ),
              SizedBox(
                width: 1,
                height: 24,
                child: ColoredBox(color: dividerColorOf(context)),
              ),
              Expanded(
                child: _VoiceControlSegment(
                  icon: deafened
                      ? Icons.headset_off_rounded
                      : Icons.headphones_rounded,
                  label: deafened ? l10n.voiceUndeafen : l10n.voiceDeafen,
                  backgroundColor: deafened
                      ? scheme.errorContainer
                      : Colors.transparent,
                  foregroundColor: deafened
                      ? scheme.onErrorContainer
                      : scheme.onSurface,
                  onTap: () => unawaited(
                    ref
                        .read(sessionViewProvider.notifier)
                        .setDeafened(!deafened),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceRightDisconnectButton(
    BuildContext context,
    AppLocalizations l10n, {
    required bool floating,
    required bool sessionBusy,
  }) {
    final scheme = context.scheme;
    return _buildCircleSlot(
      context,
      floating: floating,
      color: scheme.error,
      child: IconButton(
        onPressed: sessionBusy
            ? null
            : () => unawaited(
                ref.read(sessionViewProvider.notifier).disconnect(),
              ),
        style: ButtonStyle.from(
          foregroundColor: scheme.onError,
          minimumSize: const Size.square(_slotHeight),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(
          Icons.call_end_rounded,
          size: IconSizes.toolbar,
          semanticLabel: l10n.serverDisconnect,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final floating = ref.watch(
      preferencesProvider.select((prefs) => prefs.floatingNavigationBar),
    );
    final (:pttMode, :muted, :deafened, :selfSpeaking, :sessionBusy) = ref
        .watch(
          sessionViewProvider.select(
            (view) => (
              pttMode: view.pttMode,
              muted: view.muted,
              deafened: view.deafened,
              selfSpeaking: view.selfSpeaking,
              sessionBusy: view.busy,
            ),
          ),
        );

    ref.listen<bool>(sessionViewProvider.select((view) => view.pttMode), (
      previous,
      next,
    ) {
      if (previous != next && mounted) {
        if (!next) {
          _setPttHeld(false);
        }
        setState(() => _voiceControlMode = next);
      }
    });

    final Widget barRow = AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : Motion.effectsFast,
      switchInCurve: Motion.effectsFastCurve,
      switchOutCurve: Motion.effectsFastCurve.flipped,
      child: _voiceControlMode
          ? Row(
              key: const ValueKey<bool>(true),
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildVoiceLeftButton(context, l10n, floating: floating),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildVoiceCenterCapsule(
                    context,
                    l10n,
                    floating: floating,
                    pttMode: pttMode,
                    muted: muted,
                    deafened: deafened,
                    selfSpeaking: selfSpeaking,
                  ),
                ),
                const SizedBox(width: 8),
                _buildVoiceRightDisconnectButton(
                  context,
                  l10n,
                  floating: floating,
                  sessionBusy: sessionBusy,
                ),
              ],
            )
          : Row(
              key: const ValueKey<bool>(false),
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildTextLeftButton(context, l10n, floating: floating),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextCenterCapsule(
                    context,
                    l10n,
                    floating: floating,
                  ),
                ),
                const SizedBox(width: 8),
                _buildTextRightButton(
                  context,
                  l10n,
                  floating: floating,
                  pttMode: pttMode,
                  muted: muted,
                  selfSpeaking: selfSpeaking,
                ),
              ],
            ),
    );

    final Widget content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.chatContent),
        child: TextFieldTapRegion(child: barRow),
      ),
    );

    if (floating) {
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, math.max(16.0, safeBottom)),
        child: content,
      );
    }

    return Surface(
      color: surfaceColorFor(floatingSurfaceLevelFor(scheme), scheme),
      shape: Border(top: BorderSide(color: dividerColorOf(context))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: content,
        ),
      ),
    );
  }
}

class _VoiceControlSegment extends StatelessWidget {
  const _VoiceControlSegment({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(color: backgroundColor),
          child: AnimatedInkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: IconSizes.medium, color: foregroundColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelLarge?.copyWith(
                        color: foregroundColor,
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

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    this.avatar,
    required this.message,
    required this.onImageTap,
    this.animateEntry = false,
  });

  final ChatMessage message;
  final Widget? avatar;
  final ValueChanged<String> onImageTap;
  final bool animateEntry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar ??
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
                  onImageTap: onImageTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!animateEntry || MediaQuery.disableAnimationsOf(context)) {
      return row;
    }
    return _AnimatedMessageEntry(child: row);
  }
}

class _AnimatedMessageEntry extends StatefulWidget {
  const _AnimatedMessageEntry({required this.child});

  final Widget child;

  @override
  State<_AnimatedMessageEntry> createState() => _AnimatedMessageEntryState();
}

class _AnimatedMessageEntryState extends State<_AnimatedMessageEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.spatialFast,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.spatialCurve,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

class _MeasureDockHeight extends SingleChildRenderObjectWidget {
  const _MeasureDockHeight({
    required this.onHeightChanged,
    required super.child,
  });

  final ValueChanged<double> onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureDockHeight(onHeightChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureDockHeight renderObject,
  ) {
    renderObject.onHeightChanged = onHeightChanged;
  }
}

class _RenderMeasureDockHeight extends RenderProxyBox {
  _RenderMeasureDockHeight(this.onHeightChanged);

  ValueChanged<double> onHeightChanged;
  double? _lastHeight;
  bool _scheduled = false;

  @override
  void detach() {
    _scheduled = false;
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_lastHeight != null && (height - _lastHeight!).abs() <= 0.5) {
      return;
    }
    _lastHeight = height;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached) return;
      final current = _lastHeight;
      if (current != null) {
        onHeightChanged(current);
      }
    });
  }
}
