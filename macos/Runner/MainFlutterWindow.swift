// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目。
// 原始许可证：FlClash 应用代码为 GPL-3.0；其 plugins/window 插件为 MIT。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7 与 be84736605527034689c95bf27828ff27d912c5e。
// 本片段取自 plugins/window（MIT），可按 MIT 或 GPL-3.0 使用：对应
// plugins/window/macos/window/Sources/window/WindowStyle.swift、WindowController.swift
// 与 WindowEffectView.swift。

import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

private enum WindowEffect: String {
  case none
  case transparent
  case blur
  case acrylic
  case mica
  case glass
}

@available(macOS 26.0, *)
private enum SidebarGlass {
  #if compiler(>=6.2)
  // 分栏侧栏玻璃为私有变体，复制 NSSplitViewController 的侧栏配置以随系统外观自适应。
  private static let sidebarAttributes: [String: Any]? = {
    let split = NSSplitViewController()
    let sidebar = NSViewController(nibName: nil, bundle: nil)
    sidebar.view = NSView()
    let content = NSViewController(nibName: nil, bundle: nil)
    content.view = NSView()
    split.addSplitViewItem(NSSplitViewItem(sidebarWithViewController: sidebar))
    split.addSplitViewItem(NSSplitViewItem(viewController: content))
    split.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    split.view.layoutSubtreeIfNeeded()
    guard let glass = firstGlass(in: split.view) else {
      return nil
    }
    var attributes: [String: Any] = [:]
    for key in ["_variant", "_adaptiveAppearance"]
    where glass.responds(to: NSSelectorFromString(key)) {
      attributes[key] = glass.value(forKey: key)
    }
    return attributes
  }()

  static var isAvailable: Bool {
    sidebarAttributes != nil
  }

  static func make() -> NSGlassEffectView {
    let glass = NSGlassEffectView()
    for (key, value) in sidebarAttributes ?? [:]
    where glass.responds(to: NSSelectorFromString("set\(key):")) {
      glass.setValue(value, forKey: key)
    }
    return glass
  }

  private static func firstGlass(in view: NSView) -> NSGlassEffectView? {
    if let glass = view as? NSGlassEffectView {
      return glass
    }
    for subview in view.subviews {
      if let glass = firstGlass(in: subview) {
        return glass
      }
    }
    return nil
  }
  #else
  static var isAvailable: Bool { false }
  #endif
}

private final class EffectHostViewController: NSViewController {
  let flutterViewController: FlutterViewController
  let effectView = NSVisualEffectView()
  private var glassView: NSView?

  init(hosting flutterViewController: FlutterViewController) {
    self.flutterViewController = flutterViewController
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    effectView.frame = flutterViewController.view.frame
    effectView.autoresizingMask = [.width, .height]
    effectView.blendingMode = .behindWindow
    effectView.maskImage = NSImage()
    effectView.state = .inactive
    addChild(flutterViewController)
    attachFlutterView()
    view = effectView
  }

  func attachFlutterView() {
    let flutterView = flutterViewController.view
    guard flutterView.superview !== effectView else {
      return
    }
    flutterView.translatesAutoresizingMaskIntoConstraints = true
    flutterView.frame = effectView.bounds
    flutterView.autoresizingMask = [.width, .height]
    effectView.addSubview(flutterView)
  }

  @available(macOS 26.0, *)
  func showGlass(tint: NSColor?) {
    #if compiler(>=6.2)
    let glass: NSGlassEffectView
    if let existing = glassView as? NSGlassEffectView {
      glass = existing
    } else {
      glass = SidebarGlass.make()
      glass.frame = effectView.bounds
      glass.autoresizingMask = [.width, .height]
      effectView.addSubview(glass)
      glass.contentView = flutterViewController.view
      glassView = glass
    }
    glass.tintColor = tint
    #else
    removeGlass()
    #endif
  }

  func removeGlass() {
    guard let glassView else {
      return
    }
    attachFlutterView()
    glassView.removeFromSuperview()
    self.glassView = nil
  }
}

