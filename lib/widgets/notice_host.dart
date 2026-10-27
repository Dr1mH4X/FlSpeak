import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notices.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// 页面级提示的唯一宿主：窗口右上角的覆盖层。
///
/// 提示不参与页面布局，出现与消失只改变自己的堆叠高度；没有提示时只留下
/// 安全区留白，不拦截点击。
class NoticeHost extends ConsumerWidget {
  const NoticeHost({super.key});

  static const _maxWidth = 380.0;
  static const _errorLinger = Duration(seconds: 8);
  static const _infoLinger = Duration(seconds: 5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticeCenterProvider);
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final compact = size.width < Breakpoints.compact;
    final top = safe.top + (compact ? 8.0 : 12.0);
    final right = safe.right + (compact ? 16.0 : 24.0);
    final width = math.min(_maxWidth, math.max(0.0, size.width - right - 16));

    return Padding(
      padding: EdgeInsets.only(top: top, right: right),
      child: SizedBox(
        width: width,
        child: _NoticeStack(
          notices: notices,
          onDismiss: (id) =>
              ref.read(noticeCenterProvider.notifier).dismiss(id),
        ),
      ),
    );
  }
}

/// 新到旧的提示列。用 [AnimatedList] 只让增删的那一条动，其余保持原位。
class _NoticeStack extends StatefulWidget {
  const _NoticeStack({required this.notices, required this.onDismiss});

  final List<AppNotice> notices;
  final ValueChanged<int> onDismiss;

  @override
  State<_NoticeStack> createState() => _NoticeStackState();
}

class _NoticeStackState extends State<_NoticeStack> {
  final _listKey = GlobalKey<AnimatedListState>();
  late final List<AppNotice> _items = [...widget.notices];

  @override
  void didUpdateWidget(covariant _NoticeStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(widget.notices);
  }

  void _sync(List<AppNotice> next) {
    final targetIds = {for (final notice in next) notice.id};

    // 先按索引从大到小移除，后续索引不会因删除而漂移。
    for (var index = _items.length - 1; index >= 0; index--) {
      final notice = _items[index];
      if (targetIds.contains(notice.id)) {
        continue;
      }
      _items.removeAt(index);
      _listKey.currentState?.removeItem(
        index,
        (context, animation) => _item(context, notice, animation),
        duration: _animationDuration(context),
      );
    }

    for (var index = 0; index < next.length; index++) {
      final notice = next[index];
      if (_items.any((item) => item.id == notice.id)) {
        continue;
      }
      _items.insert(index, notice);
      _listKey.currentState?.insertItem(
        index,
        duration: _animationDuration(context),
      );
    }
  }

  Duration _animationDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Motion.effectsFast;

  Widget _item(
    BuildContext context,
    AppNotice notice,
    Animation<double> animation,
  ) {
    final curved = animation.drive(CurveTween(curve: Motion.effectsFastCurve));
    return SizeTransition(
      key: ValueKey(notice.id),
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curved,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _NoticeCard(
            notice: notice,
            onDismiss: () => widget.onDismiss(notice.id),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      // 提示列不需要滚动，也不该在桌面端为它画出滚动条。
      behavior: const _NoScrollbarBehavior(),
      child: AnimatedList(
        key: _listKey,
        initialItemCount: _items.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemBuilder: (context, index, animation) =>
            _item(context, _items[index], animation),
      ),
    );
  }
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class _NoticeCard extends StatefulWidget {
  const _NoticeCard({required this.notice, required this.onDismiss});

  final AppNotice notice;
  final VoidCallback onDismiss;

  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard> {
  Timer? _timer;
  var _hovered = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_hovered || _focused) {
      return;
    }
    final linger = widget.notice.tone == NoticeTone.error
        ? NoticeHost._errorLinger
        : NoticeHost._infoLinger;
    _timer = Timer(linger, _dismiss);
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    _hovered = hovered;
    _restartTimer();
  }

  void _setFocused(bool focused) {
    if (_focused == focused) {
      return;
    }
    _focused = focused;
    _restartTimer();
  }

  void _dismiss() {
    _timer?.cancel();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final error = widget.notice.tone == NoticeTone.error;
    final background = error
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = error
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    final icon = error
        ? Icons.error_outline_rounded
        : Icons.info_outline_rounded;
    final closeLabel = MaterialLocalizations.of(context).closeButtonTooltip;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Focus(
        onFocusChange: _setFocused,
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Material(
            color: background,
            surfaceTintColor: Colors.transparent,
            elevation: 3,
            borderRadius: Radii.xlAll,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: ExcludeSemantics(
                      child: Icon(icon, size: 16, color: foreground),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      widget.notice.message,
                      style: context.texts.bodySmall?.copyWith(
                        fontSize: 13,
                        color: foreground,
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: Sizes.touch,
                    child: IconButton(
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      color: foreground,
                      onPressed: _dismiss,
                      icon: Icon(
                        Icons.close_rounded,
                        semanticLabel: closeLabel,
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
