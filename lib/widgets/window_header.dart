// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，
// 原始许可证为 GPL-3.0。来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 片段对应 lib/manager/window_manager.dart 的 WindowHeaderContainer /
// WindowHeaderLayout / WindowHeaderBar / WindowHeader / WindowHeaderActions，
// 以及 lib/ui/scaffold.dart 的 _WindowControlsClearance。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/window_chrome.dart';
import '../core/window_metrics.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'caption_icon.dart';
import 'view_scope.dart';

/// 桌面端顶栏容器：
/// - macOS 窄屏显示 28px 标题条；宽屏由侧栏顶部避让红绿灯。
/// - Windows 始终显示 32px 顶栏，并在右侧放置窗口控制按钮。
class WindowHeaderContainer extends StatelessWidget {
  const WindowHeaderContainer({
    super.key,
    required this.isMacOS,
    this.isWindows = false,
    required this.isMobileView,
    required this.child,
  });

  final bool isMacOS;
  final bool isWindows;
  final bool isMobileView;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showsWindowHeader(
      isMacOS: isMacOS,
      isWindows: isWindows,
      isMobileView: isMobileView,
    )) {
      return child;
    }
    final l10n = AppLocalizations.of(context);
    final height = getWindowHeaderHeight(isMacOS: isMacOS);
    return WindowHeaderLayout(
      height: height,
      header: WindowHeader(
        isWindows: isWindows,
        title: isMacOS
            ? Text(
                l10n.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
      ),
      child: child,
    );
  }
}

class WindowHeaderLayout extends StatelessWidget {
  const WindowHeaderLayout({
    super.key,
    required this.height,
    required this.header,
    required this.child,
  });

  final double height;
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            SizedBox(height: height),
            Expanded(child: child),
          ],
        ),
        Positioned(top: 0, left: 0, right: 0, child: header),
      ],
    );
  }
}

class WindowHeader extends StatelessWidget {
  const WindowHeader({super.key, this.title, this.isWindows = false});

  final Widget? title;
  final bool isWindows;

  @override
  Widget build(BuildContext context) {
    final height = getWindowHeaderHeight(isMacOS: !isWindows);
    return WindowHeaderBar(
      height: height,
      onDragStart: () => unawaited(WindowChrome.startDragging()),
      onDoubleTap: () => unawaited(
        isWindows ? WindowChrome.toggleMaximize() : WindowChrome.toggleZoom(),
      ),
      title: title,
      actions: isWindows ? const WindowHeaderActions() : null,
    );
  }
}

class WindowHeaderBar extends StatelessWidget {
  const WindowHeaderBar({
    super.key,
    required this.height,
    required this.onDragStart,
    required this.onDoubleTap,
    this.title,
    this.actions,
  });

  final double height;
  final VoidCallback onDragStart;
  final VoidCallback onDoubleTap;
  final Widget? title;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final color = _chromeSurface(context);
    return Material(
      color: color,
      shape: Border(bottom: Divider.createBorderSide(context)),
      child: SizedBox(
        height: height,
        child: Stack(
          alignment: AlignmentDirectional.center,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => onDragStart(),
                onDoubleTap: onDoubleTap,
                child: ColoredBox(color: color),
              ),
            ),
            if (title != null)
              Positioned.fill(
                child: IgnorePointer(child: Center(child: title)),
              ),
            if (actions != null)
              Positioned(top: 0, bottom: 0, right: 0, child: actions!),
          ],
        ),
      ),
    );
  }
}

/// Windows 顶栏右侧的操作按钮（置顶 Pin、最小化、最大化/还原、关闭）。
class WindowHeaderActions extends StatelessWidget {
  const WindowHeaderActions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final height = getWindowHeaderHeight(isMacOS: false);
    final buttonSize = getCaptionButtonSize(height);

