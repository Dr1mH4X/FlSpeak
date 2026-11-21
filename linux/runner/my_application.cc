#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <gdk/gdkx.h>
#endif

#include <string.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

enum class LinuxSessionBackend {
  kPureX11,
  kWayland,
  kXWayland,
  kUnknown,
};

const gchar* const kPortalBusName = "org.freedesktop.portal.Desktop";
const gchar* const kPortalObjectPath = "/org/freedesktop/portal/desktop";
const gchar* const kPortalGlobalShortcutsIface =
    "org.freedesktop.portal.GlobalShortcuts";
const gchar* const kPortalRequestIface = "org.freedesktop.portal.Request";
const gchar* const kPortalSessionIface = "org.freedesktop.portal.Session";
const gchar* const kPortalShortcutId = "ptt";

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // 全局按住说话热键：纯 X11 使用 XInput2（被动只观察）；Wayland / XWayland
  // 使用 org.freedesktop.portal.GlobalShortcuts。
  FlMethodChannel* hotkey_channel;
  FlMethodCodec* hotkey_codec;
  guint hotkey_keycode;  // 0 表示未注册。
  gboolean hotkey_key_down;

  // X11 XInput2 状态。
  gboolean hotkey_x11_filter_installed;
  gboolean hotkey_x11_events_selected;
  int hotkey_xi_opcode;
  guint hotkey_x11_release_timer_id;

  // Wayland / XWayland Portal 状态。
  GDBusConnection* portal_bus;
  gchar* portal_session_handle;
  guint portal_activated_sub_id;
  guint portal_deactivated_sub_id;
  guint portal_response_sub_id;
  GCancellable* portal_cancellable;
  FlMethodCall* portal_pending_call;
  guint portal_generation;
  guint portal_token_counter;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlValue* make_hotkey_result(gboolean ok, const gchar* reason,
                                   gboolean has_code, int code) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "ok", fl_value_new_bool(ok));
  fl_value_set_string_take(map, "reason", fl_value_new_string(reason));
  fl_value_set_string_take(
      map, "code", has_code ? fl_value_new_int(code) : fl_value_new_null());
  return map;
}

static gboolean is_wayland_session_env() {
  const gchar* session_type = g_getenv("XDG_SESSION_TYPE");
  if (session_type != nullptr &&
      g_ascii_strcasecmp(session_type, "wayland") == 0) {
    return TRUE;
  }
  const gchar* wayland_display = g_getenv("WAYLAND_DISPLAY");
  return wayland_display != nullptr && wayland_display[0] != '\0';
}

