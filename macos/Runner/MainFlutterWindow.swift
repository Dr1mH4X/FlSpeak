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

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupGlobalHotkey(flutterViewController)

    super.awakeFromNib()
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
