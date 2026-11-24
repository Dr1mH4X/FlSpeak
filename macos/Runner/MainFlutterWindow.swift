// Adapted from FlClash plugins/window (7fd417f, MIT): macos/window/Sources/window/WindowStyle.swift & WindowController.swift. See docs/THIRD-PARTY.md.

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 全局按住说话热键：通过 Listen-Only CGEventTap 观察物理按键事件，
  /// 只观察不吞键，依赖系统「输入监控」（Input Monitoring）运行时权限。
  private var eventTap: CFMachPort?
  private var eventTapRunLoopSource: CFRunLoopSource?
  private var targetKeyCode: CGKeyCode?
  private var isTargetKeyDown = false
  private var hotkeyChannel: FlutterMethodChannel?

  /// Flutter 主题的 surface 色。窗口底色与标题栏跟随主题，
  /// 圆角边缘不再露出系统默认的 windowBackgroundColor。
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // FlClash 的隐藏标题栏组合：标题文字不画、标题栏透明、内容铺满窗口。
    // 系统红绿灯保留，由 Dart 侧按 78×32 的区域让位。
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)
    DesktopCaptureFocusGuard.installIfNeeded()
    setupGlobalHotkey(flutterViewController)
    setupWindowChannel(flutterViewController)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(fullScreenStateChanged(_:)),
      name: NSWindow.didEnterFullScreenNotification,
      object: self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(fullScreenStateChanged(_:)),
      name: NSWindow.didExitFullScreenNotification,
      object: self)

    super.awakeFromNib()
  }

  deinit {
    unregisterHotkey()
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func fullScreenStateChanged(_ notification: Notification) {
    windowChannel?.invokeMethod(
      "onFullScreenChanged", arguments: styleMask.contains(.fullScreen))
  }

  private func setupWindowChannel(_ controller: FlutterViewController) {
    windowChannel = FlutterMethodChannel(
      name: "flspeak/window",
      binaryMessenger: controller.engine.binaryMessenger)

    windowChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setBackgroundColor":
        guard let self = self, let argb = call.arguments as? Int else {
          result(false)
          return
        }
        let value = UInt32(bitPattern: Int32(truncatingIfNeeded: argb))
        self.backgroundColor = NSColor(
          srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
          green: CGFloat((value >> 8) & 0xFF) / 255.0,
          blue: CGFloat(value & 0xFF) / 255.0,
          alpha: CGFloat((value >> 24) & 0xFF) / 255.0)
        result(true)
      case "startDragging":
        guard let event = self?.currentEvent else {
          result(false)
          return
        }
        // 通道调用返回时 pointer event 可能已经结束；排到主队列再取一次。
        DispatchQueue.main.async {
          self?.performDrag(with: event)
        }
        result(true)
      case "toggleZoom":
        if let self = self {
          if self.styleMask.contains(.fullScreen) {
            self.toggleFullScreen(nil)
          } else {
            self.zoom(nil)
          }
        }
        result(true)
      case "isFullScreen":
        result(self?.styleMask.contains(.fullScreen) ?? false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupGlobalHotkey(_ controller: FlutterViewController) {
    hotkeyChannel = FlutterMethodChannel(
      name: "flspeak/global_hotkey",
      binaryMessenger: controller.engine.binaryMessenger)

    hotkeyChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "register":
        guard let self = self,
          let rawCode = call.arguments as? Int,
          let keyCode = CGKeyCode(exactly: rawCode)
        else {
          result([
            "ok": false,
            "reason": "unsupportedKey",
            "code": nil,
          ] as [String: Any?])
          return
        }
        result(self.registerHotkey(keyCode))
      case "unregister":
        self?.unregisterHotkey()
        result(true)
      case "requestPermission":
        result(CGRequestListenEventAccess())
      case "openPermissionSettings":
        guard
          let url = URL(
            string:
              "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
          )
        else {
          result(false)
          return
        }
        result(NSWorkspace.shared.open(url))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerHotkey(_ keyCode: CGKeyCode) -> [String: Any?] {
    unregisterHotkey()
    let eventMask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
      }
      let window = Unmanaged<MainFlutterWindow>.fromOpaque(userInfo).takeUnretainedValue()
      return window.handleEventTap(type: type, event: event)
    }
    // 直接试探 CGEvent.tapCreate，不以 CGPreflightListenEventAccess() 短路；
    // 后者在进程内缓存旧结果，无法反映运行时在系统设置新授予的权限。
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: callback,
        userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    else {
      let granted = CGPreflightListenEventAccess()
      return [
        "ok": false,
        "reason": granted ? "failed" : "permissionDenied",
        "code": nil,
      ]
    }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      CFMachPortInvalidate(tap)
      return ["ok": false, "reason": "failed", "code": nil]
    }
    targetKeyCode = keyCode
    eventTap = tap
    eventTapRunLoopSource = source
    isTargetKeyDown = false
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return ["ok": true, "reason": "registered", "code": nil]
  }

  private func handleEventTap(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      if isTargetKeyDown {
        isTargetKeyDown = false
        hotkeyChannel?.invokeMethod("onKeyUp", arguments: nil)
      }
      return Unmanaged.passUnretained(event)
    }
    guard let target = targetKeyCode else {
      return Unmanaged.passUnretained(event)
    }
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == target else {
      return Unmanaged.passUnretained(event)
    }
    switch type {
    case .keyDown:
      if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
        break
      }
      if !isTargetKeyDown {
        isTargetKeyDown = true
        hotkeyChannel?.invokeMethod("onKeyDown", arguments: nil)
      }
    case .keyUp:
      if isTargetKeyDown {
        isTargetKeyDown = false
        hotkeyChannel?.invokeMethod("onKeyUp", arguments: nil)
      }
    case .flagsChanged:
      guard let mask = Self.modifierFlag(for: target) else { break }
      let down = event.flags.contains(mask)
      if down && !isTargetKeyDown {
        isTargetKeyDown = true
        hotkeyChannel?.invokeMethod("onKeyDown", arguments: nil)
      } else if !down && isTargetKeyDown {
        isTargetKeyDown = false
        hotkeyChannel?.invokeMethod("onKeyUp", arguments: nil)
      }
    default:
      break
    }
    return Unmanaged.passUnretained(event)
  }

  private static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags? {
    switch keyCode {
    case 0x39: return .maskAlphaShift
    case 0x38, 0x3C: return .maskShift
    case 0x3B, 0x3E: return .maskControl
    case 0x3A, 0x3D: return .maskAlternate
    case 0x37, 0x36: return .maskCommand
    case 0x3F: return .maskSecondaryFn
    default: return nil
    }
  }

  private func unregisterHotkey() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    if let source = eventTapRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      eventTapRunLoopSource = nil
    }
    if let tap = eventTap {
      CFMachPortInvalidate(tap)
      eventTap = nil
    }
    targetKeyCode = nil
    isTargetKeyDown = false
  }
}

