import 'package:flutter_riverpod/flutter_riverpod.dart';

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
