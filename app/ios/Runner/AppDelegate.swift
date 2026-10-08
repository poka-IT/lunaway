import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LunawayFiles") {
      registerFiles(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LunawayNetwork") {
      network.register(messenger: registrar.messenger())
    }
  }

  private let network = NetworkWatch()

  /// The folder of the offline maps. They weigh hundreds of megabytes and
  /// download again from the server: Apple's storage guidelines ask such
  /// files to stay out of the iCloud and computer backups, which a flag on
  /// their folder does. The free room of its volume is read before a
  /// download, so that a pack never fills the device.
  private func registerFiles(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lunaway/files", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      do {
        switch call.method {
        case "excludeFromBackup":
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
          result(true)
        case "freeBytes":
          let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          result(values.volumeAvailableCapacityForImportantUsage.map { NSNumber(value: $0) })
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
      }
    }
  }
}

/// Whether the device has a network, and whether it is metered (a mobile
/// network, a phone's hotspot, Low Data Mode): the regions kept offline
/// update on Wi-Fi unless the user allows mobile data, and the app asks its
/// servers again as soon as a network comes back rather than a minute
/// later. One monitor for the run, started with the engine, so its first
/// answer is in before the app asks.
final class NetworkWatch: NSObject, FlutterStreamHandler {
  private let monitor = NWPathMonitor()
  private var sink: FlutterEventSink?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lunaway/network", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "current" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(Self.describe(self.monitor.currentPath))
    }
    FlutterEventChannel(name: "lunaway/network/changes", binaryMessenger: messenger)
      .setStreamHandler(self)
    monitor.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async { self?.sink?(Self.describe(path)) }
    }
    monitor.start(queue: DispatchQueue(label: "lunaway.network"))
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    // The state as it stands: the monitor's first word may have come before
    // anyone listened.
    events(Self.describe(monitor.currentPath))
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private static func describe(_ path: NWPath) -> [String: Bool] {
    let connected = path.status == .satisfied
    return ["connected": connected, "metered": !connected || path.isExpensive || path.isConstrained]
  }
}
