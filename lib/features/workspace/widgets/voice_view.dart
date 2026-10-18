import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';

/// 频道里的语音状态：未加入时邀请加入，加入后展示成员格子与语音控制。
///
/// mute/deafen/PTT 都走 Rust 后端；摄像头、共享屏幕、离开语音没有后端，
/// 所以这里不提供——TS 里换频道就是离开一个语音频道。
class VoiceView extends StatelessWidget {
  const VoiceView({
    required this.channelName,
    required this.members,
    required this.joined,
    required this.busy,
    required this.muted,
    required this.deafened,
    required this.inputReady,
    required this.outputReady,
    required this.speaking,
    required this.selfSpeaking,
    required this.pttMode,
    required this.pttActive,
    required this.voiceNotice,
    required this.canRejoinLast,
    required this.onJoin,
    required this.onToggleMute,
    required this.onToggleDeafen,
    required this.onTogglePttMode,
    required this.onPttDown,
    required this.onPttUp,
    required this.onRejoinLast,
    required this.onDismissVoiceNotice,
    super.key,
  });

  final String channelName;
  final List<ClientView> members;
  final bool joined;
  final bool busy;
  final bool muted;
  final bool deafened;
  final bool inputReady;
  final bool outputReady;
  final Set<int> speaking;
  final bool selfSpeaking;
  final bool pttMode;
  final bool pttActive;
  final String? voiceNotice;
  final bool canRejoinLast;
  final VoidCallback onJoin;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleDeafen;
  final VoidCallback onTogglePttMode;
  final VoidCallback onPttDown;
  final VoidCallback onPttUp;
  final VoidCallback onRejoinLast;
  final VoidCallback onDismissVoiceNotice;

  @override
  Widget build(BuildContext context) {
    if (!joined) {
      return _VoiceJoin(
        channelName: channelName,
        members: members,
        busy: busy,
        onJoin: onJoin,
      );
    }
    return _VoiceRoom(
      members: members,
      muted: muted,
      deafened: deafened,
      inputReady: inputReady,
      outputReady: outputReady,
      speaking: speaking,
      selfSpeaking: selfSpeaking,
      pttMode: pttMode,
      pttActive: pttActive,
      voiceNotice: voiceNotice,
      canRejoinLast: canRejoinLast,
      onToggleMute: onToggleMute,
      onToggleDeafen: onToggleDeafen,
      onTogglePttMode: onTogglePttMode,
      onPttDown: onPttDown,
      onPttUp: onPttUp,
      onRejoinLast: onRejoinLast,
      onDismissVoiceNotice: onDismissVoiceNotice,
    );
  }
}

class _VoiceJoin extends StatelessWidget {
  const _VoiceJoin({
    required this.channelName,
    required this.members,
    required this.busy,
    required this.onJoin,
  });

  final String channelName;
  final List<ClientView> members;
  final bool busy;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (members.isNotEmpty) ...[
                      _AvatarStack(members: members),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      channelName,
                      textAlign: TextAlign.center,
                      style: texts.headlineSmall?.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      members.isEmpty
                          ? l10n.voiceEmpty
                          : l10n.voiceMembersCount(members.length),
                      textAlign: TextAlign.center,
                      style: texts.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: busy ? null : onJoin,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.xxl),
                        ),
                      ),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mic_rounded, size: 20),
                      label: Text(l10n.voiceJoin),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 叠在一起的成员头像：环色跟页面底色走，叠起来也不会糊成一片。
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});

  final List<ClientView> members;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(4).toList();
    const size = AvatarSize.large;
    const step = 38.0;
    final width = size + (shown.length - 1) * step + 6;

    return SizedBox(
      width: width,
      height: size + 6,
      child: Stack(
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: index * step,
              top: 3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: context.pageColor,
                  shape: BoxShape.circle,
                ),
                child: ClientAvatar(
                  nickname: shown[index].nickname,
                  size: size,
                  onSurface: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceRoom extends StatelessWidget {
  const _VoiceRoom({
    required this.members,
    required this.muted,
    required this.deafened,
    required this.inputReady,
    required this.outputReady,
    required this.speaking,
    required this.selfSpeaking,
    required this.pttMode,
    required this.pttActive,
    required this.voiceNotice,
    required this.canRejoinLast,
    required this.onToggleMute,
    required this.onToggleDeafen,
    required this.onTogglePttMode,
    required this.onPttDown,
    required this.onPttUp,
    required this.onRejoinLast,
    required this.onDismissVoiceNotice,
  });

  final List<ClientView> members;
  final bool muted;
  final bool deafened;
  final bool inputReady;
  final bool outputReady;
  final Set<int> speaking;
  final bool selfSpeaking;
  final bool pttMode;
  final bool pttActive;
  final String? voiceNotice;
  final bool canRejoinLast;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleDeafen;
  final VoidCallback onTogglePttMode;
  final VoidCallback onPttDown;
  final VoidCallback onPttUp;
  final VoidCallback onRejoinLast;
  final VoidCallback onDismissVoiceNotice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final horizontal = context.isCompact ? 16.0 : 32.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (voiceNotice != null)
          Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
            child: NoticeBar(
              message: voiceNotice!,
              dismissTooltip: l10n.commonClose,
              onDismiss: onDismissVoiceNotice,
            ),
          ),
        if (!inputReady || !outputReady)
          Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!inputReady)
                  _DeviceChip(
                    icon: Icons.mic_off_rounded,
                    label: l10n.voiceMicUnavailable,
                  ),
                if (!outputReady)
                  _DeviceChip(
                    icon: Icons.volume_off_rounded,
                    label: l10n.voiceSpeakerUnavailable,
                  ),
              ],
            ),
          ),
        if (members.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_alt_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.voiceMembersCount(members.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: members.isEmpty
              ? Center(
                  child: Text(
                    l10n.voiceEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < Breakpoints.compact
                        ? 2
                        : 3;
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1024),
                        child: GridView.builder(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            16,
                            horizontal,
                            16,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 4 / 3,
                              ),
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            return _MemberCard(
                              member: member,
                              speaking: speaking.contains(member.id),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (selfSpeaking)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.graphic_eq_rounded, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  l10n.voiceSelfSpeaking,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.primary),
                ),
              ],
            ),
          ),
        if (pttMode)
          _PushToTalkPad(
            active: pttActive,
            onPttDown: onPttDown,
            onPttUp: onPttUp,
          ),
        _VoiceControls(
          muted: muted,
          deafened: deafened,
          pttMode: pttMode,
          canRejoinLast: canRejoinLast,
          onToggleMute: onToggleMute,
          onToggleDeafen: onToggleDeafen,
          onTogglePttMode: onTogglePttMode,
          onRejoinLast: onRejoinLast,
        ),
      ],
    );
  }
}

