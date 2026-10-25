import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 服务器磁贴：圆形，颜色由档案 id 稳定散列而来，连接态用右下角的状态点表达。
///
/// 与身份头像同形（圆），靠颜色语义区分——身份用主色实底，服务器用各自
/// 的散列色，扫一眼就能在同一批服务器之间认出彼此。色相与
/// `refer/components/login/monogram.tsx` 共用一张表。
class ServerMonogram extends StatelessWidget {
  const ServerMonogram({
    required this.id,
    required this.label,
    required this.host,
    this.size = 44,
    this.online = false,
    super.key,
  });

  final String id;
  final String label;
  final String host;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final background = ServerPalette.of(id, Theme.of(context).brightness);
    final dotSize = size * 0.27;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                serverMonogram(label, host),
                style: TextStyle(
                  color: readableOn(background),
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          if (online)
            Positioned(
              right: -2,
              bottom: -2,
              child: StatusDot(
                color: context.status.live,
                ringColor: context.cardColor,
                size: dotSize,
              ),
            ),
        ],
      ),
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
    super.key,
  });

  final String label;
  final double size;
  final bool speaking;

  /// 放在卡片上时环色跟着卡片走；默认跟着页面底色。
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final ringColor = onSurface ? context.cardColor : context.pageColor;

    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
        border: speaking ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: size * 0.33,
          fontWeight: FontWeight.w500,
          height: 1,
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
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      return;
    }
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
    final primary = context.scheme.primary;
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
