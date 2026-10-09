import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'widgets/server_rail.dart';

/// 进入之后的固定外壳：左侧服务器栏 + 右侧内容。
///
/// 只有工作区与设置用这个外壳；连接界面是应用打开时的独立表面。
class WorkspaceShell extends ConsumerWidget {
  const WorkspaceShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final notice = ref.watch(sessionViewProvider.select((view) => view.notice));
    final wantsExpanded = ref.watch(railExpandedProvider);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.compact;

    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServerRail(
              location: location,
              expanded: wantsExpanded && wide,
              onToggle: () => ref.read(railExpandedProvider.notifier).toggle(),
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: NoticeBar(
                        message: notice,
                        dismissTooltip: l10n.commonClose,
                        onDismiss: ref
                            .read(sessionViewProvider.notifier)
                            .dismissNotice,
                      ),
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
