import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // App Group + 共享队列 key，必须与 ShareExtension 保持一致
  private static let appGroupId = "group.com.xiaosui.xiaosui"
  private static let pendingKey = "pendingShares"
  private static let channelName = "com.xiaosui.xiaosui/share"

  private var shareChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: AppDelegate.channelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "fetchPending":
          result(self.drainPendingShares())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      shareChannel = channel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // ShareExtension 完成后会尝试通过 xiaosui:// scheme 唤起主应用，
    // 这里通知 Flutter 侧立刻去取队列。
    if url.scheme == "xiaosui" {
      shareChannel?.invokeMethod("sharesAvailable", arguments: nil)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// 取出 App Group UserDefaults 里累积的待处理分享，并清空。
  private func drainPendingShares() -> [String] {
    guard let defaults = UserDefaults(suiteName: AppDelegate.appGroupId) else {
      return []
    }
    let queue = defaults.array(forKey: AppDelegate.pendingKey) as? [String] ?? []
    if !queue.isEmpty {
      defaults.removeObject(forKey: AppDelegate.pendingKey)
    }
    return queue
  }
}
