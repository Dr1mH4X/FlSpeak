// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，
// 原始许可证为 GPL-3.0。来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 片段对应 lib/manager/window_manager.dart 的 WindowHeaderContainer /
// WindowHeaderLayout / WindowHeaderBar / WindowHeader，以及 lib/ui/scaffold.dart
// 的 _WindowControlsClearance。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/window_chrome.dart';
import '../core/window_metrics.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'view_scope.dart';

/// 窄屏上的 28px 标题条；宽屏不画标题条，页面直接铺到窗口上沿。
class WindowHeaderContainer extends StatelessWidget {
  const WindowHeaderContainer({
    super.key,
    required this.isMacOS,
    required this.isMobileView,
    required this.child,
  });

  final bool isMacOS;
  final bool isMobileView;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showsWindowHeader(isMacOS: isMacOS, isMobileView: isMobileView)) {
      return child;
    }
    final l10n = AppLocalizations.of(context);
    return WindowHeaderLayout(
      height: getWindowHeaderHeight(isMacOS: isMacOS),
      header: WindowHeader(
        title: Text(
          l10n.appName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.bodyMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
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
  const WindowHeader({super.key, required this.title});

  final Widget title;

  @override
  Widget build(BuildContext context) {
    return WindowHeaderBar(
      height: getWindowHeaderHeight(isMacOS: true),
      onDragStart: () => unawaited(WindowChrome.startDragging()),
      onDoubleTap: () => unawaited(WindowChrome.toggleZoom()),
      title: title,
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
  });

  final double height;
  final VoidCallback onDragStart;
  final VoidCallback onDoubleTap;
  final Widget? title;

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
          ],
        ),
      ),
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
