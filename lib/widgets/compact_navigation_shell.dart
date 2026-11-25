// Adapted from FlClash (be84736, GPL-3.0): lib/pages/home.dart. See docs/THIRD-PARTY.md.

import 'dart:async';

import 'package:material_ui/material_ui.dart'
    hide NavigationBar, NavigationDestination;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/preferences.dart';
import '../core/providers.dart';
import '../features/connect/connect_page.dart';
import '../features/settings/settings_page.dart';
import '../features/workspace/workspace_page.dart';
import '../features/workspace/workspace_shell.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import '../theme/app_theme.dart';
import 'prism.dart';

/// 告知子树当前是否处于窄屏底部导航的根标签页。
class CompactRootTabScope extends InheritedWidget {
  const CompactRootTabScope({
    required this.active,
    this.activeTabIndex = 0,
    this.onExitToHome,
    required super.child,
    super.key,
  });

  final bool active;
  final int activeTabIndex;
  final VoidCallback? onExitToHome;

  static CompactRootTabScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompactRootTabScope>();

  @override
  bool updateShouldNotify(CompactRootTabScope oldWidget) =>
      active != oldWidget.active ||
      activeTabIndex != oldWidget.activeTabIndex ||
      onExitToHome != oldWidget.onExitToHome;
}

/// 为浮动底部导航栏下方的滚动内容传递底部安全留白。
class CompactBottomInsetScope extends InheritedWidget {
  const CompactBottomInsetScope({
    required this.inset,
    required super.child,
    super.key,
  });

  final double inset;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CompactBottomInsetScope>()
          ?.inset ??
      0;

  @override
  bool updateShouldNotify(CompactBottomInsetScope oldWidget) =>
      inset != oldWidget.inset;
}

/// 窄屏（`< 768px`）顶级导航外壳：在「首页」「工作区」与「设置」间淡入淡出切换，
/// 并按 [SessionPreferences.floatingNavigationBar] 在
/// [NavigationDock] 悬浮药丸与 [NavigationBar] 停靠底栏间切换。
class CompactNavigationShell extends ConsumerStatefulWidget {
  const CompactNavigationShell({
    required this.location,
    this.serverId,
    this.onTabSelected,
    super.key,
  });

  final String location;
  final String? serverId;
  final ValueChanged<int>? onTabSelected;

  @override
  ConsumerState<CompactNavigationShell> createState() =>
      _CompactNavigationShellState();
}