/// 成员卡片：4:3 的卡片里只留头像与昵称，说话时头像与卡片同时亮起。
class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.speaking});

  final ClientView member;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 4:3 的卡片高度有限，窄屏或放大字号时先按剩余高度收缩头像，
        // 宁可头像小一号，也不要文字顶出卡片。
        final textScaler = MediaQuery.textScalerOf(context);
        final textHeight = textScaler.scale(14) * 1.5;
        final contentHeight = constraints.maxHeight - 24 - (speaking ? 4 : 0);
        final avatarSize = math.min(
          AvatarSize.extraLarge,
          math.max(36.0, contentHeight - 12 - textHeight),
        );
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(Radii.xxxl),
            border: speaking
                ? Border.all(color: scheme.primary, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MemberAvatar(
                label: initialsOf(member.nickname),
                size: avatarSize,
                speaking: speaking,
                onSurface: true,
              ),
              const SizedBox(height: 10),
              Text(
                member.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: texts.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeviceChip extends StatelessWidget {
  const _DeviceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按住说话：只有按下时后端才发音频，所以用按下/抬起而不是开关。
class _PushToTalkPad extends StatelessWidget {
  const _PushToTalkPad({
    required this.active,
    required this.onPttDown,
    required this.onPttUp,
  });

  final bool active;
  final VoidCallback onPttDown;
  final VoidCallback onPttUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => onPttDown(),
            onTapUp: (_) => onPttUp(),
            onTapCancel: onPttUp,
            child: AnimatedContainer(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: active ? scheme.primary : scheme.surfaceContainerHigh,
                borderRadius: Radii.pillAll,
                border: Border.all(
                  color: active ? scheme.primary : scheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? Icons.mic_rounded : Icons.touch_app_rounded,
                    size: 22,
                    color: active ? scheme.onPrimary : scheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      active ? l10n.voicePushToTalkHint : l10n.voicePushToTalk,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: texts.labelLarge?.copyWith(
                        color: active ? scheme.onPrimary : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceControls extends StatelessWidget {
  const _VoiceControls({
    required this.muted,
    required this.deafened,
    required this.pttMode,
    required this.canRejoinLast,
    required this.onToggleMute,
    required this.onToggleDeafen,
    required this.onTogglePttMode,
    required this.onRejoinLast,
  });

  final bool muted;
  final bool deafened;
  final bool pttMode;
  final bool canRejoinLast;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleDeafen;
  final VoidCallback onTogglePttMode;
  final VoidCallback onRejoinLast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: Radii.pillAll,
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _ControlButton(
                tooltip: muted ? l10n.voiceUnmute : l10n.voiceMute,
                icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                active: muted,
                onTap: onToggleMute,
              ),
              _ControlButton(
                tooltip: deafened ? l10n.voiceUndeafen : l10n.voiceDeafen,
                icon: deafened
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                active: deafened,
                onTap: onToggleDeafen,
              ),
              _ControlButton(
                tooltip: l10n.voicePushToTalk,
                icon: Icons.record_voice_over_rounded,
                active: pttMode,
                danger: false,
                onTap: onTogglePttMode,
              ),
              if (canRejoinLast)
                TextButton(
                  onPressed: onRejoinLast,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    minimumSize: const Size(Sizes.touch, Sizes.touch),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    l10n.voiceRejoinLast,
                    style: texts.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onTap,
    this.danger = true,
  });

  final String tooltip;
  final IconData icon;
  final bool active;

  /// 静音/聋听是「关掉输入输出」，用拒绝色；模式切换只是状态，不该像警告。
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final background = active
        ? (danger ? scheme.errorContainer : scheme.primaryContainer)
        : context.cardColor;
    final foreground = active
        ? (danger ? scheme.onErrorContainer : scheme.onPrimaryContainer)
        : scheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 48,
            child: Icon(icon, size: 22, color: foreground),
          ),
        ),
      ),
    );
  }
}
