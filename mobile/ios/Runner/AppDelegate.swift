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

  private var screenGuardChannel: FlutterMethodChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Screen guard (lib/services/screen_guard.dart): tell Flutter when the
    // user takes a screenshot, so the email's sender can be notified.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MailSpaceScreenGuard") {
      let channel = FlutterMethodChannel(name: "mailspace/screen_guard", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        // iPhones can't block screenshots; "secure" is accepted and ignored.
        result(call.method == "secure" ? true : FlutterMethodNotImplemented)
      }
      screenGuardChannel = channel
      NotificationCenter.default.addObserver(
        forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.screenGuardChannel?.invokeMethod("screenshot", arguments: nil)
      }
    }
  }
}