static LinuxSessionBackend detect_session_backend() {
  GdkDisplay* display = gdk_display_get_default();
#ifdef GDK_WINDOWING_WAYLAND
  if (display != nullptr && GDK_IS_WAYLAND_DISPLAY(display)) {
    return LinuxSessionBackend::kWayland;
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (display != nullptr && GDK_IS_X11_DISPLAY(display)) {
    return is_wayland_session_env() ? LinuxSessionBackend::kXWayland
                                    : LinuxSessionBackend::kPureX11;
  }
#endif
  return is_wayland_session_env() ? LinuxSessionBackend::kWayland
                                  : LinuxSessionBackend::kUnknown;
}

#ifdef GDK_WINDOWING_X11
namespace {

int g_hotkey_x11_error_code = 0;

int hotkey_x11_error_handler(Display*, XErrorEvent* event) {
  if (g_hotkey_x11_error_code == 0 && event != nullptr) {
    g_hotkey_x11_error_code = event->error_code;
  }
  return 0;
}

// 写入 root window 上 XIAllMasterDevices 的现有掩码（若存在），避免覆盖 GDK 自身的掩码。
void copy_existing_xi_master_mask(Display* xdisplay, Window root,
                                  unsigned char* out_mask, size_t out_len) {
  memset(out_mask, 0, out_len);
  int num_masks = 0;
  XIEventMask* existing = XIGetSelectedEvents(xdisplay, root, &num_masks);
  if (existing == nullptr) {
    return;
  }
  for (int i = 0; i < num_masks; ++i) {
    if (existing[i].deviceid == XIAllMasterDevices && existing[i].mask != nullptr &&
        existing[i].mask_len > 0) {
      const size_t copy_len =
          static_cast<size_t>(existing[i].mask_len) < out_len
              ? static_cast<size_t>(existing[i].mask_len)
              : out_len;
      memcpy(out_mask, existing[i].mask, copy_len);
      break;
    }
  }
  XFree(existing);
}

}  // namespace

static void cancel_x11_release_timer(MyApplication* self) {
  if (self->hotkey_x11_release_timer_id != 0) {
    g_source_remove(self->hotkey_x11_release_timer_id);
    self->hotkey_x11_release_timer_id = 0;
  }
}

static void reset_hotkey_key_down(MyApplication* self) {
  if (self->hotkey_key_down) {
    self->hotkey_key_down = FALSE;
    if (self->hotkey_channel != nullptr) {
      fl_method_channel_invoke_method(self->hotkey_channel, "onKeyUp", nullptr,
                                      nullptr, nullptr, nullptr);
    }
  }
}

static gboolean hotkey_x11_commit_release_cb(gpointer data) {
  auto* self = MY_APPLICATION(data);
  self->hotkey_x11_release_timer_id = 0;
  if (self->hotkey_key_down && self->hotkey_channel != nullptr) {
    self->hotkey_key_down = FALSE;
    fl_method_channel_invoke_method(self->hotkey_channel, "onKeyUp", nullptr,
                                    nullptr, nullptr, nullptr);
  }
  return G_SOURCE_REMOVE;
}

static GdkFilterReturn hotkey_x11_filter(GdkXEvent* xevent, GdkEvent*,
                                         gpointer data) {
  auto* self = MY_APPLICATION(data);
  if (self->hotkey_keycode == 0 || self->hotkey_channel == nullptr ||
      self->hotkey_xi_opcode < 0) {
    return GDK_FILTER_CONTINUE;
  }
  auto* xev = static_cast<XEvent*>(xevent);
  if (xev->type != GenericEvent) {
    return GDK_FILTER_CONTINUE;
  }
  XGenericEventCookie* cookie = &xev->xcookie;
  if (cookie->extension != self->hotkey_xi_opcode ||
      (cookie->evtype != XI_RawKeyPress &&
       cookie->evtype != XI_RawKeyRelease)) {
    return GDK_FILTER_CONTINUE;
  }

  Display* xdisplay = cookie->display;
  if (xdisplay == nullptr) {
    GdkDisplay* display = gdk_display_get_default();
    if (display != nullptr && GDK_IS_X11_DISPLAY(display)) {
      xdisplay = gdk_x11_display_get_xdisplay(display);
    }
  }
  gboolean owns_event_data = FALSE;
  if (cookie->data == nullptr) {
    if (xdisplay == nullptr || !XGetEventData(xdisplay, cookie)) {
      return GDK_FILTER_CONTINUE;
    }
    owns_event_data = TRUE;
  }

  const auto* raw = static_cast<const XIRawEvent*>(cookie->data);
  if (raw != nullptr &&
      static_cast<guint>(raw->detail) == self->hotkey_keycode) {
    if (cookie->evtype == XI_RawKeyPress) {
      if (self->hotkey_x11_release_timer_id != 0) {
        // X11 按键连发会紧挨着发送 Release + Press：取消待确认释放以吞掉伪松开。
        cancel_x11_release_timer(self);
      } else {
#ifdef XIKeyRepeat
        const gboolean is_repeat = (raw->flags & XIKeyRepeat) != 0;
#else
        const gboolean is_repeat = (raw->flags & (1 << 16)) != 0;
#endif
        if (!is_repeat && !self->hotkey_key_down) {
          self->hotkey_key_down = TRUE;
          fl_method_channel_invoke_method(self->hotkey_channel, "onKeyDown",
                                          nullptr, nullptr, nullptr, nullptr);
        }
      }
    } else if (cookie->evtype == XI_RawKeyRelease) {
      if (self->hotkey_key_down) {
        cancel_x11_release_timer(self);
        self->hotkey_x11_release_timer_id =
            g_timeout_add(20, hotkey_x11_commit_release_cb, self);
      }
    }
  }

  if (owns_event_data) {
    XFreeEventData(xdisplay, cookie);
  }
  return GDK_FILTER_CONTINUE;
}

static void unregister_x11_hotkey(MyApplication* self) {
  cancel_x11_release_timer(self);
  reset_hotkey_key_down(self);
  self->hotkey_keycode = 0;
  if (self->hotkey_x11_filter_installed) {
    gdk_window_remove_filter(nullptr, hotkey_x11_filter, self);
    self->hotkey_x11_filter_installed = FALSE;
  }
  if (self->hotkey_x11_events_selected) {
    GdkDisplay* display = gdk_display_get_default();
    if (display != nullptr && GDK_IS_X11_DISPLAY(display)) {
      Display* xdisplay = gdk_x11_display_get_xdisplay(display);
      Window root = XDefaultRootWindow(xdisplay);
      unsigned char mask_bytes[XIMaskLen(XI_LASTEVENT)];
      copy_existing_xi_master_mask(xdisplay, root, mask_bytes,
                                   sizeof(mask_bytes));
      XIClearMask(mask_bytes, XI_RawKeyPress);
      XIClearMask(mask_bytes, XI_RawKeyRelease);

      XIEventMask evmask;
      evmask.deviceid = XIAllMasterDevices;
      evmask.mask_len = sizeof(mask_bytes);
      evmask.mask = mask_bytes;

      g_hotkey_x11_error_code = 0;
      XErrorHandler prev = XSetErrorHandler(hotkey_x11_error_handler);
      XISelectEvents(xdisplay, root, &evmask, 1);
      XSync(xdisplay, False);
      XSetErrorHandler(prev);
    }
    self->hotkey_x11_events_selected = FALSE;
  }
}

static FlValue* register_x11_hotkey(MyApplication* self, guint keycode) {
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_X11_DISPLAY(display)) {
    return make_hotkey_result(FALSE, "unsupportedPlatform", FALSE, 0);
  }
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);

  int xi_opcode = -1;
  int xi_event = 0;
  int xi_error = 0;
  if (!XQueryExtension(xdisplay, "XInputExtension", &xi_opcode, &xi_event,
                       &xi_error)) {
    return make_hotkey_result(FALSE, "unsupportedPlatform", FALSE, 0);
  }
  int major = 2;
  int minor = 0;
  if (XIQueryVersion(xdisplay, &major, &minor) != Success || major < 2) {
    return make_hotkey_result(FALSE, "unsupportedPlatform", FALSE, 0);
  }

  Window root = XDefaultRootWindow(xdisplay);
  unsigned char mask_bytes[XIMaskLen(XI_LASTEVENT)];
  copy_existing_xi_master_mask(xdisplay, root, mask_bytes, sizeof(mask_bytes));
  XISetMask(mask_bytes, XI_RawKeyPress);
  XISetMask(mask_bytes, XI_RawKeyRelease);

  XIEventMask evmask;
  evmask.deviceid = XIAllMasterDevices;
  evmask.mask_len = sizeof(mask_bytes);
  evmask.mask = mask_bytes;

  g_hotkey_x11_error_code = 0;
  XErrorHandler previous_handler = XSetErrorHandler(hotkey_x11_error_handler);
  XISelectEvents(xdisplay, root, &evmask, 1);
  XSync(xdisplay, False);
  XSetErrorHandler(previous_handler);
  if (g_hotkey_x11_error_code != 0) {
    return make_hotkey_result(FALSE, "failed", TRUE, g_hotkey_x11_error_code);
  }

  self->hotkey_xi_opcode = xi_opcode;
  self->hotkey_x11_events_selected = TRUE;
  self->hotkey_keycode = keycode;
  self->hotkey_key_down = FALSE;
  if (!self->hotkey_x11_filter_installed) {
    gdk_window_add_filter(nullptr, hotkey_x11_filter, self);
    self->hotkey_x11_filter_installed = TRUE;
  }
  return make_hotkey_result(TRUE, "registered", FALSE, 0);
}
#endif

