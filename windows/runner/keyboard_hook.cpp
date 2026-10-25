#include "keyboard_hook.h"

#include <windows.h>

namespace flspeak {
namespace {

// 低级钩子回调是 C 函数指针，钩子句柄与目标键码放进程级状态里；
// 本应用只会存在一个 KeyboardHook 实例。
HHOOK g_hook = nullptr;
uint32_t g_target_vk = 0;
KeyboardHook::KeyEventCallback g_callback;

LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_callback) {
    const auto* info = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    // 扩展键（数字小键盘、媒体键）不算目标键，避免误触。
    if (!(info->flags & LLKHF_EXTENDED) && info->vkCode == g_target_vk) {
      switch (wparam) {
        case WM_KEYDOWN:
        case WM_SYSKEYDOWN:
          g_callback(true);
          break;
        case WM_KEYUP:
        case WM_SYSKEYUP:
          g_callback(false);
          break;
        default:
          break;
      }
    }
  }
  return CallNextHookEx(g_hook, code, wparam, lparam);
}

}  // namespace

KeyboardHook::~KeyboardHook() { Stop(); }

bool KeyboardHook::Start(uint32_t virtual_key, KeyEventCallback callback) {
  Stop();
  g_target_vk = virtual_key;
  g_callback = std::move(callback);
  g_hook = SetWindowsHookEx(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                            GetModuleHandle(nullptr), 0);
  if (g_hook == nullptr) {
    g_callback = nullptr;
    return false;
  }
  return true;
}

void KeyboardHook::Stop() {
  if (g_hook != nullptr) {
    UnhookWindowsHookEx(g_hook);
    g_hook = nullptr;
  }
  g_callback = nullptr;
}

}  // namespace flspeak
