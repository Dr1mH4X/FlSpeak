import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../core/voice_levels.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/signal_ribbon.dart';

/// 所选声源的响度历史；电平与连接标记只重建这块画布，并在后台/遮挡时休眠。
class VoiceActivityRibbon extends ConsumerStatefulWidget {
  const VoiceActivityRibbon({super.key});

  @override
  ConsumerState<VoiceActivityRibbon> createState() =>
      _VoiceActivityRibbonState();
}

class _VoiceActivityRibbonState extends ConsumerState<VoiceActivityRibbon>
    with WidgetsBindingObserver {
  bool _isForeground = true;
  bool _isTickerEnabled = true;
  ProviderSubscription<AsyncValue<VoiceLevels>>? _levelsSub;
  VoiceLevels _levels = VoiceLevels.silent;

  bool get _isActive => _isForeground && _isTickerEnabled;

  static bool _isLifecycleVisible(AppLifecycleState? state) => switch (state) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
    AppLifecycleState.resumed || AppLifecycleState.inactive || null => true,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground = _isLifecycleVisible(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isTickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncListening(notify: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = _isLifecycleVisible(state);
    if (_isForeground == isForeground) {
      return;
    }
    _isForeground = isForeground;
    _syncListening(notify: true);
  }

  void _syncListening({required bool notify}) {
    if (_isActive) {
      if (_levelsSub != null) {
        return;
      }
      var firingImmediately = true;
      _levelsSub = ref.listenManual<AsyncValue<VoiceLevels>>(
        voiceLevelsProvider,
        (_, next) {
          final levels = next.value;
          if (levels == null || !mounted || identical(levels, _levels)) {
            return;
          }
          if (firingImmediately && !notify) {
            _levels = levels;
            return;
          }
          setState(() => _levels = levels);
        },
        fireImmediately: true,
      );
      firingImmediately = false;
      if (notify && mounted) {
        setState(() {});
      }
      return;
    }

    final hadSub = _levelsSub != null;
    _levelsSub?.close();
    _levelsSub = null;
    if ((hadSub || !identical(_levels, VoiceLevels.silent)) &&
        notify &&
        mounted) {
      setState(() => _levels = VoiceLevels.silent);
    } else {
      _levels = VoiceLevels.silent;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _levelsSub?.close();
    _levelsSub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(
      preferencesProvider.select((prefs) => prefs.voiceMeterSource),
    );
    final connection = ref.watch(
      sessionViewProvider.select(
        (view) => (
          connected: view.connected,
          serverId: view.activeServerId,
          epoch: view.connectionEpoch,
        ),
      ),
    );
    return ExcludeSemantics(
      child: _Ribbon(
        key: ValueKey((connection.serverId, connection.epoch)),
        levels: _isActive ? _levels : VoiceLevels.silent,
        source: source,
        connected: connection.connected && _isActive,
      ),
    );
  }
}

class _Ribbon extends StatefulWidget {
  const _Ribbon({
    required this.levels,
    required this.source,
    required this.connected,
    super.key,
  });

  final VoiceLevels levels;
  final VoiceMeterSource source;
  final bool connected;

  @override
  State<_Ribbon> createState() => _RibbonState();
}

class _RibbonState extends State<_Ribbon> {
  static const _historyLength = 24;

  /// 最近约 480ms 的电平，每个新读数左移一格。
  List<double> _history = List.filled(_historyLength, 0);

  double get _level => !widget.connected
      ? 0
      : widget.source == VoiceMeterSource.microphone
      ? widget.levels.mic
      : widget.levels.received;

  @override
  void initState() {
    super.initState();
    _history = [..._history.skip(1), _level.clamp(0.0, 1.0).toDouble()];
  }

  @override
  void didUpdateWidget(covariant _Ribbon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.connected) {
      _history = List.filled(_historyLength, 0);
      return;
    }
    final switched = widget.source != oldWidget.source;
    if (switched) {
      _history = List.filled(_historyLength, 0);
    }
    // 每个电平事件都是新对象；其他无关重建保持同一对象，
    // 不会把历史推快。
    if (switched || !identical(widget.levels, oldWidget.levels)) {
      _history = [..._history.skip(1), _level.clamp(0.0, 1.0).toDouble()];
    }
  }

  @override
  Widget build(BuildContext context) {
    // 音频线程已经完成平滑；界面直接绘制，避免插值再次延迟峰值。
    return SignalRibbon(values: _history, color: context.scheme.primary);
  }
}
