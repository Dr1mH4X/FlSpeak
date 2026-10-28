// 本文件来源于 FlClash（https://github.com/chen08209/FlClash）项目，原始许可证为 GPL-3.0。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7
// 对应原文件：lib/ui/view_scope.dart

import 'package:flutter/widgets.dart';

enum ViewScopeAspect { size, isMobile, windowControls }

/// 窗口尺寸与原生按钮让位的只读范围。
///
/// 页面与侧栏只读这里的 [windowControls]；全屏或窄屏时它的值为零，
/// 让位随窗口状态整体收起。
class ViewScope extends InheritedModel<ViewScopeAspect> {
  const ViewScope({
    super.key,
    required this.size,
    required this.isMobile,
    this.windowControls = Size.zero,
    required super.child,
  });

  final Size size;
  final bool isMobile;

  /// 原生窗口按钮压在页面左上角的区域。
  final Size windowControls;

  static ViewScope? _maybeOf(BuildContext context, ViewScopeAspect aspect) {
    return InheritedModel.inheritFrom<ViewScope>(context, aspect: aspect);
  }

  static Size sizeOf(BuildContext context) =>
      _maybeOf(context, ViewScopeAspect.size)?.size ?? Size.zero;

  static bool isMobileOf(BuildContext context) =>
      _maybeOf(context, ViewScopeAspect.isMobile)?.isMobile ?? false;

  /// 没有 [ViewScope] 的测试环境按零处理，页面维持原有布局。
  static Size windowControlsOf(BuildContext context) =>
      _maybeOf(context, ViewScopeAspect.windowControls)?.windowControls ??
      Size.zero;

  @override
  bool updateShouldNotify(ViewScope oldWidget) =>
      size != oldWidget.size ||
      isMobile != oldWidget.isMobile ||
      windowControls != oldWidget.windowControls;

  @override
  bool updateShouldNotifyDependent(
    ViewScope oldWidget,
    Set<ViewScopeAspect> dependencies,
  ) => dependencies.any(
    (aspect) => switch (aspect) {
      ViewScopeAspect.size => size != oldWidget.size,
      ViewScopeAspect.isMobile => isMobile != oldWidget.isMobile,
      ViewScopeAspect.windowControls =>
        windowControls != oldWidget.windowControls,
    },
  );
}