// 将 lib/core/hotkey_codes.dart 中的 X11 keycode (evdev + 8) 映射为
// XDG GlobalShortcuts preferred_trigger 键名。
static const gchar* keycode_to_portal_trigger(guint keycode) {
  switch (keycode) {
    case 38: return "a";
    case 56: return "b";
    case 54: return "c";
    case 40: return "d";
    case 26: return "e";
    case 41: return "f";
    case 42: return "g";
    case 43: return "h";
    case 31: return "i";
    case 44: return "j";
    case 45: return "k";
    case 46: return "l";
    case 58: return "m";
    case 57: return "n";
    case 32: return "o";
    case 33: return "p";
    case 24: return "q";
    case 27: return "r";
    case 39: return "s";
    case 28: return "t";
    case 30: return "u";
    case 55: return "v";
    case 25: return "w";
    case 53: return "x";
    case 29: return "y";
    case 52: return "z";
    case 19: return "0";
    case 10: return "1";
    case 11: return "2";
    case 12: return "3";
    case 13: return "4";
    case 14: return "5";
    case 15: return "6";
    case 16: return "7";
    case 17: return "8";
    case 18: return "9";
    case 67: return "F1";
    case 68: return "F2";
    case 69: return "F3";
    case 70: return "F4";
    case 71: return "F5";
    case 72: return "F6";
    case 73: return "F7";
    case 74: return "F8";
    case 75: return "F9";
    case 76: return "F10";
    case 95: return "F11";
    case 96: return "F12";
    case 65: return "space";
    case 66: return "Caps_Lock";
    case 118: return "Insert";
    case 127: return "Delete";
    case 110: return "Home";
    case 115: return "End";
    case 112: return "Prior";
    case 117: return "Next";
    case 49: return "grave";
    case 20: return "minus";
    case 21: return "equal";
    case 34: return "bracketleft";
    case 35: return "bracketright";
    case 51: return "backslash";
    case 47: return "semicolon";
    case 48: return "apostrophe";
    case 59: return "comma";
    case 60: return "period";
    case 61: return "slash";
    default: return nullptr;
  }
}

