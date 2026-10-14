import Foundation
import HisterKit
import Security

/// The media services' tokens (Settings → Search → Media; docs/media.md), in
/// the Keychain: one service, one account per media service. AIKeychain's
/// rules: on iOS `AfterFirstUnlockThisDeviceOnly` (never in a backup, never
/// off this device), on the Mac the login keychain; never synced, never
/// logged, never in a URL. Only the app uses them: Safari's extension has
/// no Media.
nonisolated enum MediaKeychain {
    /// "<app id>.media", derived from the app's bundle ID (`ShioriID.app`).
    static let service = ShioriID.app + ".media"

    static func read(_ media: MediaService) -> String {
        var query = base(media)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saves a token, or deletes it when empty. Update-then-add.
    @discardableResult
    static func save(_ raw: String, for media: MediaService) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = base(media)
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

    /// The app's own items: on the Mac the login keychain, as AIKeychain's (the data-protection keychain needs an
    /// entitlement a free team's build lacks).
    private static func base(_ media: MediaService) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: media.rawValue,
        ]
    }
}
