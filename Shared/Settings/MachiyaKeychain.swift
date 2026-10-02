import Foundation
import Security

/// The Machiya sign-in (Settings → Notes → Sign in to Machiya): the
/// device's token and who it signs in as, in the Keychain under the
/// service "Machiya", never in UserDefaults. AIKeychain's rules: every
/// query names service AND account; update-then-add; on iOS
/// `AfterFirstUnlockThisDeviceOnly` (never in a backup, never off this
/// device); never synced.
///
/// In Shared/ because the Safari extension's handler reads it too (the
/// `machiya` native message). On iOS the item is in the App Group's
/// access group, which the app and its extensions share. On the Mac it is
/// in the login keychain (the data-protection keychain needs an
/// entitlement a free team's build lacks, see AIKeychain), whose item
/// belongs to the app that made it: the extension's read may be refused
/// there, and then it has no token (the rooms answer 401).
nonisolated enum MachiyaKeychain {
    static let service = "Machiya"

    enum Account: String {
        case token
        /// The principal's name from pairing ("" for a pasted token).
        case principal
    }

    /// The token, or "" when signed out.
    static var token: String { read(.token) }
    static var principal: String { read(.principal) }

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

    /// Signs in: the token and who it is. False when the Keychain refused.
    @discardableResult
    static func save(token: String, principal: String) -> Bool {
        guard save(token, for: .token) else { return false }
        return save(principal, for: .principal)
    }

    /// Signs out: both items deleted.
    @discardableResult
    static func signOut() -> Bool {
        let a = save("", for: .token)
        let b = save("", for: .principal)
        return a && b
    }

    /// Saves a value, or deletes it when empty.
    @discardableResult
    private static func save(_ raw: String, for account: Account) -> Bool {
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

    private static func base(_ account: Account) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        #if os(iOS)
        // Shared with the Safari extension through the App Group.
        query[kSecAttrAccessGroup as String] = SharedSettings.appGroup
        #endif
        return query
    }
}
