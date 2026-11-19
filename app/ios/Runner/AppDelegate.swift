import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var cachedPushToken: String?
  private var pendingTokenResults: [FlutterResult] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "br.com.feitolabs.trato/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "obterTokenPush" {
        self.requestPushToken(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestPushToken(result: @escaping FlutterResult) {
    if let token = cachedPushToken, !token.isEmpty {
      result(["token": token, "plataforma": "ios"])
      return
    }
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      guard let self else { return }
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        DispatchQueue.main.async {
          self.pendingTokenResults.append(result)
          UIApplication.shared.registerForRemoteNotifications()
        }
      case .notDetermined:
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
          DispatchQueue.main.async {
            if granted {
              self.pendingTokenResults.append(result)
              UIApplication.shared.registerForRemoteNotifications()
            } else {
              result(nil)
            }
          }
        }
      case .denied:
        DispatchQueue.main.async { result(nil) }
      @unknown default:
        DispatchQueue.main.async { result(nil) }
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    cachedPushToken = token
    let payload: [String: String] = ["token": token, "plataforma": "ios"]
    let waiting = pendingTokenResults
    pendingTokenResults.removeAll()
    waiting.forEach { $0(payload) }
    pushChannel?.invokeMethod("tokenAtualizado", arguments: payload)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let waiting = pendingTokenResults
    pendingTokenResults.removeAll()
    waiting.forEach { $0(nil) }
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
