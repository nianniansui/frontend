import Flutter
import UIKit
import WidgetKit
import os.log

@main
@objc class AppDelegate: FlutterAppDelegate {
  // App Group + 共享队列 key，必须与 ShareExtension 保持一致
  private static let appGroupId = "group.com.xiaosui.xiaosui"
  private static let pendingKey = "pendingShares"
  private static let shareChannelName = "com.xiaosui.xiaosui/share"
  private static let deepLinkChannelName = "com.xiaosui.xiaosui/deeplink"
  private static let widgetChannelName = "com.xiaosui.xiaosui/widget"
  private static let log = OSLog(subsystem: "com.xiaosui.xiaosui", category: "share")

  private var shareChannel: FlutterMethodChannel?
  private var deepLinkChannel: FlutterMethodChannel?
  private var widgetChannel: FlutterMethodChannel?

  /// Widget / 通知 / URL scheme 冷启动时携带的初始 deep link，
  /// 等 Flutter 端 ready 之后（调用 initialLink）一次性消费。
  private var pendingInitialDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      // share channel
      let share = FlutterMethodChannel(
        name: AppDelegate.shareChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      share.setMethodCallHandler { [weak self] call, result in
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
      shareChannel = share

      // deep link channel
      let deep = FlutterMethodChannel(
        name: AppDelegate.deepLinkChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      deep.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "initialLink":
          // Flutter 启动后查询是否有冷启动 deep link，消费一次
          let v = self.pendingInitialDeepLink
          self.pendingInitialDeepLink = nil
          result(v)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      deepLinkChannel = deep

      // widget channel：Flutter 把"最近一条摘要"写入 App Group，触发 widget 刷新
      let widget = FlutterMethodChannel(
        name: AppDelegate.widgetChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      widget.setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "updateLatestSummary":
          guard let args = call.arguments as? [String: Any],
                let text = args["text"] as? String else {
            result(FlutterError(code: "invalid_args", message: "missing text", details: nil))
            return
          }
          let kind = args["kind"] as? String ?? "XiaosuiWidget"
          self.writeLatestSummary(text)
          // 通知 WidgetCenter 刷新对应 kind
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
          }
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      widgetChannel = widget
      os_log("share + deeplink + widget channels registered", log: AppDelegate.log, type: .info)
    } else {
      os_log("rootViewController is not FlutterViewController", log: AppDelegate.log, type: .error)
    }

    // 解析 launch options 里的 URL（widget tap 冷启动时会带过来）
    if let url = launchOptions?[.url] as? URL,
       url.scheme == "xiaosui" {
      pendingInitialDeepLink = url.host  // xiaosui://record → "record"
      os_log("cold launch via deep link: %{public}@", log: AppDelegate.log, type: .info, url.absoluteString)
    }

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
      // 1) shared 路径：share extension 唤起主 App
      DispatchQueue.main.async { [weak self] in
        self?.shareChannel?.invokeMethod("sharesAvailable", arguments: nil)
      }
      // 2) 其它 host（比如 record）通过 deep link channel 直推 Flutter
      if let host = url.host, host != "shared" {
        DispatchQueue.main.async { [weak self] in
          self?.deepLinkChannel?.invokeMethod("openRecord", arguments: nil)
        }
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }

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

  private func peekPendingShares() -> [String] {
    guard let defaults = UserDefaults(suiteName: AppDelegate.appGroupId) else {
      return []
    }
    return defaults.array(forKey: AppDelegate.pendingKey) as? [String] ?? []
  }

  private func writeLatestSummary(_ text: String) {
    guard let defaults = UserDefaults(suiteName: AppDelegate.appGroupId) else {
      os_log("widget update: App Group missing", log: AppDelegate.log, type: .error)
      return
    }
    defaults.set(text, forKey: "latestSummary")
    defaults.set(Date().timeIntervalSince1970, forKey: "latestSummaryAt")
    defaults.synchronize()
  }
}
