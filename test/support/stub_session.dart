import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';

/// 固定状态的会话控制器：只渲染给定的快照，并记录界面发来的命令。
///
/// 这样界面测试不碰 FFI，同时还能断言「点了按钮之后发了什么命令」。
class StubSessionController extends SessionController {
  StubSessionController(this.initial);

  final SessionView initial;

  final registered = <({String label, String address})>[];
  final connected = <({String id, String nickname})>[];
  final sent = <String>[];
  final joined = <int>[];
  bool disconnected = false;
  bool refreshed = false;

  @override
  SessionView build() => initial;

  @override
  Future<ServerProfileView?> addServer({
    required String label,
    required String address,
  }) async {
    registered.add((label: label, address: address));
    return ServerProfileView(
      id: address,
      label: label,
      host: address.split(':').first,
      port: 9987,
    );
  }

  @override
  Future<void> connect({required String id, required String nickname}) async {
    connected.add((id: id, nickname: nickname));
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Future<void> joinChannel(int channelId, {String? password}) async {
    joined.add(channelId);
  }

  @override
  Future<void> sendMessage(String text) async {
    sent.add(text);
  }

  @override
  Future<void> refresh() async {
    refreshed = true;
  }

  @override
  void selectChatScope(ChatScope scope) {
    state = state.copyWith(chatScope: scope);
  }
}
