import SafariServices

/// The native half of the web extension, talking to the app through the
/// shared App Group: it answers with the app's combined-search settings,
/// records how many captures the offline queue holds, and adds searches
/// made from Safari to the recent searches. Page data never crosses into
/// native code.
///
/// `nonisolated`: the project defaults to MainActor, and Safari creates
/// and calls this class off the main thread. A MainActor-isolated handler
/// trips Swift's isolation check and the extension process dies on every
/// native message (EXC_BREAKPOINT in dispatch_assert_queue).
nonisolated final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        var reply: [String: Any] = [:]
        switch message?["type"] as? String {
        case "settings":
            reply = SharedSettings.extensionPayload()
        case "queue":
            // The offline queue's size, for the app's Settings.
            var report: [String: Any] = [
                "count": message?["count"] as? Int ?? 0,
                "reportedAt": Date().timeIntervalSince1970,
            ]
            if let oldest = message?["oldest"] as? Double { report["oldest"] = oldest }
            SharedSettings.defaults?.set(report, forKey: SharedSettings.Key.extensionQueue)
        case "set-settings":
            if let values = message?["values"] as? [String: Any] {
                SharedSettings.applyFromPage(values)
                reply = SharedSettings.extensionPayload()
            }
        case "recent":
            if let query = message?["q"] as? String { SharedSettings.recordSearch(query) }
        default:
            break
        }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
