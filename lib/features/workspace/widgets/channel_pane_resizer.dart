import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/pane_resizer.dart';

/// 频道栏与主区域之间的分隔条：拖动调整频道栏宽度，双击恢复默认。
///
/// 内部复用通用的 [PaneResizer]，并在松手与双击时更新 [preferencesProvider]。
class ChannelPaneResizer extends ConsumerWidget {
  const ChannelPaneResizer({
    required this.maxWidth,
    required this.child,
    super.key,
  });

  /// 拖动条自身的可点宽度：细到不抢版面，又要够鼠标点中。
  static const handleWidth = 8.0;

  /// 读屏与键盘每次增减的步长。
  static const step = 16.0;

  /// 拖动条的可击中区域，测试用。
  static const handleKey = ValueKey('channelPaneResizeHandle');

  /// 悬停时浮出的握把，测试用。
  static const gripKey = ValueKey('channelPaneResizeGrip');

  /// 窗口收紧后的上限：主区域至少要留出 [Sizes.mainPaneMin]。
  final double maxWidth;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final storedWidth =
        ref.watch(
          preferencesProvider.select((prefs) => prefs.channelPanelWidth),
        ) ??
        Sizes.channelPanel;

    final upperBound = math.max(
      Sizes.channelPanelMin,
      math.min(Sizes.channelPanelMax, maxWidth),
    );

    return PaneResizer(
      axis: Axis.horizontal,
      size: storedWidth,
      minSize: Sizes.channelPanelMin,
      maxSize: upperBound,
      defaultSize: Sizes.channelPanel,
      step: step,
      handleThickness: handleWidth,
      handleKey: handleKey,
      gripKey: gripKey,
      semanticLabel: l10n.channelPaneResize,
      onSizeChanged: (width) {
        ref.read(preferencesProvider.notifier).setChannelPanelWidth(width);
      },
      onReset: () {
        ref.read(preferencesProvider.notifier).setChannelPanelWidth(null);
      },
      child: child,
    );
  }
}
