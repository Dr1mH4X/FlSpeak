import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_motion.dart';

/// 空状态是行动邀请：说清楚现在缺什么、下一步点哪里。
///
/// 标题可选——调用方已经有标题时不必再写一遍。
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.body,
    this.title,
    this.action,
    this.maxWidth = 360,
    super.key,
  });

  final IconData icon;
  final String? title;
  final String body;
  final Widget? action;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: IconSizes.display,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              if (title != null) ...[
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: context.texts.titleMedium,
                ),
                const SizedBox(height: 6),
              ],
              Text(
                body,
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表分组标题，和设计稿的 `SectionLabel` 同规格（`px-3 pt-5 pb-2 text-xs`）。
class SectionLabel extends StatelessWidget {
  const SectionLabel({required this.label, this.padding, super.key});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(12, 20, 12, 8),
    child: Text(
      label,
      style: context.texts.labelSmall?.copyWith(
        color: context.scheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// 页面级卡片描边：与 [hairlineSide] 同源，浅色靠细线，深色 outlineVariant
/// 全色（M3 divider 规范）。
BoxBorder? cardBorder(BuildContext context) =>
    Border.fromBorderSide(hairlineSide(context));

/// 对话框 / 底部抽屉的统一外壳。
///
/// 设计稿里桌面端是居中卡片、手机端是贴底抽屉，两者共用同一套标题栏、
/// 内容区和操作栏，所以这里只实现一次。
Future<T?> showAppModal<T>(
  BuildContext context, {
  required String title,
  String? description,
  required WidgetBuilder builder,
  WidgetBuilder? footer,
}) {
  final compact = context.isCompact;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  Widget panel(BuildContext context) => _ModalPanel(
    title: title,
    description: description,
    footer: footer,
    child: builder(context),
  );

  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      sheetAnimationStyle: reduceMotion
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Motion.effectsSlow,
              reverseDuration: Motion.effectsDefault,
              curve: Motion.spatialCurve,
            ),
      // M3 scrim：scrim 色压 32%，亮暗主题各自成立。
      barrierColor: context.scheme.scrim.withValues(alpha: 0.32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (context) => Padding(
        // 底部抽屉没有自动避让软键盘：添加服务器的输入框必须跟着键盘上移。
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: panel(context),
      ),
    );
  }

  return Navigator.of(context, rootNavigator: true).push<T>(
    _AppDialogRoute<T>(
      context: context,
      barrierColor: context.scheme.scrim.withValues(alpha: 0.32),
      // 底色与形状交给 dialogTheme（surfaceContainerHigh + xxxl）。
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: Radii.xxxlAll,
          side: BorderSide(color: context.scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 512),
          child: panel(context),
        ),
      ),
    ),
  );
}

class _AppDialogRoute<T> extends DialogRoute<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    required super.barrierColor,
  }) : super(
         themes: InheritedTheme.capture(
           from: context,
           to: Navigator.of(context, rootNavigator: true).context,
         ),
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
         animationStyle: MediaQuery.disableAnimationsOf(context)
             ? AnimationStyle.noAnimation
             : const AnimationStyle(
                 duration: Motion.effectsDefault,
                 reverseDuration: Motion.effectsFast,
               ),
       );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final progress = animation.drive(
      CurveTween(curve: Motion.effectsDefaultCurve),
    );
    return FadeTransition(
      opacity: progress,
      child: ScaleTransition(
        scale: progress.drive(Tween(begin: 0.94, end: 1.0)),
        child: child,
      ),
    );
  }
}

class _ModalPanel extends StatelessWidget {
  const _ModalPanel({
    required this.title,
    required this.description,
    required this.child,
    required this.footer,
  });

  final String title;
  final String? description;
  final Widget child;
  final WidgetBuilder? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (context.isCompact)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, context.isCompact ? 14 : 20, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: context.texts.titleLarge),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        description!,
                        style: context.texts.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                iconSize: IconSizes.toolbar,
                color: scheme.onSurfaceVariant,
                icon: Icon(
                  Icons.close_rounded,
                  semanticLabel: MaterialLocalizations.of(context)
                      .closeButtonTooltip,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: child,
          ),
        ),
        if (footer != null)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [footer!(context)],
            ),
          ),
      ],
    );
  }
}

/// 全应用唯一的二级（弹出）菜单实现，所有弹出菜单都走这里，保证行为一致。
///
/// - 右键菜单：[openOnSecondaryTap] 为 true 时在触发点弹出；[enabled] 为
///   false 不响应右键（比如未连接的服务器、自己已在的频道）。
/// - 按钮打开：[openOnSecondaryTap] 保持 false，[builder] 里拿到控制器，
///   由子组件决定打开时机（比如「更多」按钮）。
class SecondaryMenu extends StatelessWidget {
  const SecondaryMenu({
    required this.items,
    required this.builder,
    this.openOnSecondaryTap = false,
    this.enabled = true,
    super.key,
  });

  /// 菜单项，一般是 [MenuItemButton]。
  final List<Widget> items;

  /// 菜单锚定的内容；[MenuController] 供子组件按需打开菜单。
  final Widget Function(BuildContext context, MenuController controller)
  builder;

  final bool openOnSecondaryTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      clipBehavior: Clip.antiAlias,
      menuChildren: items,
      builder: (context, controller, child) {
        final content = builder(context, controller);
        if (!openOnSecondaryTap) {
          return content;
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp: enabled
              ? (details) => controller.open(position: details.localPosition)
              : null,
          child: content,
        );
      },
    );
  }
}

/// 页面级卡片家族：cardColor + xxl(29) 圆角 + 发丝描边 + 轻投影。
///
/// 连接页身份卡、服务器列表、添加行与设置卡共用，圆角/描边/投影只在这里
/// 定义一次。[clip] 给行高亮贴边的列表用——裁到圆角内，条目的可见圆角
/// 永远属于卡片本身（同心圆角的外层裁剪做法）。
///
/// 圆角取 xxl 而非 xxxl：家族里最矮的成员（添加行 ≈56 高）在 35 下会被
/// 钳制成胶囊，页面上高矮卡片就渲染不出同一条弧；半径 ≤ 最矮卡的半高，
/// 所有卡片才能圆角对齐。
class HairlineCard extends StatelessWidget {
  const HairlineCard({required this.child, this.clip = false, super.key});

  final Widget child;

  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: Radii.xxlAll,
        border: Border.fromBorderSide(hairlineSide(context)),
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
