import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 有新版本时使用的提示点。
///
/// 颜色只作辅助，语义由 [semanticLabel] 提供；放在可点击链接内部时由外层
/// `Semantics` 统一描述，传 null 即可避免重复朗读。
class UpdateDot extends StatelessWidget {
  const UpdateDot({
    this.semanticLabel,
    this.size = 8,
    this.borderColor,
    super.key,
  });

  final String? semanticLabel;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.scheme.error,
        shape: BoxShape.circle,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 1.5),
      ),
    );
    final label = semanticLabel;
    if (label == null) {
      return ExcludeSemantics(child: dot);
    }
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: dot),
    );
  }
}
