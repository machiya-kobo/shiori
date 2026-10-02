import Foundation
import Security

/// The AI engines' keys (Settings → AI), in the Keychain. One service,
/// one account per provider. On iOS `AfterFirstUnlockThisDeviceOnly`:
/// encrypted at rest, never in a backup, never off this device. On the
/// Mac, the login keychain (see `base`). Never synced.
///
/// In the app's own access group: only the app uses them (the Safari
/// handler never runs a model; the web summaries have their own key on
/// the server). Every query names service AND account: an unscoped
/// delete can reach another item.
nonisolated enum AIKeychain {
    enum Account: String {
        case anthropic = "anthropicAPIKey"
        case openAI = "openAIAPIKey"
        /// Optional: stock Ollama takes none.
        case local = "localServerToken"
    }

    /// "<app id>.ai", derived from the app's bundle ID (`ShioriID.app`),
    /// so keys saved by an earlier build of the same app are still found.
    static let service = ShioriID.app + ".ai"

    static func read(_ account: Account) -> String {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saves a key, or deletes it when empty. Update-then-add, never
    /// delete-then-add (which races and drops the item's attributes).
    @discardableResult
    static func save(_ raw: String, for account: Account) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = base(account)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        var attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        #if os(iOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func has(_ account: Account) -> Bool { !read(account).isEmpty }

    /// On the Mac, the login keychain: the data-protection keychain needs
    /// an application-identifier entitlement, which the free team's Mac
    /// build doesn't carry. Without it, a write reports "missing
    /// entitlement" but a read just says "not found", so a key saved
    /// through a fallback was never read back ("No Anthropic API key"
    /// right after pasting one). The login keychain is this Mac's
    /// alone, and only this app (its creator) can read the item.
    private static func base(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }
}