struct PortalOpData {
  GWeakRef app_ref;
  guint generation;
  guint keycode;
  gchar* expected_request_path;
};

static PortalOpData* portal_op_data_new(MyApplication* self, guint generation,
                                        guint keycode) {
  auto* data = g_new0(PortalOpData, 1);
  g_weak_ref_init(&data->app_ref, self);
  data->generation = generation;
  data->keycode = keycode;
  return data;
}

static void portal_op_data_free(gpointer ptr) {
  auto* data = static_cast<PortalOpData*>(ptr);
  if (data == nullptr) {
    return;
  }
  g_weak_ref_clear(&data->app_ref);
  g_free(data->expected_request_path);
  g_free(data);
}

static void unsubscribe_portal_signals(MyApplication* self) {
  if (self->portal_bus != nullptr) {
    if (self->portal_response_sub_id != 0) {
      g_dbus_connection_signal_unsubscribe(self->portal_bus,
                                           self->portal_response_sub_id);
      self->portal_response_sub_id = 0;
    }
    if (self->portal_activated_sub_id != 0) {
      g_dbus_connection_signal_unsubscribe(self->portal_bus,
                                           self->portal_activated_sub_id);
      self->portal_activated_sub_id = 0;
    }
    if (self->portal_deactivated_sub_id != 0) {
      g_dbus_connection_signal_unsubscribe(self->portal_bus,
                                           self->portal_deactivated_sub_id);
      self->portal_deactivated_sub_id = 0;
    }
  } else {
    self->portal_response_sub_id = 0;
    self->portal_activated_sub_id = 0;
    self->portal_deactivated_sub_id = 0;
  }
}

static void respond_hotkey_call(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlValue) owned_value = value;
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(owned_value));
  if (!fl_method_call_respond(call, response, nullptr)) {
    g_warning("flspeak/global_hotkey: failed to respond to method call");
  }
}

static void unregister_portal_hotkey(MyApplication* self,
                                     gboolean cancel_pending) {
  self->portal_generation++;
  if (self->portal_cancellable != nullptr) {
    g_cancellable_cancel(self->portal_cancellable);
    g_clear_object(&self->portal_cancellable);
  }
  unsubscribe_portal_signals(self);
  if (cancel_pending && self->portal_pending_call != nullptr) {
    FlMethodCall* pending = self->portal_pending_call;
    self->portal_pending_call = nullptr;
    respond_hotkey_call(pending, make_hotkey_result(FALSE, "failed", FALSE, 0));
    g_object_unref(pending);
  }
  if (self->portal_session_handle != nullptr) {
    if (self->portal_bus != nullptr) {
      g_dbus_connection_call(
          self->portal_bus, kPortalBusName, self->portal_session_handle,
          kPortalSessionIface, "Close", nullptr, nullptr,
          G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr, nullptr);
    }
    g_clear_pointer(&self->portal_session_handle, g_free);
  }
  g_clear_object(&self->portal_bus);
}

static void finish_portal_registration(MyApplication* self, gboolean ok,
                                       const gchar* reason, gboolean has_code,
                                       int code) {
  FlMethodCall* pending = self->portal_pending_call;
  self->portal_pending_call = nullptr;
  if (!ok) {
    unregister_portal_hotkey(self, FALSE);
  }
  if (pending != nullptr) {
    respond_hotkey_call(pending,
                        make_hotkey_result(ok, reason, has_code, code));
    g_object_unref(pending);
  }
}

static void unregister_hotkey(MyApplication* self) {
#ifdef GDK_WINDOWING_X11
  unregister_x11_hotkey(self);
#endif
  unregister_portal_hotkey(self, TRUE);
  reset_hotkey_key_down(self);
  self->hotkey_keycode = 0;
}