class _CompactNavigationShellState
    extends ConsumerState<CompactNavigationShell> {
  static const _tabs = <String>[
    AppRoutes.connect,
    AppRoutes.workspace,
    AppRoutes.settings,
  ];

  late final PageController _pageController;
  late int _currentIndex = _indexForLocation(widget.location);
  List<int>? _order;
  int _transition = 0;

  int _indexForLocation(String location) => switch (location) {
    AppRoutes.workspace => 1,
    AppRoutes.settings => 2,
    _ => 0,
  };

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void didUpdateWidget(covariant CompactNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final nextIndex = _indexForLocation(widget.location);
      if (nextIndex != _currentIndex) {
        unawaited(_toPage(nextIndex));
      }
    }
  }

  Future<void> _toPage(int index, {bool ignoreAnimateTo = false}) async {
    _currentIndex = index;
    final transition = ++_transition;
    final page = _pageController.hasClients
        ? _pageController.page?.round() ?? index
        : index;
    final current = _order?[page] ?? page;
    if (_order != null) {
      setState(() => _order = null);
      _pageController.jumpToPage(current);
    }
    if (ignoreAnimateTo || !_pageController.hasClients) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
      return;
    }
    // 跨过中间页时先置换相邻槽位再切页，避免经过不存在交互意愿的中间页。
    if ((index - current).abs() > 1) {
      final adjacent = index > current ? index - 1 : index + 1;
      setState(() {
        _order = List.generate(_tabs.length, (item) => item)
          ..[adjacent] = current
          ..[current] = adjacent;
      });
      _pageController.jumpToPage(adjacent);
    }
    await _pageController.animateToPage(
      index,
      duration: fadeTabDuration,
      curve: fadeTabCurve,
    );
    if (mounted && transition == _transition && _order != null) {
      setState(() => _order = null);
    }
  }

  void _selectTab(int index) {
    if (index == _currentIndex) {
      return;
    }
    if (widget.onTabSelected != null) {
      widget.onTabSelected!(index);
    }
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(_tabs[index]);
      return;
    }
    unawaited(_toPage(index));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildTabPage(int index) {
    return switch (index) {
      0 => ConnectPage(
        key: const ValueKey<String>(AppRoutes.connect),
        serverId: widget.serverId,
      ),
      1 => const WorkspaceShell(
        key: ValueKey<String>(AppRoutes.workspace),
        location: AppRoutes.workspace,
        child: WorkspacePage(forceCompact: true),
      ),
      _ => const SettingsPage(key: ValueKey<String>(AppRoutes.settings)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final floating = ref.watch(
      preferencesProvider.select((prefs) => prefs.floatingNavigationBar),
    );
    final connected = ref.watch(
      sessionViewProvider.select((view) => view.connected),
    );
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showBottomBar = !keyboardOpen;

    final destinations = <(Glyph, String)>[
      (AppGlyphs.dashboard, l10n.homeTitle),
      (
        connected ? AppGlyphs.workspaceConnected : AppGlyphs.workspace,
        l10n.navWorkspace,
      ),
      (AppGlyphs.settings, l10n.settingsTitle),
    ];

    final pageView = CompactRootTabScope(
      active: true,
      activeTabIndex: _currentIndex,
      onExitToHome: () => _selectTab(0),
      child: CompactBottomInsetScope(
        inset: showBottomBar && floating ? NavigationDock.insetOf(context) : 0,
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: showBottomBar,
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _tabs.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) {
                return null;
              }
              final index = _tabs.indexOf(key.value);
              if (index == -1) {
                return null;
              }
              return _order?.indexOf(index) ?? index;
            },
            itemBuilder: (context, index) {
              final realIndex = _order?[index] ?? index;
              final page = _buildTabPage(realIndex);
              return _FadeTabPage(
                key: page.key,
                controller: _pageController,
                position: index,
                child: page,
              );
            },
          ),
        ),
      ),
    );

    return Surface(
      color: context.pageColor,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: pageView),
                if (floating)
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: AnimatedVisibility.bottomNavigation(
                      visible: showBottomBar,
                      child: BarItemPresence.held(
                        child: _NavigationPadding(
                          child: NavigationDock(
                            destinations: [
                              for (final (glyph, label) in destinations)
                                NavigationDockDestination(
                                  glyph: glyph,
                                  label: label,
                                ),
                            ],
                            selectedIndex: _currentIndex,
                            onSelected: _selectTab,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!floating)
            AnimatedVisibility.bottomNavigation(
              visible: showBottomBar,
              child: _NavigationPadding(
                child: NavigationBar(
                  destinations: [
                    for (final (index, (glyph, label)) in destinations.indexed)
                      NavigationDestination(
                        icon: AnimatedGlyph(
                          glyph: glyph,
                          filled: index == _currentIndex,
                        ),
                        label: label,
                      ),
                  ],
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _selectTab,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavigationPadding extends StatelessWidget {
  const _NavigationPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      removeTop: true,
      removeBottom: false,
      removeLeft: true,
      removeRight: true,
      context: context,
      child: child,
    );
  }
}

const _restingDelta = 0.001;

/// 用快照在原位交叉淡入淡出，取消 PageView 的水平位移，
/// 并保持每一页在切换时状态不丢。
class _FadeTabPage extends StatefulWidget {
  const _FadeTabPage({
    super.key,
    required this.controller,
    required this.position,
    required this.child,
  });

  final PageController controller;
  final int position;
  final Widget child;

  @override
  State<_FadeTabPage> createState() => _FadeTabPageState();
}

class _FadeTabPageState extends State<_FadeTabPage> {
  final _snapshot = SnapshotController();

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  double get _delta {
    final controller = widget.controller;
    if (!controller.hasClients) {
      return 0;
    }
    final metrics = controller.position;
    if (!metrics.hasContentDimensions || metrics.viewportDimension == 0) {
      return 0;
    }
    final page = metrics.pixels / metrics.viewportDimension;
    return (widget.position - page).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (_, child) {
        final offset = _delta;
        _snapshot.allowSnapshotting = offset.abs() > _restingDelta;
        return FractionalTranslation(
          translation: Offset(-offset, 0),
          child: Opacity(opacity: 1 - offset.abs(), child: child),
        );
      },
      child: SnapshotWidget(
        controller: _snapshot,
        mode: SnapshotMode.permissive,
        autoresize: true,
        child: LiquidGlassHost(
          enabled: LiquidGlassScope.of(context),
          child: widget.child,
        ),
      ),
    );
  }
}
