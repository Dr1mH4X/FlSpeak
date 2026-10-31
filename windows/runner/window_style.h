// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目。
// 原始许可证：FlClash 应用代码为 GPL-3.0；其 plugins/window 插件为 MIT。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 本片段取自 plugins/window（MIT），可按 MIT 或 GPL-3.0 使用：对应
// plugins/window/windows/window_style.h。

#ifndef RUNNER_WINDOW_STYLE_H_
#define RUNNER_WINDOW_STYLE_H_

#include <windows.h>

#include <cstdint>
#include <optional>
#include <string>

namespace window {

enum class TitleBarStyle {
  kNormal,
  kHidden,
};

enum class Effect {
  kNone,
  kTransparent,
  kBlur,
  kAcrylic,
  kMica,
  kGlass,
};

std::optional<TitleBarStyle> ParseTitleBarStyle(const std::string& value);
std::optional<Effect> ParseEffect(const std::string& value);

int WindowsBuildNumber();
bool IsWindows11OrGreater();
bool IsEffectSupported(Effect effect);

// Reapplied as a whole by Apply() on every change, so settings never fight.
struct WindowStyle {
  TitleBarStyle title_bar_style = TitleBarStyle::kNormal;
  bool window_button_visibility = true;
  std::optional<bool> rounded_corners;
  Effect effect = Effect::kNone;
  uint32_t effect_tint = 0;  // ARGB.
  std::optional<bool> dark_mode;

  void SetTitleBarStyle(TitleBarStyle style, bool button_visibility,
                        HWND hwnd);
  void SetRoundedCorners(bool value, HWND hwnd);
  void SetEffect(Effect value, uint32_t tint, std::optional<bool> dark,
                 HWND hwnd);

  // Only place calling the Dwm*/SetWindowCompositionAttribute APIs.
  void Apply(HWND hwnd) const;

  // Rows the controller keeps clear above the view and paints transparent.
  // Windows 10 draws the top border only inside a frame extended over the
  // whole caption (a shorter non-client strip makes DWM draw the caption), so
  // Apply() extends it there; Windows 11 draws the border into the non-client
  // strip, one physical pixel tall, that WM_NCCALCSIZE leaves. Zero while an accent effect is on,
  // maximized or full screen.
  int TopBorderHeight(HWND hwnd) const;
};

}  // namespace window

#endif  // RUNNER_WINDOW_STYLE_H_