static gchar* make_portal_request_path(GDBusConnection* bus,
                                       const gchar* handle_token) {
  const gchar* unique = g_dbus_connection_get_unique_name(bus);
  if (unique == nullptr || handle_token == nullptr) {
    return nullptr;
  }
  const gchar* raw = unique[0] == ':' ? unique + 1 : unique;
  g_autofree gchar* sender = g_strdup(raw);
  for (gchar* p = sender; *p != '\0'; ++p) {
    if (*p == '.') {
      *p = '_';
    }
  }
  return g_strdup_printf("/org/freedesktop/portal/desktop/request/%s/%s",
                         sender, handle_token);
}

static MyApplication* acquire_app_weak(GWeakRef* ref) {
  gpointer raw = g_weak_ref_get(ref);
  return raw != nullptr ? MY_APPLICATION(raw) : nullptr;
}

static void portal_shortcut_signal_cb(GDBusConnection*, const gchar*,
                                      const gchar*, const gchar*,
                                      const gchar* signal_name,
                                      GVariant* parameters, gpointer user_data) {
  auto* self = MY_APPLICATION(user_data);
  if (self->portal_session_handle == nullptr ||
      self->hotkey_channel == nullptr || parameters == nullptr ||
      !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(osta{sv})"))) {
    return;
  }
  const gchar* session_handle = nullptr;
  const gchar* shortcut_id = nullptr;
  g_variant_get(parameters, "(&o&st@a{sv})", &session_handle, &shortcut_id,
                nullptr, nullptr);
  if (g_strcmp0(session_handle, self->portal_session_handle) != 0 ||
      g_strcmp0(shortcut_id, kPortalShortcutId) != 0) {
    return;
  }
  if (g_strcmp0(signal_name, "Activated") == 0) {
    if (!self->hotkey_key_down) {
      self->hotkey_key_down = TRUE;
      fl_method_channel_invoke_method(self->hotkey_channel, "onKeyDown",
                                      nullptr, nullptr, nullptr, nullptr);
    }
  } else if (g_strcmp0(signal_name, "Deactivated") == 0) {
    if (self->hotkey_key_down) {
      self->hotkey_key_down = FALSE;
      fl_method_channel_invoke_method(self->hotkey_channel, "onKeyUp",
                                      nullptr, nullptr, nullptr, nullptr);
    }
  }
}

static void portal_bind_shortcuts_response_cb(GDBusConnection*, const gchar*,
                                              const gchar*, const gchar*,
                                              const gchar*,
                                              GVariant* parameters,
                                              gpointer user_data) {
  auto* op = static_cast<PortalOpData*>(user_data);
  g_autoptr(MyApplication) self = acquire_app_weak(&op->app_ref);
  if (self == nullptr || op->generation != self->portal_generation) {
    return;
  }
  if (self->portal_bus != nullptr && self->portal_response_sub_id != 0) {
    g_dbus_connection_signal_unsubscribe(self->portal_bus,
                                         self->portal_response_sub_id);
    self->portal_response_sub_id = 0;
  }
  if (parameters == nullptr ||
      !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ua{sv})"))) {
    finish_portal_registration(self, FALSE, "failed", FALSE, 0);
    return;
  }
  guint32 response_code = 2;
  g_variant_get(parameters, "(u@a{sv})", &response_code, nullptr);
  if (response_code == 0) {
    self->hotkey_keycode = op->keycode;
    self->hotkey_key_down = FALSE;
    finish_portal_registration(self, TRUE, "registered", FALSE, 0);
  } else if (response_code == 1) {
    finish_portal_registration(self, FALSE, "permissionDenied", TRUE, 1);
  } else {
    finish_portal_registration(self, FALSE, "failed", TRUE,
                               static_cast<int>(response_code));
  }
}

static void portal_bind_shortcuts_reply_cb(GObject* source_object,
                                           GAsyncResult* res,
                                           gpointer user_data) {
  PortalOpData* op = static_cast<PortalOpData*>(user_data);
  g_autoptr(MyApplication) self = acquire_app_weak(&op->app_ref);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source_object), res, &error);
  if (self == nullptr || op->generation != self->portal_generation) {
    portal_op_data_free(op);
    return;
  }
  if (error != nullptr) {
    const int code = error->code;
    portal_op_data_free(op);
    finish_portal_registration(self, FALSE, "failed", TRUE, code);
    return;
  }
  if (reply != nullptr && self->portal_pending_call != nullptr) {
    const gchar* actual_path = nullptr;
    g_variant_get(reply, "(&o)", &actual_path);
    if (actual_path != nullptr &&
        g_strcmp0(actual_path, op->expected_request_path) != 0 &&
        self->portal_bus != nullptr) {
      if (self->portal_response_sub_id != 0) {
        g_dbus_connection_signal_unsubscribe(self->portal_bus,
                                             self->portal_response_sub_id);
      }
      auto* sig_op =
          portal_op_data_new(self, op->generation, op->keycode);
      self->portal_response_sub_id = g_dbus_connection_signal_subscribe(
          self->portal_bus, kPortalBusName, kPortalRequestIface, "Response",
          actual_path, nullptr, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
          portal_bind_shortcuts_response_cb, sig_op,
          portal_op_data_free);
    }
  }
  portal_op_data_free(op);
}

