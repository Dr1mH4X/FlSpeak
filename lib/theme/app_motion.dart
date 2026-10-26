import 'package:flutter/animation.dart';

/// Material 3 动效 token：M3 Expressive 的弹簧物理系统在 Flutter 上没有官方
/// 实现，按规范用曲线模拟弹簧（m3.material.io/styles/motion/overview/specs
/// 「Web: Convert springs to curves」换算表），数值逐条来自该表。
///
/// FlSpeak 是工具型产品，按规范整体走 **standard scheme**（minimal bounce）；
/// expressive 曲线只留给强调时刻备用。速度分配沿用规范：fast 给小组件
/// （按钮、开关、行内状态），default 给占半屏的容器（抽屉、侧栏、页签内容），
/// slow 给全屏切换。
abstract final class Motion {
  /// effects：颜色与透明度动画，规范要求无回弹，三档曲线各不相同。
  static const effectsFast = Duration(milliseconds: 150);
  static const effectsDefault = Duration(milliseconds: 200);
  static const effectsSlow = Duration(milliseconds: 300);

  /// spatial：位移与尺寸动画，standard 三档共用同一条轻微回弹曲线，
  /// 只有时长差别。
  static const spatialFast = Duration(milliseconds: 350);
  static const spatialDefault = Duration(milliseconds: 500);
  static const spatialSlow = Duration(milliseconds: 750);

  /// standard fast effects：`cubic-bezier(0.31, 0.94, 0.34, 1.00)`。
  static const effectsFastCurve = Cubic(0.31, 0.94, 0.34, 1.00);

  /// standard default effects：`cubic-bezier(0.34, 0.80, 0.34, 1.00)`。
  static const effectsDefaultCurve = Cubic(0.34, 0.80, 0.34, 1.00);

  /// standard slow effects：`cubic-bezier(0.34, 0.88, 0.34, 1.00)`。
  static const effectsSlowCurve = Cubic(0.34, 0.88, 0.34, 1.00);

  /// standard spatial（fast/default/slow 共用）：`cubic-bezier(0.27, 1.06, 0.18, 1.00)`。
  static const spatialCurve = Cubic(0.27, 1.06, 0.18, 1.00);

  /// expressive fast spatial：`cubic-bezier(0.42, 1.67, 0.21, 0.90)`，350ms。
  /// 终值上冲明显，只用于需要强调的时刻（hero 元素），日常动画不要用。
  static const expressiveSpatialCurve = Cubic(0.42, 1.67, 0.21, 0.90);
}
