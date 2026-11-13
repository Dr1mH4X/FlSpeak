import 'dart:typed_data';

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        Checkbox,
        Chip,
        Divider,
        FilledButton,
        IconButton,
        LinearProgressIndicator,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/server_icon.dart';
import 'expressive_frame.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

class ServerBadge extends ConsumerWidget {
  const ServerBadge({
    required this.id,
    this.size = 44,
    this.online = false,
    this.selected = false,
    this.loading = false,
    super.key,
  });

  final String id;
  final double size;
  final bool online;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final choice = ref.watch(
      preferencesProvider.select(
        (preferences) => preferences.serverIcons[id] ?? ServerIconChoice.auto,
      ),
    );
    final serverBytes = ref.watch(
      sessionViewProvider.select((view) => view.serverIconBytes[id]),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ExpressiveFrame(
              size: size,
              loading: loading,
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              child: ServerIconGlyph(
                choice: choice,
                serverIconBytes: serverBytes,
                size: size,
                fallbackColor: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            if (online)
              Positioned(
                right: -2,
                bottom: -2,
                child: StatusDot(
                  color: context.status.live,
                  ringColor: context.cardColor,
                  size: size * 0.25,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ServerIconGlyph extends StatelessWidget {
  const ServerIconGlyph({
    required this.choice,
    required this.size,
    required this.fallbackColor,
    this.serverIconBytes,
    this.useAutoGlyph = false,
    super.key,
  });

  final ServerIconChoice choice;
  final Uint8List? serverIconBytes;
  final double size;
  final Color fallbackColor;
  final bool useAutoGlyph;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      useAutoGlyph ? choice.pickerIcon : choice.fallbackPreset.icon,
      size: size * 0.5,
      color: fallbackColor,
    );
    final bytes = choice.isAuto ? serverIconBytes : null;
    if (bytes == null) return fallback;
    final imageSize = size * 0.55;
    final cacheExtent = (imageSize * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 256);
    return Image.memory(
      bytes,
      width: imageSize,
      height: imageSize,
      fit: BoxFit.contain,
      cacheWidth: cacheExtent,
      cacheHeight: cacheExtent,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return fallback;
      },
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

/// 身份头像：主色实底圆形；与服务器磁贴同形，靠颜色语义区分（主色 vs 散列色）。
class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({required this.nickname, this.size = 64, super.key});

  final String nickname;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Text(
          initialsOf(nickname),
          style: TextStyle(
            color: context.scheme.onPrimary,
            fontSize: size * 0.34,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// 成员头像的四个档位，和设计稿 `size-7 / size-10 / size-14 / size-20` 对齐。
abstract final class AvatarSize {
  static const small = 28.0;
  static const medium = 40.0;
  static const large = 56.0;
  static const extraLarge = 80.0;
}

/// 成员头像：主色容器上的缩写，说话时套一圈主色光环。
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required this.label,
    this.size = AvatarSize.medium,
    this.speaking = false,
    this.onSurface = false,
    this.image,
    super.key,
  });

  final String label;
  final double size;
  final bool speaking;
  final Uint8List? image;

  /// 放在卡片上时环色跟着卡片走；默认跟着页面底色。
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final ringColor = onSurface ? context.cardColor : context.pageColor;
    final fallback = Text(
      label,
      style: TextStyle(
        color: scheme.onPrimaryContainer,
        fontSize: size * 0.33,
        fontWeight: FontWeight.w500,
        height: 1,
      ),
    );

    // 说话描边用透明边占位过渡：边框出现/消失不再挤动布局，也不瞬跳。
    final avatar = AnimatedContainer(
      duration: Motion.effectsFast,
      curve: Motion.effectsDefaultCurve,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? context.status.live : Colors.transparent,
          width: 2,
        ),
      ),
      child: image == null
          ? fallback
          : ClipOval(
              child: Image.memory(
                image!,
                width: size - 4,
                height: size - 4,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).ceil(),
                errorBuilder: (context, error, stack) =>
                    Center(child: fallback),
              ),
            ),
    );

    if (!speaking) {
      return ExcludeSemantics(child: avatar);
    }
    return ExcludeSemantics(
      child: _SpeakingHalo(ringColor: ringColor, child: avatar),
    );
  }
}

/// 说话光环：向外扩一圈主色，和设计稿的 `speak-pulse` 同节奏。
class _SpeakingHalo extends StatefulWidget {
  const _SpeakingHalo({required this.ringColor, required this.child});

  final Color ringColor;
  final Widget child;

  @override
  State<_SpeakingHalo> createState() => _SpeakingHaloState();
}

class _SpeakingHaloState extends State<_SpeakingHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.status.live;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.5 * (1 - t)),
                spreadRadius: 1 + 6 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 兼容旧调用：昵称进、缩写出。
class ClientAvatar extends StatelessWidget {
  const ClientAvatar({
    required this.nickname,
    this.size = AvatarSize.medium,
    this.speaking = false,
    this.onSurface = false,
    super.key,
  });

  final String nickname;
  final double size;
  final bool speaking;
  final bool onSurface;

  @override
  Widget build(BuildContext context) => MemberAvatar(
    label: initialsOf(nickname),
    size: size,
    speaking: speaking,
    onSurface: onSurface,
  );
}

/// 在线状态点。环色跟随所在容器的底色，因此放在任何面上都分得开。
class StatusDot extends StatelessWidget {
  const StatusDot({
    required this.color,
    required this.ringColor,
    this.size = 12,
    super.key,
  });

  final Color color;
  final Color ringColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: size * 0.18),
        ),
      ),
    );
  }
}
