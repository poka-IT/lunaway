import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // A first window wide enough for the desktop layout (list, map, details).
    // Set through setFrame after the content view controller, which would
    // otherwise size the window to its own view.
    var content = NSSize(width: 1280, height: 820)
    #if DEBUG
    // Screenshot runs only: a fixed content size. Never read in release.
    if let size = ProcessInfo.processInfo.environment["LUNAWAY_WINDOW"]?.split(separator: "x"),
       size.count == 2, let w = Double(size[0]), let h = Double(size[1]) {
      content = NSSize(width: w, height: h)
    }
    #endif
    let frame = self.frameRect(forContentRect: NSRect(origin: self.frame.origin, size: content))
    self.setFrame(frame, display: true)
    self.contentMinSize = NSSize(width: 360, height: 560)
    // The first frame above wins over a frame macOS would restore from a
    // previous run that ended abruptly.
    self.isRestorable = false
    self.center()

    #if DEBUG
    // Screenshot runs only: a window shown on every Space, so the map web view
    // renders even when the current Space belongs to a full-screen app.
    if ProcessInfo.processInfo.environment["LUNAWAY_ALL_SPACES"] == "1" {
      // Only an accessory app may put a window on another app's full-screen
      // Space; the Dock icon and the menu bar go away for the run.
      NSApp.setActivationPolicy(.accessory)
      // Stationary and auxiliary: Stage Manager would otherwise move the
      // window to its strip as soon as the person at the Mac switches to
      // another app, and a window off the screen draws nothing.
      self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      if #available(macOS 13.0, *) { self.collectionBehavior.insert(.auxiliary) }
      self.level = .floating
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.orderFrontRegardless() }
    }
    #endif

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
