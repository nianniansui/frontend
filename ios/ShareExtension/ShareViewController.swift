import UIKit
import Social
import UniformTypeIdentifiers
import os.log

/// 小碎 Share Extension
///
/// 用户从 Safari / 微信 / 备忘录等任意地方点击分享 → 选小碎，
/// 我们把文字（或 URL、或选中的网页标题）追加写入 App Group 的
/// UserDefaults 队列。主应用启动或回到前台时再调用 /add_memory_text。
///
/// 为什么不直接在扩展里调后端？
/// - 扩展内存极紧（通常 16–24MB），长时间网络请求会被杀。
/// - 用户分享是瞬时操作，不能阻塞 UI。
/// - 队列化后主应用能做错误重试、显示状态。
final class ShareViewController: SLComposeServiceViewController {

    // MARK: - 必须与 Runner target 的 App Group 保持一致
    private static let appGroupId = "group.com.xiaosui.xiaosui"
    private static let pendingKey = "pendingShares"
    // 主应用 URL scheme，用于分享结束后尝试拉起主 App 触发处理
    private static let hostScheme = "xiaosui"
    private static let log = OSLog(subsystem: "com.xiaosui.xiaosui.ShareExtension", category: "share")

    override func isContentValid() -> Bool {
        let text = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty
    }

    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        prefillFromAttachmentsIfNeeded()
    }

    override func didSelectPost() {
        let userTyped = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        enqueueAndFinish(withFallback: userTyped)
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    // MARK: - 预填：从 NSExtensionItem 里抽取纯文本 / URL / 标题

    private func prefillFromAttachmentsIfNeeded() {
        guard (contentText ?? "").isEmpty else { return }
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else { return }

        extractText(from: item) { [weak self] extracted in
            guard let self, let text = extracted, !text.isEmpty else { return }
            DispatchQueue.main.async {
                self.textView.text = text
                self.validateContent()
            }
        }
    }

    private func extractText(from item: NSExtensionItem, completion: @escaping (String?) -> Void) {
        if let attributed = item.attributedContentText?.string,
           !attributed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(attributed)
            return
        }

        guard let attachments = item.attachments, !attachments.isEmpty else {
            completion(nil)
            return
        }

        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                if let s = value as? String { completion(s); return }
                completion(nil)
            }
            return
        }

        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                if let url = value as? URL { completion(url.absoluteString); return }
                if let s = value as? String { completion(s); return }
                completion(nil)
            }
            return
        }

        completion(nil)
    }

    // MARK: - 写入 App Group 队列 + 关闭扩展

    private func enqueueAndFinish(withFallback fallback: String) {
        let text = fallback.isEmpty ? (contentText ?? "") : fallback
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        if let defaults = UserDefaults(suiteName: Self.appGroupId) {
            var queue = defaults.array(forKey: Self.pendingKey) as? [String] ?? []
            queue.append(trimmed)
            defaults.set(queue, forKey: Self.pendingKey)
            defaults.synchronize()
            os_log("appended share, queue size now %{public}d", log: Self.log, type: .info, queue.count)
        } else {
            os_log("UserDefaults(suiteName:) returned nil — App Group entitlement on extension missing?", log: Self.log, type: .error)
        }

        openHostAppIfPossible()
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func openHostAppIfPossible() {
        guard let url = URL(string: "\(Self.hostScheme)://shared") else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(url, options: [:], completionHandler: { ok in
                    os_log("open(host scheme) result=%{public}@", log: Self.log, type: .info, ok ? "true" : "false")
                })
                return
            }
            responder = current.next
        }
        os_log("could not find UIApplication via responder chain", log: Self.log, type: .error)
    }
}

