import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 提示的语义。错误用 error 容器，操作结果用 info 容器。
enum NoticeTone { error, info }

/// 一条瞬时提示。`id` 每次展示都递增，让宿主重启动画与倒计时。
@immutable
class AppNotice {
  const AppNotice({
    required this.id,
    required this.message,
    required this.tone,
  });

  final int id;
  final String message;
  final NoticeTone tone;
}

/// 页面级瞬时提示的唯一入口，按新到旧保留最近几条。
///
/// 只保存要展示的文案；持久状态（连接态、设备就绪、身份提升）仍留在
/// `SessionView` 与各自的页面组件里。
class NoticeCenter extends Notifier<List<AppNotice>> {
  static const limit = 3;

  var _nextId = 0;

  @override
  List<AppNotice> build() => const [];

  void show(String message, {NoticeTone tone = NoticeTone.error}) {
    final text = message.trim();
    if (text.isEmpty) {
      return;
    }
    // 同文案同 tone 视为同一条：换新 id 插到队首，宿主据此重新计时。
    state = [
      AppNotice(id: _nextId++, message: text, tone: tone),
      for (final notice in state)
        if (notice.message != text || notice.tone != tone) notice,
    ].take(limit).toList();
  }

  void dismiss(int id) {
    state = state.where((notice) => notice.id != id).toList();
  }
}

final noticeCenterProvider = NotifierProvider<NoticeCenter, List<AppNotice>>(
  NoticeCenter.new,
);
