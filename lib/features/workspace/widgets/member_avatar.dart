import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/member_avatars.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/monogram.dart';

class SessionMemberAvatar extends ConsumerWidget {
  const SessionMemberAvatar({
    required this.uid,
    required this.nickname,
    this.size = AvatarSize.medium,
    this.speaking = false,
    this.onSurface = false,
    super.key,
  });

  final String uid;
  final String nickname;
  final double size;
  final bool speaking;
  final bool onSurface;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MemberAvatar(
    label: initialsOf(nickname),
    image: uid.isEmpty
        ? null
        : ref.watch(memberAvatarProvider(uid)).asData?.value,
    size: size,
    speaking: speaking,
    onSurface: onSurface,
  );
}