private enum WindowEffectView {
  static func isSupported(_ effect: WindowEffect) -> Bool {
    switch effect {
    case .none, .transparent, .blur, .acrylic:
      return true
    case .mica:
      return false
    case .glass:
      if #available(macOS 26.0, *) {
        return SidebarGlass.isAvailable
      }
      return false
    }
  }

  static func appearance(brightness: String?) -> NSAppearance? {
    switch brightness {
    case "light":
      return NSAppearance(named: .aqua)
    case "dark":
      return NSAppearance(named: .darkAqua)
    default:
      return nil
    }
  }

  static func install(in window: NSWindow) {
    guard let flutterViewController = window.contentViewController as? FlutterViewController else {
      return
    }
    let frame = window.frame
    let host = EffectHostViewController(hosting: flutterViewController)
    window.contentViewController = host
    host.attachFlutterView()
    window.setFrame(frame, display: true)
  }

  static func apply(
    _ effect: WindowEffect,
    tint: NSColor?,
    appearance: NSAppearance?,
    to window: NSWindow
  ) {
    guard let host = window.contentViewController as? EffectHostViewController else {
      return
    }
    let effectView = host.effectView
    switch effect {
    case .none, .transparent, .mica, .glass:
      effectView.maskImage = NSImage()
      effectView.state = .inactive
      effectView.layer?.backgroundColor = nil
      host.flutterViewController.backgroundColor = .clear
      if effect == .none {
        window.isOpaque = true
      } else {
        window.isOpaque = false
        window.backgroundColor = .clear
      }
      if effect == .glass, #available(macOS 26.0, *) {
        host.showGlass(tint: tint)
      } else {
        host.removeGlass()
      }
    case .blur, .acrylic:
      host.removeGlass()
      effectView.maskImage = nil
      effectView.material = effect == .blur ? .sidebar : .fullScreenUI
      effectView.state = .followsWindowActiveState
      effectView.appearance = appearance
      applyTint(tint, to: effectView)
      window.isOpaque = false
      window.backgroundColor = .clear
      host.flutterViewController.backgroundColor = .clear
    }
  }

  private static func applyTint(_ tint: NSColor?, to effectView: NSVisualEffectView) {
    guard let tint else {
      effectView.layer?.backgroundColor = nil
      return
    }
    effectView.wantsLayer = true
    effectView.layer?.backgroundColor = tint.cgColor
  }
}

// 两个热键事件常量在新 SDK 里类型不一致（UInt32 / Int），统一成 UInt32。
private let hotkeyPressed = UInt32(kEventHotKeyPressed)
private let hotkeyReleased = UInt32(kEventHotKeyReleased)

class MainFlutterWindow: NSWindow {
  /// 全局按住说话热键：Carbon RegisterEventHotKey 不需要任何系统权限，
  /// 代价是注册期间该按键被本应用独占，不再转发给其他应用。
  private var hotkeyRef: EventHotKeyRef?
  private var hotkeyEventHandler: EventHandlerRef?
  private var hotkeyChannel: FlutterMethodChannel?

  /// Flutter 主题的 surface 色。窗口底色与标题栏跟随主题，
  /// 圆角边缘不再露出系统默认的 windowBackgroundColor。
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    WindowEffectView.install(in: self)
    flutterViewController.backgroundColor = .clear
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
    if let hotkeyRef = hotkeyRef {
      UnregisterEventHotKey(hotkeyRef)
    }
    if let hotkeyEventHandler = hotkeyEventHandler {
      RemoveEventHandler(hotkeyEventHandler)
    }
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
      case "isEffectSupported":
        let rawName =
          (call.arguments as? String)
          ?? (call.arguments as? [String: Any])?["effect"] as? String
        guard let rawName, let effect = WindowEffect(rawValue: rawName) else {
          result(false)
          return
        }
        result(WindowEffectView.isSupported(effect))
      case "setEffect":
        guard
          let self = self,
          let args = call.arguments as? [String: Any],
          let rawName = args["effect"] as? String,
          let effect = WindowEffect(rawValue: rawName),
          WindowEffectView.isSupported(effect)
        else {
          result(false)
          return
        }
        let tintArgb = (args["tint"] as? NSNumber)?.intValue
        let tintColor = tintArgb.map { argb -> NSColor in
          let value = UInt32(bitPattern: Int32(truncatingIfNeeded: argb))
          return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: CGFloat((value >> 24) & 0xFF) / 255.0)
        }
        let appearance = WindowEffectView.appearance(
          brightness: args["brightness"] as? String)
        WindowEffectView.apply(effect, tint: tintColor, appearance: appearance, to: self)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupGlobalHotkey(_ controller: FlutterViewController) {
    hotkeyChannel = FlutterMethodChannel(
      name: "flspeak/global_hotkey",
      binaryMessenger: controller.engine.binaryMessenger)

    let handler: EventHandlerUPP = { _, event, userData in
      guard let event = event, let userData = userData else { return noErr }
      let window = unsafeBitCast(userData, to: MainFlutterWindow.self)
      switch UInt32(GetEventKind(event)) {
      case hotkeyPressed:
        window.hotkeyChannel?.invokeMethod("onKeyDown", arguments: nil)
      case hotkeyReleased:
        window.hotkeyChannel?.invokeMethod("onKeyUp", arguments: nil)
      default:
        break
      }
      return noErr
    }
    var specs = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: hotkeyPressed),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: hotkeyReleased),
    ]
    InstallEventHandler(
      GetApplicationEventTarget(),
      handler,
      specs.count,
      &specs,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &hotkeyEventHandler)

    hotkeyChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "register":
        guard let self = self, let keyCode = call.arguments as? Int else {
          result(false)
          return
        }
        result(self.registerHotkey(UInt32(keyCode)))
      case "unregister":
        self?.unregisterHotkey()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerHotkey(_ keyCode: UInt32) -> Bool {
    unregisterHotkey()
    // signature 取一个应用内唯一的四字符码即可，id 区分同应用内的多个热键。
    let hotKeyID = EventHotKeyID(signature: OSType(0x46_53_50_4B), id: 1)
    return RegisterEventHotKey(
      keyCode, 0, hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef
    ) == noErr
  }

  private func unregisterHotkey() {
    if let ref = hotkeyRef {
      UnregisterEventHotKey(ref)
      hotkeyRef = nil
    }
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
