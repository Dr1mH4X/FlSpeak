import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 服务器磁贴：颜色由档案 id 稳定散列而来，连接态用右下角的状态点表达。
///
/// 这是界面上唯一使用饱和色的功能性图形——扫一眼就能在同一批服务器之间认出彼此。
class ServerMonogram extends StatelessWidget {
  const ServerMonogram({
    required this.id,
    required this.label,
    required this.host,
    this.size = 44,
    this.online = false,
    this.dimmed = false,
    super.key,
  });

  final String id;
  final String label;
  final String host;
  final double size;
  final bool online;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final background = ServerPalette.of(id, brightness);
    final foreground = readableOn(background);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(
            opacity: dimmed ? 0.45 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(size * 0.3),
              ),
              child: Center(
                child: Text(
                  serverMonogram(label, host),
                  style: TextStyle(
                    color: foreground,
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
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
                ringColor: Theme.of(context).colorScheme.surface,
                size: size * 0.3,
              ),
            ),
        ],
      ),
    );
  }
}

/// 在线状态点。环色跟随所在容器的底色，因此放在任何面上都分得开。
class StatusDot extends StatelessWidget {
  const StatusDot({
    required this.color,
    required this.ringColor,
    this.size = 12,
    this.pulsing = false,
    super.key,
  });

  final Color color;
  final Color ringColor;
  final double size;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: size * 0.18),
      ),
    );
    if (!pulsing) {
      return dot;
    }
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reducedMotion) {
      return dot;
    }
    return _Pulsing(child: dot);
  }
}

class _Pulsing extends StatefulWidget {
  const _Pulsing({required this.child});

  final Widget child;

  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: 0.45,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// 成员头像。刻意不饱和——饱和色留给连接态与说话态。
class ClientAvatar extends StatelessWidget {
  const ClientAvatar({
    required this.nickname,
    this.size = 28,
    this.highlighted = false,
    super.key,
  });

  final String nickname;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        initialsOf(nickname),
        style: TextStyle(
          color: highlighted
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