static void portal_send_bind_shortcuts(MyApplication* self, guint generation,
                                       guint keycode) {
  const gchar* trigger = keycode_to_portal_trigger(keycode);
  if (trigger == nullptr || self->portal_session_handle == nullptr ||
      self->portal_bus == nullptr) {
    finish_portal_registration(self, FALSE, "unsupportedKey", FALSE, 0);
    return;
  }
  g_autofree gchar* req_token =
      g_strdup_printf("flspeak_req_%u", ++self->portal_token_counter);
  g_autofree gchar* expected_path =
      make_portal_request_path(self->portal_bus, req_token);
  if (expected_path == nullptr) {
    finish_portal_registration(self, FALSE, "failed", FALSE, 0);
    return;
  }

  auto* sig_op = portal_op_data_new(self, generation, keycode);
  sig_op->expected_request_path = g_strdup(expected_path);
  self->portal_response_sub_id = g_dbus_connection_signal_subscribe(
      self->portal_bus, kPortalBusName, kPortalRequestIface, "Response",
      expected_path, nullptr, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
      portal_bind_shortcuts_response_cb, sig_op,
      portal_op_data_free);

  GVariantBuilder shortcut_opts;
  g_variant_builder_init(&shortcut_opts, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&shortcut_opts, "{sv}", "description",
                        g_variant_new_string("Push to talk"));
  g_variant_builder_add(&shortcut_opts, "{sv}", "preferred_trigger",
                        g_variant_new_string(trigger));

  GVariantBuilder shortcuts;
  g_variant_builder_init(&shortcuts, G_VARIANT_TYPE("a(sa{sv})"));
  g_variant_builder_add(&shortcuts, "(sa{sv})", kPortalShortcutId,
                        &shortcut_opts);

  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(req_token));

  auto* call_op = portal_op_data_new(self, generation, keycode);
  call_op->expected_request_path = g_strdup(expected_path);
  g_dbus_connection_call(
      self->portal_bus, kPortalBusName, kPortalObjectPath,
      kPortalGlobalShortcutsIface, "BindShortcuts",
      g_variant_new("(oa(sa{sv})sa{sv})", self->portal_session_handle,
                    &shortcuts, "", &options),
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1,
      self->portal_cancellable, portal_bind_shortcuts_reply_cb, call_op);
}

static void portal_create_session_response_cb(GDBusConnection*, const gchar*,
                                              const gchar*, const gchar*,
                                              const gchar*,
                                              GVariant* parameters,
                                              gpointer user_data) {
  auto* op = static_cast<PortalOpData*>(user_data);
  g_autoptr(MyApplication) self = acquire_app_weak(&op->app_ref);
  if (self == nullptr || op->generation != self->portal_generation) {
    return;
  }
  if (self->portal_bus != nullptr && self->portal_response_sub_id != 0) {
    g_dbus_connection_signal_unsubscribe(self->portal_bus,
                                         self->portal_response_sub_id);
    self->portal_response_sub_id = 0;
  }
  if (parameters == nullptr ||
      !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ua{sv})"))) {
    finish_portal_registration(self, FALSE, "failed", FALSE, 0);
    return;
  }
  guint32 response_code = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response_code, &results);
  if (response_code == 1) {
    finish_portal_registration(self, FALSE, "permissionDenied", TRUE, 1);
    return;
  }
  if (response_code != 0) {
    finish_portal_registration(self, FALSE, "failed", TRUE,
                               static_cast<int>(response_code));
    return;
  }

  g_autoptr(GVariant) session_val =
      results != nullptr ? g_variant_lookup_value(results, "session_handle", nullptr)
                         : nullptr;
  const gchar* session_handle = nullptr;
  if (session_val != nullptr &&
      (g_variant_is_of_type(session_val, G_VARIANT_TYPE_STRING) ||
       g_variant_is_of_type(session_val, G_VARIANT_TYPE_OBJECT_PATH))) {
    session_handle = g_variant_get_string(session_val, nullptr);
  }
  if (session_handle == nullptr || !g_variant_is_object_path(session_handle)) {
    finish_portal_registration(self, FALSE, "failed", FALSE, 0);
    return;
  }
  g_free(self->portal_session_handle);
  self->portal_session_handle = g_strdup(session_handle);
  portal_send_bind_shortcuts(self, op->generation, op->keycode);
}

