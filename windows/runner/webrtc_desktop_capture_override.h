#ifndef FLSPEAK_WINDOWS_RUNNER_WEBRTC_DESKTOP_CAPTURE_OVERRIDE_H_
#define FLSPEAK_WINDOWS_RUNNER_WEBRTC_DESKTOP_CAPTURE_OVERRIDE_H_

// Force-included (/FI) before each translation unit's top-of-file defines, so
// _CRT_SECURE_NO_WARNINGS must precede CRT headers pulled in below (e.g. for
// flutter_frame_capturer.cc's fopen under /WX).
#if defined(_MSC_VER) && !defined(_CRT_SECURE_NO_WARNINGS)
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <cstdint>

#include "rtc_desktop_device.h"

// Include rtc_desktop_device.h above before redefining CreateDesktopCapturer so
// RTCDesktopDevice's vtable declaration stays intact while flutter_screen_capture
// passes non-focusing WGC options into libwebrtc.
#define CreateDesktopCapturer(source, show_cursor)                    \
  CreateDesktopCapturerWithOptions(                                   \
      (source), ::libwebrtc::RTCDesktopCapturerOptions{               \
                    (show_cursor), /*focus_window=*/false,            \
                    /*allow_wgc_window_capturer=*/true,               \
                    /*wgc_border_required=*/false})

#endif  // FLSPEAK_WINDOWS_RUNNER_WEBRTC_DESKTOP_CAPTURE_OVERRIDE_H_
