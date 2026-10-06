import SafariServices

/// The native half of the web extension, talking to the app through the
/// shared App Group: it answers with the app's combined-search settings,
/// records how many captures the offline queue holds, adds searches
/// made from Safari to the recent searches, and hands the extension the
/// Machiya sign-in and Hister's token from the Keychain (`machiya`,
/// `hister`). Page data never crosses
/// into native code.
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
        case "machiya":
            // The Machiya sign-in (Settings → Account), for Kura and Konbini:
            // the background applies the host rule and never stores it.
            // Signing in and out happens only in the app. Signed in to
            // Hister, the app's own id (mhs_…, the helper's) goes to the
            // rooms, as the apps send it: never Hister's token.
            let sessionID = HisterKeychain.sessionID
            let token = MachiyaKeychain.token
            if sessionID.hasPrefix("mhs_") {
                reply = ["token": sessionID, "principal": HisterKeychain.username]
            } else if !token.isEmpty {
                reply = ["token": token, "principal": MachiyaKeychain.principal]
            }
        case "hister":
            // Hister's token (Settings → Account), sent as X-Access-Token;
            // set and removed only in the app (which checked it; the
            // background checks it again). None: an empty reply.
            let token = HisterKeychain.token
            if !token.isEmpty {
                reply = ["token": token]
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
