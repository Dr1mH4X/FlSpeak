#ifndef RUNNER_KEYBOARD_HOOK_H_
#define RUNNER_KEYBOARD_HOOK_H_

#include <cstdint>
#include <functional>

namespace flspeak {

// 全局「按住说话」键盘钩子。
//
// 低级钩子（WH_KEYBOARD_LL）只观察不吞键：按住说话的键在其他程序里照常
// 工作。钩子必须安装在运行消息循环的线程上（Flutter 平台线程），回调也
// 在该线程触发，所以回调里可以直接调用 Flutter 通道。
class KeyboardHook {
 public:
  using KeyEventCallback = std::function<void(bool down)>;

  KeyboardHook() = default;
  ~KeyboardHook();

  KeyboardHook(const KeyboardHook&) = delete;
  KeyboardHook& operator=(const KeyboardHook&) = delete;

  // 监听给定的虚拟键码；重复调用会先卸载旧钩子。返回是否安装成功。
  bool Start(uint32_t virtual_key, KeyEventCallback callback);

  // 卸载钩子。没安装时是空操作。
  void Stop();
};

}  // namespace flspeak

#endif  // RUNNER_KEYBOARD_HOOK_H_
