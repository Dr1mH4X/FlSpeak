import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/identity/identity.dart';
import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

/// 连接页大字问候的候选句。Provider 生命周期内只随机一次。
enum ConnectPrompt { whereToChat, whatToDo, hopIn }

final connectPromptProvider = Provider<ConnectPrompt>((ref) {
  return ConnectPrompt.values[Random().nextInt(ConnectPrompt.values.length)];
});

enum ConnectDayPeriod { morning, afternoon, evening, lateNight }

ConnectDayPeriod connectDayPeriodAt(DateTime time) {
  final hour = time.hour;
  if (hour >= 5 && hour < 12) {
    return ConnectDayPeriod.morning;
  }
  if (hour >= 12 && hour < 18) {
    return ConnectDayPeriod.afternoon;
  }
  if (hour >= 18) {
    return ConnectDayPeriod.evening;
  }
  return ConnectDayPeriod.lateNight;
}

DateTime _nextPeriodBoundary(DateTime time) {
  final int nextHour;
  final int dayOffset;
  if (time.hour < 5) {
    nextHour = 5;
    dayOffset = 0;
  } else if (time.hour < 12) {
    nextHour = 12;
    dayOffset = 0;
  } else if (time.hour < 18) {
    nextHour = 18;
    dayOffset = 0;
  } else {
    nextHour = 0;
    dayOffset = 1;
  }
  return DateTime(time.year, time.month, time.day + dayOffset, nextHour);
}

/// 连接页顶部的动态问候：上方按时段与身份署名，下方随机一句行动提示。
class ConnectGreeting extends ConsumerStatefulWidget {
  const ConnectGreeting({super.key});

  @override
  ConsumerState<ConnectGreeting> createState() => _ConnectGreetingState();
}

class _ConnectGreetingState extends ConsumerState<ConnectGreeting> {
  Timer? _periodTimer;

  @override
  void initState() {
    super.initState();
    _schedulePeriodRefresh();
  }

  @override
  void dispose() {
    _periodTimer?.cancel();
    super.dispose();
  }

  void _schedulePeriodRefresh() {
    _periodTimer?.cancel();
    final now = ref.read(clockProvider)();
    final boundary = _nextPeriodBoundary(now);
    _periodTimer = Timer(boundary.difference(now), () {
      if (!mounted) {
        return;
      }
      setState(() {});
      _schedulePeriodRefresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final identity = ref.watch(activeIdentityProvider);
    final prompt = ref.watch(connectPromptProvider);
    final hasConnectionHistory = ref.watch(
      preferencesProvider.select((prefs) => prefs.lastConnected.isNotEmpty),
    );
    final now = ref.watch(clockProvider)();

    final greeting = identity.hasExplicitNickname
        ? switch (connectDayPeriodAt(now)) {
            ConnectDayPeriod.morning => l10n.connectGreetingMorning(
              identity.nickname,
            ),
            ConnectDayPeriod.afternoon => l10n.connectGreetingAfternoon(
              identity.nickname,
            ),
            ConnectDayPeriod.evening => l10n.connectGreetingEvening(
              identity.nickname,
            ),
            ConnectDayPeriod.lateNight => l10n.connectGreetingLateNight(
              identity.nickname,
            ),
          }
        : hasConnectionHistory
        ? l10n.connectGreetingWelcomeBack
        : l10n.connectGreetingHello;
    final promptText = switch (prompt) {
      ConnectPrompt.whereToChat => l10n.connectPromptWhere,
      ConnectPrompt.whatToDo => l10n.connectPromptDoing,
      ConnectPrompt.hopIn => l10n.connectPromptHopIn,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          greeting,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(promptText, style: context.texts.displaySmall),
      ],
    );
  }
}