    return ListenableBuilder(
      listenable: Listenable.merge([
        WindowChrome.isPinned,
        WindowChrome.isMaximized,
        WindowChrome.fullScreen,
      ]),
      builder: (context, _) {
        final isPinned = WindowChrome.isPinned.value;
        final isMaximized = WindowChrome.isMaximized.value;
        final isFullScreen = WindowChrome.fullScreen.value;

        final (maximizeGlyph, maximizeLabel) = switch ((
          isMaximized,
          isFullScreen,
        )) {
          (true, _) || (_, true) => (CaptionGlyph.restore, l10n.windowRestore),
          _ => (CaptionGlyph.maximize, l10n.windowMaximize),
        };

        return IconButtonTheme(
          data: IconButtonThemeData(
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: WidgetStatePropertyAll(buttonSize),
              maximumSize: WidgetStatePropertyAll(buttonSize),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              foregroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Semantics(
                  label: isPinned ? l10n.windowUnpin : l10n.windowPin,
                  button: true,
                  child: IconButton(
                    style: ButtonStyle(
                      shape: const WidgetStatePropertyAll(CircleBorder()),
                      minimumSize: const WidgetStatePropertyAll(Size.zero),
                      maximumSize: const WidgetStatePropertyAll(Size.infinite),
                      iconSize: const WidgetStatePropertyAll(pinIconSize),
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (isPinned) {
                          return Theme.of(context)
                              .colorScheme
                              .secondaryContainer;
                        }
                        return null;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (isPinned) {
                          return Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer;
                        }
                        return null;
                      }),
                    ),
                    onPressed: () => unawaited(WindowChrome.togglePin()),
                    icon: Icon(
                      isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                  ),
                ),
              ),
              Semantics(
                label: l10n.windowMinimize,
                button: true,
                child: IconButton(
                  onPressed: () => unawaited(WindowChrome.minimize()),
                  icon: const CaptionIcon(CaptionGlyph.minimize),
                ),
              ),
              Semantics(
                label: maximizeLabel,
                button: true,
                child: IconButton(
                  onPressed: () => unawaited(WindowChrome.toggleMaximize()),
                  icon: CaptionIcon(maximizeGlyph),
                ),
              ),
              Semantics(
                label: l10n.commonClose,
                button: true,
                child: IconButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      final active =
                          states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.pressed);
                      return active
                          ? Theme.of(context).colorScheme.error
                          : null;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      final active =
                          states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.pressed);
                      return active
                          ? Theme.of(context).colorScheme.onError
                          : null;
                    }),
                    overlayColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.pressed)
                          ? Theme.of(context).colorScheme.onError
                                .withValues(alpha: 0.12)
                          : Colors.transparent;
                    }),
                  ),
                  onPressed: () => unawaited(WindowChrome.close()),
                  icon: const CaptionIcon(CaptionGlyph.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 宽屏没有标题条时，把侧栏顶部留白与通栏页面顶栏接到同一套拖拽手势。
class WindowDragRegion extends StatelessWidget {
  const WindowDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => unawaited(WindowChrome.startDragging()),
      onDoubleTap: () => unawaited(WindowChrome.toggleZoom()),
      child: child,
    );
  }
}

/// 通栏页面（设置页）在窗口左上角给红绿灯让出横向空间。
class WindowControlsClearance extends StatelessWidget {
  const WindowControlsClearance({super.key, required this.child});

  final Widget child;

  static bool _fillsWindow(BuildContext context) {
    final route = ModalRoute.of(context);
    return route != null &&
        route.opaque &&
        !route.isFirst &&
        route.navigator == Navigator.maybeOf(context, rootNavigator: true);
  }

  @override
  Widget build(BuildContext context) {
    final controls = ViewScope.windowControlsOf(context);
    if (controls.isEmpty || !_fillsWindow(context)) {
      return child;
    }
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: padding.copyWith(left: math.max(padding.left, controls.width)),
      ),
      child: child,
    );
  }
}

Color _chromeSurface(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.brightness == Brightness.dark
      ? scheme.surfaceContainerLow
      : scheme.surfaceContainerHighest;
}
