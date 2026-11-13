import 'package:flutter/material.dart' hide ButtonStyle, IconButton;

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'prism.dart';

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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
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
      builder: (context) => ElevatedSurfaceTheme(
        child: SurfaceScope(
          level: SurfaceLevel.page,
          child: Padding(
            // 底部抽屉没有自动避让软键盘：添加服务器的输入框必须跟着键盘上移。
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: panel(context),
          ),
        ),
      ),
    );
  }

  final floatingLevel = floatingSurfaceLevelFor(context.scheme);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _AppDialogRoute<T>(
      context: context,
      barrierColor: context.scheme.scrim.withValues(alpha: 0.32),
      builder: (context) => ElevatedSurfaceTheme(
        child: Builder(
          builder: (context) => Dialog(
            backgroundColor: surfaceColorFor(floatingLevel, context.scheme),
            shape: AppShape.all(AppCorner.alert),
            clipBehavior: Clip.antiAlias,
            child: SurfaceScope(
              level: floatingLevel,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 512),
                child: panel(context),
              ),
            ),
          ),
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
              decoration: ShapeDecoration(
                color: dividerColorOf(context),
                shape: AppShape.full,
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
              ElasticButton(
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  iconSize: IconSizes.toolbar,
                  style: ButtonStyle.from(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    semanticLabel: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                  ),
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
              border: Border(top: BorderSide(color: dividerColorOf(context))),
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
/// - 小屏「更多」按钮：传入 [moreSemanticLabel] 时，仅在窄屏（`< 768`）行尾
///   渲染竖向三点按钮，并锚定在按钮自身位置打开菜单；桌面宽屏不渲染三点按钮，
///   直接由整行右键呼出。
/// - 按钮打开：[openOnSecondaryTap] 保持 false，[builder] 里拿到控制器，
///   由子组件决定打开时机。
class SecondaryMenu extends StatelessWidget {
  const SecondaryMenu({
    required this.items,
    required this.builder,
    this.openOnSecondaryTap = false,
    this.enabled = true,
    this.moreSemanticLabel,
    this.morePadding = EdgeInsets.zero,
    super.key,
  });

  /// 菜单项，一般是 [MenuItemButton]。
  final List<Widget> items;

  /// 菜单锚定的内容；[MenuController] 供子组件按需打开菜单。
  final Widget Function(BuildContext context, MenuController controller)
  builder;

  final bool openOnSecondaryTap;
  final bool enabled;

  /// 非空时在窄屏（[AppSchemeOf.isCompact]）行尾追加竖向三点按钮。
  final String? moreSemanticLabel;

  /// 窄屏三点按钮的外边距。
  final EdgeInsetsGeometry morePadding;

  @override
  Widget build(BuildContext context) {
    final showMore = moreSemanticLabel != null && context.isCompact;
    return MenuAnchor(
      clipBehavior: Clip.antiAlias,
      menuChildren: items,
      builder: (anchorContext, controller, child) {
        Widget content = builder(anchorContext, controller);
        if (showMore) {
          content = Row(
            children: [
              Expanded(child: content),
              Padding(
                padding: morePadding,
                child: Builder(
                  builder: (buttonContext) => IconButton(
                    onPressed: !enabled
                        ? null
                        : () {
                            if (controller.isOpen) {
                              controller.close();
                              return;
                            }
                            final buttonBox =
                                buttonContext.findRenderObject() as RenderBox?;
                            final anchorBox =
                                anchorContext.findRenderObject() as RenderBox?;
                            final position =
                                (buttonBox != null && anchorBox != null)
                                ? buttonBox.localToGlobal(
                                    Offset(0, buttonBox.size.height),
                                    ancestor: anchorBox,
                                  )
                                : null;
                            controller.open(position: position);
                          },
                    iconSize: IconSizes.medium,
                    style: ButtonStyle.from(
                      minimumSize: const Size(Sizes.touch, Sizes.touch),
                      maximumSize: const Size(Sizes.touch, Sizes.touch),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      semanticLabel: moreSemanticLabel,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
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
