import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../core/channel_display.dart';
import '../../core/models.dart';
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
    ref.read(selectedMemberProvider.notifier).clear();
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
    final origin = ref.read(sessionViewProvider);
    if (!origin.connected || origin.activeServerId != serverId) return;
    bool current() {
      if (!ref.mounted) return false;
      final view = ref.read(sessionViewProvider);
      return view.connected &&
          view.activeServerId == origin.activeServerId &&
          view.connectionEpoch == origin.connectionEpoch;
    }

    select(channelId, serverId: serverId);
    bool moved;
    try {
      moved = await ref
          .read(sessionViewProvider.notifier)
          .joinChannel(channelId);
    } on CoreError_ChannelPasswordRequired {
      if (!current()) return;
      moved = await requestPassword?.call() ?? false;
    }
    // 期间用户又换了目标时以新的为准，不回滚。
    if (current() &&
        !moved &&
        state == (serverId: serverId, channelId: channelId)) {
      state = fallback;
    }
  }
}

/// 选中的用户，连同当时的服务器以及快照信息。
typedef SelectedMember = ({
  String? serverId,
  int clientId,
  String uid,
  ClientView snapshot,
  int selectionEpoch,
});

final selectedMemberProvider =
    NotifierProvider<SelectedMemberController, SelectedMember?>(
      SelectedMemberController.new,
    );

class SelectedMemberController extends Notifier<SelectedMember?> {
  int _epoch = 0;

  @override
  SelectedMember? build() => null;

  void select(ClientView client, {String? serverId}) {
    state = (
      serverId: serverId,
      clientId: client.id,
      uid: client.uid,
      snapshot: client,
      selectionEpoch: ++_epoch,
    );
  }

  void clear() {
    state = null;
  }
}

/// 详情面板要展示的目标类型：频道详情或用户详情。
sealed class DetailsTarget {
  const DetailsTarget();
}

class ChannelDetailsTarget extends DetailsTarget {
  const ChannelDetailsTarget(this.channel);
  final ChannelView channel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelDetailsTarget &&
          runtimeType == other.runtimeType &&
          channel.id == other.channel.id;

  @override
  int get hashCode => channel.id.hashCode;
}

class MemberDetailsTarget extends DetailsTarget {
  const MemberDetailsTarget({required this.client, this.isOffline = false});
  final ClientView client;
  final bool isOffline;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberDetailsTarget &&
          runtimeType == other.runtimeType &&
          client.id == other.client.id &&
          client.uid == other.client.uid &&
          isOffline == other.isOffline;

  @override
  int get hashCode => Object.hash(client.id, client.uid, isOffline);
}

/// 详情页签当前展示的目标：优先选中的用户，其次私聊对象，最后退回到活动频道。
final activeDetailsTargetProvider = Provider<DetailsTarget?>((ref) {
  final view = ref.watch(sessionViewProvider);
  final selectedMember = ref.watch(selectedMemberProvider);

  if (selectedMember != null &&
      selectedMember.serverId == view.activeServerId) {
    final live = view.clients
        .where(
          (peer) =>
              peer.id == selectedMember.clientId &&
              peer.uid == selectedMember.uid,
        )
        .firstOrNull;
    if (live != null) {
      return MemberDetailsTarget(client: live, isOffline: false);
    }
    return MemberDetailsTarget(
      client: selectedMember.snapshot,
      isOffline: true,
    );
  }

  if (view.chatScope == ChatScope.direct && view.directRecipient != null) {
    return MemberDetailsTarget(client: view.directRecipient!, isOffline: false);
  }

  final channelId = ref.watch(activeChannelIdProvider);
  if (channelId == null) return null;
  final channel = view.channelById(channelId);
  return channel == null ? null : ChannelDetailsTarget(channel);
});

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
