import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

/// 连接页左侧窄栏：只有底部设置入口。
///
/// 这里刻意不放删除/退出类操作——连接页不是工作区，底部每多一个破坏性
/// 入口都在赌误触。
class LoginRail extends StatelessWidget {
  const LoginRail({required this.onSettings, super.key});

  static const double width = Sizes.rail;

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return Container(
      width: width,
      color: scheme.surfaceContainer,
      child: Column(
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: IconButton(
              tooltip: l10n.settingsTitle,
              onPressed: onSettings,
              iconSize: 20,
              color: scheme.onSurfaceVariant,
              style: IconButton.styleFrom(
                minimumSize: const Size(Sizes.touch, Sizes.touch),
                maximumSize: const Size(Sizes.touch, Sizes.touch),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.settings_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
