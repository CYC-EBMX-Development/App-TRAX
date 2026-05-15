import Flutter
import UIKit
import GoogleMaps
import AMapFoundationKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng")
    // AMap iOS SDK key, injected from ios/Flutter/AmapKey.xcconfig at build time.
    if let amapKey = Bundle.main.object(forInfoDictionaryKey: "AMAP_IOS_SDK_KEY") as? String,
       !amapKey.isEmpty,
       amapKey != "PASTE_YOUR_IOS_SDK_KEY_HERE" {
      AMapServices.shared().apiKey = amapKey
    } else {
      NSLog("[TRAX] AMap iOS SDK key missing. See ios/Flutter/AmapKey.xcconfig.example")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
