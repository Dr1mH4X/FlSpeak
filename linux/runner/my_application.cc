#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <string.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // 全局按住说话热键：X11 XGrabKey + 对应的平台通道。Wayland 没有通用的
  // 全局热键协议，register 直接失败，由 Dart 侧退到应用内按键。
  FlMethodChannel* hotkey_channel;
  FlMethodCodec* hotkey_codec;
  guint hotkey_keycode;  // 0 表示未注册。
  gboolean hotkey_filter_installed;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

#ifdef GDK_WINDOWING_X11
namespace {
// XGrabKey 的 BadAccess 是异步到达的，没有自定义错误处理器会直接终止进程。
gboolean g_hotkey_grab_failed = FALSE;

int hotkey_x11_error_handler(Display* display, XErrorEvent* event) {
  if (event->error_code == BadAccess) {
    g_hotkey_grab_failed = TRUE;
    return 0;
  }
  return 0;
}
}  // namespace

// 被 XGrabKey 抓住的按键走根窗口送到本进程；经 GDK 事件过滤器转发给 Dart，
// 并拦截下来——注册期间该键全局只属于按住说话，与 macOS Carbon 行为一致。
static GdkFilterReturn hotkey_x11_filter(GdkXEvent* xevent, GdkEvent* event,
                                         gpointer data) {
  auto* self = MY_APPLICATION(data);
  if (self->hotkey_keycode == 0 || self->hotkey_channel == nullptr) {
    return GDK_FILTER_CONTINUE;
  }
  auto* xev = static_cast<XEvent*>(xevent);
  if (xev->type != KeyPress && xev->type != KeyRelease) {
    return GDK_FILTER_CONTINUE;
  }
  if (xev->xkey.keycode != self->hotkey_keycode) {
    return GDK_FILTER_CONTINUE;
  }
  fl_method_channel_invoke_method(
      self->hotkey_channel, xev->type == KeyPress ? "onKeyDown" : "onKeyUp",
      nullptr, nullptr, nullptr, nullptr);
  return GDK_FILTER_REMOVE;
}
#endif

// 真实修饰键组合不抢（Ctrl+F5 之类照常工作），只额外接受锁键状态。
// 0/LockMask/Mod2/Mod5 四种组合覆盖 NumLock、CapsLock、ScrollLock 的任意
// 开关状态。
static const unsigned int kHotkeyLockMasks[] = {0, LockMask, Mod2Mask,
                                                Mod5Mask};

static void ungrab_hotkey(MyApplication* self) {
  if (self->hotkey_keycode == 0) {
    return;
  }
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gdk_display_get_default();
  if (display != nullptr && GDK_IS_X11_DISPLAY(display)) {
    Display* xdisplay = gdk_x11_display_get_xdisplay(display);
    Window root = XDefaultRootWindow(xdisplay);
    for (unsigned int mask : kHotkeyLockMasks) {
      XUngrabKey(xdisplay, static_cast<int>(self->hotkey_keycode), mask, root);
    }
  }
#endif
  self->hotkey_keycode = 0;
}

static gboolean grab_hotkey(MyApplication* self, guint keycode) {
  ungrab_hotkey(self);
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_X11_DISPLAY(display)) {
    return FALSE;
  }
  Display* xdisplay = gdk_x11_display_get_xdisplay(display);
  Window root = XDefaultRootWindow(xdisplay);

  g_hotkey_grab_failed = FALSE;
  XErrorHandler previous_handler = XSetErrorHandler(hotkey_x11_error_handler);
  for (unsigned int mask : kHotkeyLockMasks) {
    XGrabKey(xdisplay, static_cast<int>(keycode), mask, root, False,
             GrabModeAsync, GrabModeAsync);
  }
  XSync(xdisplay, False);
  XSetErrorHandler(previous_handler);
  if (g_hotkey_grab_failed) {
    // 键可能已被其他程序占用；把成功的几次 grab 也退掉再报失败。
    ungrab_hotkey(self);
    return FALSE;
  }

  self->hotkey_keycode = keycode;
  if (!self->hotkey_filter_installed) {
    gdk_window_add_filter(nullptr, hotkey_x11_filter, self);
    self->hotkey_filter_installed = TRUE;
  }
  return TRUE;
#else
  return FALSE;
#endif
}

static void hotkey_method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                                  gpointer data) {
  auto* self = MY_APPLICATION(data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlValue) result = nullptr;
  if (strcmp(name, "register") == 0) {
    gboolean ok = fl_value_get_type(args) == FL_VALUE_TYPE_INT &&
                  grab_hotkey(self,
                              static_cast<guint>(fl_value_get_int(args)));
    result = fl_value_new_bool(ok);
  } else if (strcmp(name, "unregister") == 0) {
    ungrab_hotkey(self);
    result = fl_value_new_bool(TRUE);
  }
  g_autoptr(FlMethodResponse) response =
      result != nullptr
          ? FL_METHOD_RESPONSE(fl_method_success_response_new(result))
          : FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  if (!fl_method_call_respond(call, response, nullptr)) {
    g_warning("flspeak/global_hotkey: 回应方法调用失败");
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
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

  // 全局按住说话热键通道；X11 上注册 XGrabKey，Wayland 上 register 失败，
  // 由 Dart 侧退回应用内按键。
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
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
#ifdef GDK_WINDOWING_X11
  if (self->hotkey_filter_installed) {
    gdk_window_remove_filter(nullptr, hotkey_x11_filter, self);
    self->hotkey_filter_installed = FALSE;
  }
#endif
  ungrab_hotkey(self);
  g_clear_object(&self->hotkey_channel);
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

static void my_application_init(MyApplication* self) {}

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
