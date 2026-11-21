// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，
// 原始许可证为 GPL-3.0，来源提交 be84736605527034689c95bf27828ff27d912c5e。
// 对应 lib/views/font_family.dart 与 lib/features/form/selection_sheet.dart 中的字体加载队列与搜索选择页。

import 'dart:async';
import 'dart:collection';

import 'package:material_ui/material_ui.dart' hide IconButton;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/system_fonts.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';
import '../../../widgets/window_header.dart';

sealed class _FontChoice {
  const _FontChoice();
}

final class _DefaultFont extends _FontChoice {
  const _DefaultFont();
}

final class _InstalledFont extends _FontChoice {
  const _InstalledFont(this.family);

  final String family;

  @override
  bool operator ==(Object other) =>
      other is _InstalledFont && other.family == family;

  @override
  int get hashCode => family.hashCode;
}

class _FontsIllustration implements Illustration {
  const _FontsIllustration();

  @override
  Glyph get glyph => AppGlyphs.font;

  @override
  bool get isError => false;
}

/// 字体选择面板：在窄屏由 [OpenContainer] 全屏推入，在桌面由 [showSheet] 侧栏打开。
class FontFamilyView extends ConsumerStatefulWidget {
  const FontFamilyView({super.key});

  @override
  ConsumerState<FontFamilyView> createState() => _FontFamilyViewState();
}

class _FontFamilyViewState extends ConsumerState<FontFamilyView> {
  List<_InstalledFont>? _installed;
  late final ScrollController _scrollController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scrollController = sheetScrollController(context);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final families = await loadSystemFontFamilies();
    if (mounted) {
      setState(() => _installed = families.map(_InstalledFont.new).toList());
    }
  }

  void _select(_FontChoice choice) {
    final family = switch (choice) {
      _DefaultFont() => null,
      _InstalledFont(:final family) => family,
    };
    ref.read(preferencesProvider.notifier).setFontFamily(family);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedFamily = ref.watch(
      preferencesProvider.select((prefs) => prefs.fontFamily),
    );
    final _FontChoice selected = selectedFamily == null
        ? const _DefaultFont()
        : _InstalledFont(selectedFamily);

    final installed = _installed ?? const <_InstalledFont>[];
    final trimmed = _query.trim().toLowerCase();
    final matchesDefault =
        trimmed.isEmpty ||
        l10n.settingsFontDefault.toLowerCase().contains(trimmed);
    final filteredInstalled = trimmed.isEmpty
        ? installed
        : [
            for (final item in installed)
              if (item.family.toLowerCase().contains(trimmed)) item,
          ];
    final hasAnyResult = matchesDefault || filteredInstalled.isNotEmpty;
    final sheetType = SheetProvider.of(context)?.type;
    final hasDragHandle = sheetType == SheetType.bottomSheet;
    final useBackIcon = sheetType == null && context.isCompact;

    return Material(
      type: MaterialType.transparency,
      child: Surface(
        color: context.pageColor,
        child: SafeArea(
          child: Column(
            children: [
              if (hasDragHandle) const SheetDragHandle(),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.header),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      TonalButtonTheme(
                        glass: LiquidGlassScope.of(context),
                        child: ElasticPress(
                          child: IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            iconSize: IconSizes.toolbar,
                            icon: Semantics(
                              label: useBackIcon
                                  ? MaterialLocalizations.of(context)
                                        .backButtonTooltip
                                  : MaterialLocalizations.of(context)
                                        .closeButtonTooltip,
                              child: GlyphIcon(
                                useBackIcon
                                    ? Glyphs.backFor(Theme.of(context).platform)
                                    : Glyphs.close,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: WindowDragRegion(
                          child: Semantics(
                            header: true,
                            child: Text(
                              l10n.settingsFontFamily,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.pageTitle.of(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SearchField(
                  hintText: l10n.settingsFontSearch,
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: NullStatusSwitcher(
                  isLoading: _installed == null,
                  isEmpty: !hasAnyResult,
                  holdsArrival: false,
                  loadingStatus: const NullStatus(
                    illustration: _FontsIllustration(),
                  ),
                  nullStatus: NullStatus(
                    illustration: Illustration.search,
                    label: l10n.settingsFontNoResults,
                  ),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      if (matchesDefault)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          sliver: SliverToBoxAdapter(
                            child: generateGroup([
                              _buildFontItem(
                                l10n: l10n,
                                choice: const _DefaultFont(),
                                isSelected: selected == const _DefaultFont(),
                              ),
                            ]),
                          ),
                        ),
                      if (filteredInstalled.isNotEmpty) ...[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          sliver: SliverToBoxAdapter(
                            child: ListHeader(
                              title: l10n.settingsInstalledFonts,
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: SliverPrismList(
                            itemCount: filteredInstalled.length,
                            itemBuilder: (_, index) {
                              final choice = filteredInstalled[index];
                              return _buildFontItem(
                                l10n: l10n,
                                choice: choice,
                                isSelected: choice == selected,
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFontItem({
    required AppLocalizations l10n,
    required _FontChoice choice,
    required bool isSelected,
  }) {
    final label = switch (choice) {
      _DefaultFont() => l10n.settingsFontDefault,
      _InstalledFont(:final family) => family,
    };
    final titleWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return DecorationListItem(
      title: switch (choice) {
        _DefaultFont() => titleWidget,
        _InstalledFont(:final family) => _FontLabel(
          family: family,
          child: titleWidget,
        ),
      },
      isSelected: isSelected,
      trailing: isSelected ? const SelectionCheck() : null,
      onPressed: () => _select(choice),
    );
  }
}

/// 首次排版字体会触发 UI 线程加载字形，尤其 CJK 字体较慢；因此错帧逐个加载，
/// 且在路由转场或列表滚动期间暂缓切换。
class _FontLabel extends StatefulWidget {
  const _FontLabel({required this.family, required this.child});

  final String family;
  final Widget child;

  @override
  State<_FontLabel> createState() => _FontLabelState();
}

class _FontLabelState extends State<_FontLabel> {
  static final _shown = <String>{};
  static final _waiting = Queue<_FontLabelState>();
  static var _scheduled = false;

  bool get _isShown => _shown.contains(widget.family);

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(_FontLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.family != widget.family) {
      _request();
    }
  }

  @override
  void dispose() {
    _waiting.remove(this);
    super.dispose();
  }

  void _request() {
    if (_isShown || _waiting.contains(this)) {
      return;
    }
    _waiting.add(this);
    _schedule();
  }

  static void _schedule() {
    if (_scheduled || _waiting.isEmpty) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback(_showNext)
      ..ensureVisualUpdate();
  }

  static void _showNext(Duration _) {
    final next = _waiting.firstOrNull;
    if (next != null && next.mounted) {
      if (isRouteMoving(next.context)) {
        SchedulerBinding.instance.addPostFrameCallback(_showNext);
        return;
      }
      final scrollPosition = Scrollable.maybeOf(next.context)?.position;
      if (scrollPosition?.isScrollingNotifier.value ?? false) {
        SchedulerBinding.instance
          ..addPostFrameCallback(_showNext)
          ..ensureVisualUpdate();
        return;
      }
    }
    _scheduled = false;
    while (_waiting.isNotEmpty) {
      final label = _waiting.removeFirst();
      if (!label.mounted || label._isShown) {
        continue;
      }
      _shown.add(label.widget.family);
      label.setState(() {});
      break;
    }
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isShown) {
      return widget.child;
    }
    return DefaultTextStyle.merge(
      style: TextStyle(fontFamily: widget.family),
      child: widget.child,
    );
  }
}
