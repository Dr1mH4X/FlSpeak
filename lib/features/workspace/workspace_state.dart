import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../core/channel_display.dart';
import '../../core/providers.dart';

/// 用户在频道树里点开的频道，连同当时的服务器，避免换服务器后误用同号频道。
final selectedChannelProvider =
    NotifierProvider<SelectedChannelController, SelectedChannel?>(
      SelectedChannelController.new,
    );

typedef SelectedChannel = ({String? serverId, int channelId});

class SelectedChannelController extends Notifier<SelectedChannel?> {
  @override
  SelectedChannel? build() => null;

  void select(int channelId, {String? serverId}) {
    state = (serverId: serverId, channelId: channelId);
  }

  /// 双击频道：立刻把高亮移过去，再让 core 移动自己。移动被服务端拒（密码、
  /// 权限）时退回 [fallback]——双击的第一次点击已经选过目标频道，所以「原位置」
  /// 只能由调用方在点下去之前记下；不回退的话主区域会停在一个自己没进去的频道上。
  /// 选中与加入放在一起，是因为 [activeChannelIdProvider] 的优先规则在此定义。
  Future<void> join(
    int channelId, {
    required String? serverId,
    required SelectedChannel? fallback,
    Future<bool> Function()? requestPassword,
  }) async {
    select(channelId, serverId: serverId);
    bool moved;
    try {
      moved = await ref
          .read(sessionViewProvider.notifier)
          .joinChannel(channelId);
    } on CoreError_ChannelPasswordRequired {
      moved = await requestPassword?.call() ?? false;
    }
    // 期间用户又换了目标时以新的为准，不回滚。
    if (!moved && state == (serverId: serverId, channelId: channelId)) {
      state = fallback;
    }
  }
}

/// 主区域正在展示的频道：优先用户点开的那一个，其次自己所在的频道，
/// 最后退到根频道的第一项。频道被服务端删掉时也能自然回到一个有效值。
final activeChannelIdProvider = Provider<int?>((ref) {
  final view = ref.watch(sessionViewProvider);
  final selected = ref.watch(selectedChannelProvider);

  if (selected != null &&
      selected.serverId == view.activeServerId &&
      view.channelById(selected.channelId) != null) {
    return selected.channelId;
  }
  final self = view.selfChannelId;
  if (self != null && view.channelById(self) != null) {
    return self;
  }
  // 兜底频道要挑用户真能进入的：spacer 是装饰频道，不参与选中；
  // 用排序后的顺序，保证「第一个」和树里展示的第一个一致。
  final roots = view.orderedRootChannels().where(
    (channel) => parseChannelSpacer(channel.name) == null,
  );
  return roots.isEmpty ? null : roots.first.id;
});