/// 窗口共享启动时拦截外部应用激活，避免 WebRTC `RTCDesktopCapturer` 将被共享应用切到前台。
///
/// `webrtc::WindowCapturerMac::FocusOnSelectedSource()` 会对目标进程调用
/// `-[NSRunningApplication activateWithOptions:]` 并在返回 `NO` 时中止采集；
/// 在 `startCapture` / `startCaptureWithFPS:` 调用栈内对该调用直接返回 `true`，
/// 既保留窗口后台采集，又不抢占当前前台焦点。
private enum DesktopCaptureFocusGuard {
  private static let suppressionKey = "fls.suppressExternalAppActivation"
  private static var installed = false

  static var isSuppressing: Bool {
    (Thread.current.threadDictionary[suppressionKey] as? Int ?? 0) > 0
  }

  static func withSuppression<T>(_ body: () -> T) -> T {
    let dict = Thread.current.threadDictionary
    let depth = dict[suppressionKey] as? Int ?? 0
    dict[suppressionKey] = depth + 1
    defer {
      if depth == 0 {
        dict.removeObject(forKey: suppressionKey)
      } else {
        dict[suppressionKey] = depth
      }
    }
    return body()
  }

  static func installIfNeeded() {
    guard !installed else { return }
    installed = true

    let originalSelector = #selector(NSRunningApplication.activate(options:))
    let swizzledSelector = #selector(NSRunningApplication.fls_activate(options:))
    if let originalMethod = class_getInstanceMethod(NSRunningApplication.self, originalSelector),
      let swizzledMethod = class_getInstanceMethod(NSRunningApplication.self, swizzledSelector)
    {
      method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    guard let capturerClass: AnyClass = NSClassFromString("RTCDesktopCapturer") else { return }

    wrapMethod(capturerClass, selectorName: "startCaptureWithFPS:") { originalIMP, selector in
      typealias StartWithFPSIMP = @convention(c) (AnyObject, Selector, Int) -> Void
      let original = unsafeBitCast(originalIMP, to: StartWithFPSIMP.self)
      let block: @convention(block) (AnyObject, Int) -> Void = { receiver, fps in
        DesktopCaptureFocusGuard.withSuppression {
          original(receiver, selector, fps)
        }
      }
      return block
    }

    wrapMethod(capturerClass, selectorName: "startCapture") { originalIMP, selector in
      typealias StartIMP = @convention(c) (AnyObject, Selector) -> Void
      let original = unsafeBitCast(originalIMP, to: StartIMP.self)
      let block: @convention(block) (AnyObject) -> Void = { receiver in
        DesktopCaptureFocusGuard.withSuppression {
          original(receiver, selector)
        }
      }
      return block
    }
  }

  private static func wrapMethod(
    _ cls: AnyClass,
    selectorName: String,
    makeWrapper: (_ original: IMP, _ selector: Selector) -> Any
  ) {
    let selector = NSSelectorFromString(selectorName)
    guard let method = class_getInstanceMethod(cls, selector) else { return }
    let originalIMP = method_getImplementation(method)
    let block = makeWrapper(originalIMP, selector)
    method_setImplementation(method, imp_implementationWithBlock(block))
  }
}

private extension NSRunningApplication {
  @objc func fls_activate(options: NSApplication.ActivationOptions) -> Bool {
    if DesktopCaptureFocusGuard.isSuppressing && self != NSRunningApplication.current {
      return true
    }
    return fls_activate(options: options)
  }
}
