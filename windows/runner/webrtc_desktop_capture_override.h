#ifndef FLSPEAK_WINDOWS_RUNNER_WEBRTC_DESKTOP_CAPTURE_OVERRIDE_H_
#define FLSPEAK_WINDOWS_RUNNER_WEBRTC_DESKTOP_CAPTURE_OVERRIDE_H_

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