static void portal_create_session_reply_cb(GObject* source_object,
                                           GAsyncResult* res,
                                           gpointer user_data) {
  PortalOpData* op = static_cast<PortalOpData*>(user_data);
  g_autoptr(MyApplication) self = acquire_app_weak(&op->app_ref);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source_object), res, &error);
  if (self == nullptr || op->generation != self->portal_generation) {
    portal_op_data_free(op);
    return;
  }
  if (error != nullptr) {
    const int code = error->code;
    portal_op_data_free(op);
    finish_portal_registration(self, FALSE, "failed", TRUE, code);
    return;
  }
  if (reply != nullptr && self->portal_session_handle == nullptr &&
      self->portal_pending_call != nullptr) {
    const gchar* actual_path = nullptr;
    g_variant_get(reply, "(&o)", &actual_path);
    if (actual_path != nullptr &&
        g_strcmp0(actual_path, op->expected_request_path) != 0 &&
        self->portal_bus != nullptr) {
      if (self->portal_response_sub_id != 0) {
        g_dbus_connection_signal_unsubscribe(self->portal_bus,
                                             self->portal_response_sub_id);
      }
      auto* sig_op =
          portal_op_data_new(self, op->generation, op->keycode);
      self->portal_response_sub_id = g_dbus_connection_signal_subscribe(
          self->portal_bus, kPortalBusName, kPortalRequestIface, "Response",
          actual_path, nullptr, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
          portal_create_session_response_cb, sig_op,
          portal_op_data_free);
    }
  }
  portal_op_data_free(op);
}

static void portal_probe_done_cb(GObject* source_object, GAsyncResult* res,
                                 gpointer user_data) {
  PortalOpData* op = static_cast<PortalOpData*>(user_data);
  g_autoptr(MyApplication) self = acquire_app_weak(&op->app_ref);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source_object), res, &error);
  if (self == nullptr || op->generation != self->portal_generation) {
    portal_op_data_free(op);
    return;
  }
  guint32 version = 0;
  if (reply != nullptr) {
    g_autoptr(GVariant) inner = nullptr;
    g_variant_get(reply, "(v)", &inner);
    if (inner != nullptr && g_variant_is_of_type(inner, G_VARIANT_TYPE_UINT32)) {
      version = g_variant_get_uint32(inner);
    }
  }
  if (error != nullptr || version < 1 || self->portal_bus == nullptr) {
    portal_op_data_free(op);
    finish_portal_registration(self, FALSE, "unsupportedPlatform", FALSE, 0);
    return;
  }

  self->portal_activated_sub_id = g_dbus_connection_signal_subscribe(
      self->portal_bus, kPortalBusName, kPortalGlobalShortcutsIface,
      "Activated", kPortalObjectPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      portal_shortcut_signal_cb, self, nullptr);
  self->portal_deactivated_sub_id = g_dbus_connection_signal_subscribe(
      self->portal_bus, kPortalBusName, kPortalGlobalShortcutsIface,
      "Deactivated", kPortalObjectPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      portal_shortcut_signal_cb, self, nullptr);

  g_autofree gchar* req_token =
      g_strdup_printf("flspeak_req_%u", ++self->portal_token_counter);
  g_autofree gchar* sess_token =
      g_strdup_printf("flspeak_sess_%u", ++self->portal_token_counter);
  g_autofree gchar* expected_path =
      make_portal_request_path(self->portal_bus, req_token);
  if (expected_path == nullptr) {
    portal_op_data_free(op);
    finish_portal_registration(self, FALSE, "failed", FALSE, 0);
    return;
  }

  auto* sig_op = portal_op_data_new(self, op->generation, op->keycode);
  sig_op->expected_request_path = g_strdup(expected_path);
  self->portal_response_sub_id = g_dbus_connection_signal_subscribe(
      self->portal_bus, kPortalBusName, kPortalRequestIface, "Response",
      expected_path, nullptr, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
      portal_create_session_response_cb, sig_op,
      portal_op_data_free);

  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(req_token));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(sess_token));

  auto* call_op = portal_op_data_new(self, op->generation, op->keycode);
  call_op->expected_request_path = g_strdup(expected_path);
  portal_op_data_free(op);

  g_dbus_connection_call(
      self->portal_bus, kPortalBusName, kPortalObjectPath,
      kPortalGlobalShortcutsIface, "CreateSession",
      g_variant_new("(a{sv})", &options), G_VARIANT_TYPE("(o)"),
      G_DBUS_CALL_FLAGS_NONE, -1, self->portal_cancellable,
      portal_create_session_reply_cb, call_op);
}

