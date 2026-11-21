#include "keyboard_hook.h"

#include <windows.h>

namespace flspeak {
namespace {

// 低级钩子回调是 C 函数指针，钩子句柄与目标键码放进程级状态里；
// 本应用只会存在一个 KeyboardHook 实例。
HHOOK g_hook = nullptr;
uint32_t g_target_vk = 0;
bool g_key_down = false;
KeyboardHook::KeyEventCallback g_callback;

bool IsNavigationClusterVk(uint32_t vk) {
  switch (vk) {
    case VK_PRIOR:
    case VK_NEXT:
    case VK_END:
    case VK_HOME:
    case VK_INSERT:
    case VK_DELETE:
      return true;
    default:
      return false;
  }
}

bool IsMatchingTargetKey(const KBDLLHOOKSTRUCT* info, uint32_t target_vk) {
  if (info == nullptr || info->vkCode != target_vk) {
    return false;
  }
  const bool extended = (info->flags & LLKHF_EXTENDED) != 0;
  if (IsNavigationClusterVk(target_vk)) {
    // 主键区 Insert/Delete/Home/End/PageUp/PageDown 带有 LLKHF_EXTENDED；
    // NumLock 关闭时小键盘对应按键产生相同 vkCode 但不带该标志，按扫描码排除小键盘键。
    if (!extended) {
      const uint32_t sc = info->scanCode & 0xFF;
      switch (sc) {
        case 0x47:
        case 0x49:
        case 0x4F:
        case 0x51:
        case 0x52:
        case 0x53:
          return false;
        default:
          break;
      }
    }
    return true;
  }
  if (target_vk == VK_RETURN) {
    return !extended;
  }
  return true;
}

LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_callback) {
    const auto* info = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    if (IsMatchingTargetKey(info, g_target_vk)) {
      switch (wparam) {
        case WM_KEYDOWN:
        case WM_SYSKEYDOWN:
          if (!g_key_down) {
            g_key_down = true;
            g_callback(true);
          }
          break;
        case WM_KEYUP:
        case WM_SYSKEYUP:
          if (g_key_down) {
            g_key_down = false;
            g_callback(false);
          }
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

HookStartResult KeyboardHook::Start(uint32_t virtual_key,
                                    KeyEventCallback callback) {
  Stop();
  g_target_vk = virtual_key;
  g_key_down = false;
  g_callback = std::move(callback);
  g_hook = SetWindowsHookEx(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                            GetModuleHandle(nullptr), 0);
  if (g_hook == nullptr) {
    const uint32_t error_code = static_cast<uint32_t>(GetLastError());
    g_callback = nullptr;
    g_target_vk = 0;
    return {false, error_code};
  }
  return {true, 0};
}

void KeyboardHook::Stop() {
  if (g_hook != nullptr) {
    UnhookWindowsHookEx(g_hook);
    g_hook = nullptr;
  }
  g_callback = nullptr;
  g_target_vk = 0;
  g_key_down = false;
}

}  // namespace flspeak
