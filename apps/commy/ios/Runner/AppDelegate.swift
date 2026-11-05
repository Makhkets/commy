import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var coreBridge: CoreBridge?
  private var pendingURLs: [URL] = []

  func receive(_ url: URL) {
    if let coreBridge { coreBridge.receive(url) }
    else { pendingURLs = Array((pendingURLs + [url]).suffix(10)) }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CommyCore") {
      coreBridge = CoreBridge(messenger: registrar.messenger())
      for url in pendingURLs { coreBridge?.receive(url) }
      pendingURLs.removeAll()
    }
  }
}
