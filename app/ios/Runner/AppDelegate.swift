import Flutter
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
  }

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
