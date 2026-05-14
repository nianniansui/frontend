import Flutter
import UIKit
import os.log

@main
@objc class AppDelegate: FlutterAppDelegate {
  // App Group + 共享队列 key，必须与 ShareExtension 保持一致
  private static let appGroupId = "group.com.xiaosui.xiaosui"
  private static let pendingKey = "pendingShares"
  private static let channelName = "com.xiaosui.xiaosui/share"
  private static let log = OSLog(subsystem: "com.xiaosui.xiaosui", category: "share")

  private var shareChannel: FlutterMethodChannel?
  private var pendingNotifyOnReady: Bool = false

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
          let drained = self.drainPendingShares()
          os_log("fetchPending called, returning %{public}d items", log: AppDelegate.log, type: .info, drained.count)
          result(drained)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      shareChannel = channel
      os_log("share channel registered", log: AppDelegate.log, type: .info)
    } else {
      os_log("rootViewController is not FlutterViewController", log: AppDelegate.log, type: .error)
    }

    // 冷启动时如果队列已经有内容（用户先 share 再点开 app），主动通知 Flutter
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onDidBecomeActive(_:)),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func onDidBecomeActive(_ notification: Notification) {
    let queue = peekPendingShares()
    if !queue.isEmpty {
      os_log("becameActive with %{public}d pending shares; notifying Flutter", log: AppDelegate.log, type: .info, queue.count)
      // Flutter 端可能还没启动完成 channel；延迟到下个 runloop 再发，
      // 没接住 sharesAvailable 时 Flutter 自己也会在 didChangeAppLifecycleState=resumed 主动 fetch。
      DispatchQueue.main.async { [weak self] in
        self?.shareChannel?.invokeMethod("sharesAvailable", arguments: nil)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    os_log("open url: %{public}@", log: AppDelegate.log, type: .info, url.absoluteString)
    if url.scheme == "xiaosui" {
      // resume 路径会处理；这里再发一次保证 race 情况下不丢
      DispatchQueue.main.async { [weak self] in
        self?.shareChannel?.invokeMethod("sharesAvailable", arguments: nil)
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// 取出 App Group UserDefaults 里累积的待处理分享，并清空。
  private func drainPendingShares() -> [String] {
    guard let defaults = UserDefaults(suiteName: AppDelegate.appGroupId) else {
      os_log("UserDefaults(suiteName:) returned nil — App Group entitlement missing?", log: AppDelegate.log, type: .error)
      return []
    }
    let queue = defaults.array(forKey: AppDelegate.pendingKey) as? [String] ?? []
    if !queue.isEmpty {
      defaults.removeObject(forKey: AppDelegate.pendingKey)
      defaults.synchronize()
    }
    return queue
  }

  /// 不消费，只看队列大小（用于决定要不要通知 Flutter）
  private func peekPendingShares() -> [String] {
    guard let defaults = UserDefaults(suiteName: AppDelegate.appGroupId) else {
      return []
    }
    return defaults.array(forKey: AppDelegate.pendingKey) as? [String] ?? []
  }
}
