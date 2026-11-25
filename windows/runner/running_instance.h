// Adapted from FlClash plugins/window (7fd417f, MIT): windows/running_instance.h. See docs/THIRD-PARTY.md.

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
