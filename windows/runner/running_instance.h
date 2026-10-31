// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目。
// 原始许可证：FlClash 应用代码为 GPL-3.0；其 plugins/window 插件为 MIT。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 本片段取自 plugins/window（MIT），可按 MIT 或 GPL-3.0 使用：对应
// plugins/window/windows/running_instance.h。

#ifndef RUNNER_WINDOW_RUNNING_INSTANCE_H_
#define RUNNER_WINDOW_RUNNING_INSTANCE_H_

#include <windows.h>

namespace window {

UINT GetActivateMessage();

// Lets a lower-integrity relaunch reach an elevated |root| with
// GetActivateMessage() and app_links' WM_COPYDATA; UIPI drops both otherwise.
void AllowRelaunchMessagesThroughUipi(HWND root);

HWND FindRunningWindow();
void ActivateWindow(HWND window);

}  // namespace window

#endif  // RUNNER_WINDOW_RUNNING_INSTANCE_H_
