// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目。
// 原始许可证：FlClash 应用代码为 GPL-3.0；其 plugins/window 插件为 MIT。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 本片段取自 plugins/window（MIT），可按 MIT 或 GPL-3.0 使用：对应
// plugins/window/windows/ 的 WindowController / WindowStyle 绑定与消息拦截。

#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "running_instance.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project),
      window_controller_([this](const std::string& name) {
        if (window_channel_) {
          flutter::EncodableMap args;
          args[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
          window_channel_->InvokeMethod(
              "onEvent", std::make_unique<flutter::EncodableValue>(args));
        }
      }) {
  window_controller_.SetStyle(&window_style_);
}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  HWND hwnd = GetHandle();
  HWND view = flutter_controller_->view()->GetNativeWindow();
  window_controller_.Initialize(hwnd, view);
  window::AllowRelaunchMessagesThroughUipi(hwnd);

  // 默认开启沉浸式隐藏标题栏
  window_style_.SetTitleBarStyle(window::TitleBarStyle::kHidden, false, hwnd);

  // 全局按住说话热键。低级键盘钩子只观察不吞键，其他程序不受影响。
  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "flspeak/global_hotkey",
          &flutter::StandardMethodCodec::GetInstance());
  hotkey_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleHotkeyCall(call, std::move(result));
      });

  // flspeak/window 窗口控制通道
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "flspeak/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleWindowCall(call, std::move(result));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  keyboard_hook_.Stop();
  hotkey_channel_ = nullptr;
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleHotkeyCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "register") {
    int64_t code = -1;
    if (const auto* int32_value = std::get_if<int32_t>(call.arguments())) {
      code = *int32_value;
    } else if (const auto* int64_value = std::get_if<int64_t>(call.arguments())) {
      code = *int64_value;
    }
    bool ok = code >= 0 && code <= 0xFFFFFFFF &&
              keyboard_hook_.Start(static_cast<uint32_t>(code),
                                   [this](bool down) {
                                     hotkey_channel_->InvokeMethod(
                                         down ? "onKeyDown" : "onKeyUp",
                                         nullptr);
                                    });
    result->Success(flutter::EncodableValue(ok));
  } else if (call.method_name() == "unregister") {
    keyboard_hook_.Stop();
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::HandleWindowCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "startDragging") {
    window_controller_.StartDragging();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "toggleZoom") {
    if (window_controller_.IsFullScreen()) {
      window_controller_.SetFullScreen(false);
    } else if (window_controller_.IsMaximized()) {
      window_controller_.Unmaximize();
    } else {
      window_controller_.Maximize();
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "isFullScreen") {
    result->Success(flutter::EncodableValue(window_controller_.IsFullScreen()));
  } else if (method == "setFullScreen") {
    if (call.arguments()) {
      if (const auto* val = std::get_if<bool>(call.arguments())) {
        window_controller_.SetFullScreen(*val);
        result->Success(flutter::EncodableValue(true));
        return;
      }
    }
    result->Error("bad_args", "setFullScreen: value");
  } else if (method == "isMaximized") {
    result->Success(flutter::EncodableValue(window_controller_.IsMaximized()));
  } else if (method == "maximize") {
    window_controller_.Maximize();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "unmaximize") {
    window_controller_.Unmaximize();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "minimize") {
    window_controller_.Minimize();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "restore") {
    window_controller_.Restore();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "close") {
    window_controller_.Close();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "isAlwaysOnTop") {
    result->Success(flutter::EncodableValue(window_controller_.IsAlwaysOnTop()));
  } else if (method == "setAlwaysOnTop") {
    if (call.arguments()) {
      if (const auto* val = std::get_if<bool>(call.arguments())) {
        window_controller_.SetAlwaysOnTop(*val);
        result->Success(flutter::EncodableValue(true));
        return;
      }
    }
    result->Error("bad_args", "setAlwaysOnTop: value");
  } else if (method == "isEffectSupported") {
    if (call.arguments()) {
      if (const auto* name = std::get_if<std::string>(call.arguments())) {
        auto effect = window::ParseEffect(*name);
        result->Success(flutter::EncodableValue(effect.has_value() && window::IsEffectSupported(*effect)));
        return;
      }
    }
    result->Error("bad_args", "isEffectSupported: effect");
  } else if (method == "setEffect") {
    if (call.arguments()) {
      if (const auto* map = std::get_if<flutter::EncodableMap>(call.arguments())) {
        auto it_effect = map->find(flutter::EncodableValue("effect"));
        if (it_effect != map->end()) {
          if (const auto* effect_name = std::get_if<std::string>(&it_effect->second)) {
            auto effect = window::ParseEffect(*effect_name);
            if (effect.has_value() && window::IsEffectSupported(*effect)) {
              uint32_t tint = 0;
              auto it_tint = map->find(flutter::EncodableValue("tint"));
              if (it_tint != map->end()) {
                if (const auto* tint32 = std::get_if<int32_t>(&it_tint->second)) {
                  tint = static_cast<uint32_t>(*tint32);
                } else if (const auto* tint64 = std::get_if<int64_t>(&it_tint->second)) {
                  tint = static_cast<uint32_t>(*tint64);
                }
              }
              std::optional<bool> dark;
              auto it_bright = map->find(flutter::EncodableValue("brightness"));
              if (it_bright != map->end()) {
                if (const auto* bright_str = std::get_if<std::string>(&it_bright->second)) {
                  dark = (*bright_str == "dark");
                }
              }
              window_style_.SetEffect(*effect, tint, dark, window_controller_.GetWindow());
              result->Success(flutter::EncodableValue(true));
              return;
            }
          }
        }
      }
    }
    result->Error("bad_args", "setEffect: effect");
  } else if (method == "setBackgroundColor") {
    if (call.arguments()) {
      uint32_t argb = 0;
      if (const auto* val32 = std::get_if<int32_t>(call.arguments())) {
        argb = static_cast<uint32_t>(*val32);
      } else if (const auto* val64 = std::get_if<int64_t>(call.arguments())) {
        argb = static_cast<uint32_t>(*val64);
      }
      bool is_dark = (((argb >> 16) & 0xFF) + ((argb >> 8) & 0xFF) + (argb & 0xFF)) / 3 < 128;
      window_style_.dark_mode = is_dark;
      window_style_.Apply(window_controller_.GetWindow());
      result->Success(flutter::EncodableValue(true));
      return;
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "focus") {
    window_controller_.Focus();
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    if (message == WM_SHOWWINDOW || message == WM_SIZE) {
      flutter_controller_->engine()->ProcessExternalWindowMessage(
          flutter_controller_->view()->GetNativeWindow(), message, wparam,
          lparam);
    }
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (auto result = window_controller_.HandleWindowMessage(hwnd, message,
                                                           wparam, lparam)) {
    return *result;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
