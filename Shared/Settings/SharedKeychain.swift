import Foundation
import Security

/// The Keychain items the app and its extensions share: the Machiya
/// sign-in (`MachiyaKeychain`) and Hister's token (`HisterKeychain`).
/// AIKeychain's rules: every query names service AND account;
/// update-then-add; on iOS `AfterFirstUnlockThisDeviceOnly` (never in a
/// backup, never off this device); never synced. Values are never logged.
///
/// In Shared/ because the Safari extension's handler reads them too. On iOS
/// the items are in the App Group's access group, which the app and its
/// extensions share. On the Mac they are in the login keychain (the
/// data-protection keychain needs an entitlement a free team's build
/// lacks, see AIKeychain), whose items belong to the app that made them:
/// an extension's read may be refused there, and then it has none.
nonisolated enum SharedKeychain {
    /// The value, or "" when there is none (or it can't be read).
    static func read(service: String, account: String) -> String {
        var query = base(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saves a value, or deletes it when empty. False when the Keychain refused.
    @discardableResult
    static func save(_ raw: String, service: String, account: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = base(service: service, account: account)
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

    private static func base(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(iOS)
        // Shared with the extensions through the App Group.
        query[kSecAttrAccessGroup as String] = SharedSettings.appGroup
        #endif
        return query
    }
}

/// Hister's access token (Settings → Server → Access Token): the owner's
/// one token per user, entered once per device, in the Keychain under the
/// service "Hister". Sent as `X-Access-Token` by the app, the share
/// extension and (through the `hister` native message) Safari's extension.
/// Empty: nothing is sent.
nonisolated enum HisterKeychain {
    static let service = "Hister"
    static let account = "token"

    /// The token, or "" when there's none.
    static var token: String { SharedKeychain.read(service: service, account: account) }

    /// Keeps a token, or removes it when empty. False when the Keychain refused.
    @discardableResult
    static func save(_ token: String) -> Bool {
        SharedKeychain.save(token, service: service, account: account)
    }
}
