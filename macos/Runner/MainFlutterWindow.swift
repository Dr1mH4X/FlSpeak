// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目。
// 原始许可证：FlClash 应用代码为 GPL-3.0；其 plugins/window 插件为 MIT。
// 来源提交：7fd417fb9a9a277c6a9339a8ac87f907df7c25f7。
// 本片段取自 plugins/window（MIT），可按 MIT 或 GPL-3.0 使用：对应
// plugins/window/macos/window/Sources/window/WindowStyle.swift 的 .hidden 分支，
// 以及同目录 WindowController.swift 的 startDragging / maximize / setFullScreen。

import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

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
    self.setFrame(windowFrame, display: true)
    // FlClash 的隐藏标题栏组合：标题文字不画、标题栏透明、内容铺满窗口。
    // 系统红绿灯保留，由 Dart 侧按 78×32 的区域让位。
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)
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