static void portal_bus_ready_cb(GObject*, GAsyncResult* res,
                                gpointer user_data) {
  PortalOpData* op = static_cast<PortalOpData*>(user_data);
  g_autoptr(MyApplication) self = acquire_app_weak(&op->app_ref);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_finish(res, &error);
  if (self == nullptr || op->generation != self->portal_generation) {
    portal_op_data_free(op);
    return;
  }
  if (bus == nullptr || error != nullptr) {
    portal_op_data_free(op);
    finish_portal_registration(self, FALSE, "unsupportedPlatform", FALSE, 0);
    return;
  }

  self->portal_bus = G_DBUS_CONNECTION(g_object_ref(bus));
  g_dbus_connection_call(
      self->portal_bus, kPortalBusName, kPortalObjectPath,
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", kPortalGlobalShortcutsIface, "version"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, -1,
      self->portal_cancellable, portal_probe_done_cb, op);
}

static void start_portal_hotkey_registration(MyApplication* self, guint keycode,
                                             FlMethodCall* call) {
  if (keycode_to_portal_trigger(keycode) == nullptr) {
    respond_hotkey_call(
        call, make_hotkey_result(FALSE, "unsupportedKey", FALSE, 0));
    return;
  }
  self->portal_cancellable = g_cancellable_new();
  self->portal_pending_call = FL_METHOD_CALL(g_object_ref(call));
  auto* op = portal_op_data_new(self, self->portal_generation, keycode);
  g_bus_get(G_BUS_TYPE_SESSION, self->portal_cancellable, portal_bus_ready_cb,
            op);
}

static void hotkey_method_call_cb(FlMethodChannel*, FlMethodCall* call,
                                  gpointer data) {
  auto* self = MY_APPLICATION(data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (strcmp(name, "register") == 0) {
    unregister_hotkey(self);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_INT) {
      respond_hotkey_call(
          call, make_hotkey_result(FALSE, "unsupportedKey", FALSE, 0));
      return;
    }
    const int64_t raw_code = fl_value_get_int(args);
    if (raw_code <= 0 || raw_code > G_MAXUINT) {
      respond_hotkey_call(
          call, make_hotkey_result(FALSE, "unsupportedKey", FALSE, 0));
      return;
    }
    const guint keycode = static_cast<guint>(raw_code);
    switch (detect_session_backend()) {
      case LinuxSessionBackend::kPureX11:
#ifdef GDK_WINDOWING_X11
        respond_hotkey_call(call, register_x11_hotkey(self, keycode));
#else
        respond_hotkey_call(
            call, make_hotkey_result(FALSE, "unsupportedPlatform", FALSE, 0));
#endif
        break;
      case LinuxSessionBackend::kWayland:
      case LinuxSessionBackend::kXWayland:
        start_portal_hotkey_registration(self, keycode, call);
        break;
      case LinuxSessionBackend::kUnknown:
        respond_hotkey_call(
            call, make_hotkey_result(FALSE, "unsupportedPlatform", FALSE, 0));
        break;
    }
    return;
  }
  if (strcmp(name, "unregister") == 0) {
    unregister_hotkey(self);
    respond_hotkey_call(call, fl_value_new_bool(TRUE));
    return;
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  if (!fl_method_call_respond(call, response, nullptr)) {
    g_warning("flspeak/global_hotkey: failed to respond to method call");
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication*, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "FlSpeak");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "FlSpeak");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // 全局按住说话热键通道：纯 X11 走 XInput2 被动观察；Wayland/XWayland 走
  // GlobalShortcuts Portal，不可用时退回应用内按键。
  FlEngine* engine = fl_view_get_engine(view);
  self->hotkey_codec = FL_METHOD_CODEC(fl_standard_method_codec_new());
  self->hotkey_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "flspeak/global_hotkey",
      self->hotkey_codec);
  fl_method_channel_set_method_call_handler(self->hotkey_channel,
                                            hotkey_method_call_cb, self,
                                            nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->hotkey_channel);
  unregister_hotkey(self);
  g_clear_object(&self->hotkey_codec);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->hotkey_xi_opcode = -1;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
