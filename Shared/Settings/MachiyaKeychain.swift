import Foundation

/// The Machiya sign-in (Settings → Notes → Sign in to Machiya): the
/// device's token and who it signs in as, in the Keychain under the
/// service "Machiya", never in UserDefaults (`SharedKeychain`'s rules).
/// The Safari extension's handler reads it too (the `machiya` native
/// message); on the Mac its read may be refused, and then it has no token
/// (the rooms answer 401).
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
        SharedKeychain.read(service: service, account: account.rawValue)
    }

    /// Signs in: the token and who it is. False when the Keychain refused.
    @discardableResult
    static func save(token: String, principal: String) -> Bool {
        guard SharedKeychain.save(token, service: service, account: Account.token.rawValue) else { return false }
        return SharedKeychain.save(principal, service: service, account: Account.principal.rawValue)
    }

    /// Signs out: both items deleted.
    @discardableResult
    static func signOut() -> Bool {
        let a = SharedKeychain.save("", service: service, account: Account.token.rawValue)
        let b = SharedKeychain.save("", service: service, account: Account.principal.rawValue)
        return a && b
    }
}
