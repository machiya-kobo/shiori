import Foundation

/// The app's own bundle identifier, from whichever bundle is running: the
/// app's, or the app's from inside one of its extensions
/// ("<prefix>.shiori.Share" → "<prefix>.shiori"). Everything named after
/// the app (the extension's ID, the keychain service, the log subsystem)
/// derives from it, so a build with another `SHIORI_BUNDLE_PREFIX`
/// (local.yml) is consistent, and an existing install keeps its IDs.
nonisolated enum ShioriID {
    static let app: String = appID(of: Bundle.main)

    static func appID(of bundle: Bundle) -> String {
        guard let id = bundle.bundleIdentifier, !id.isEmpty else { return "shiori" }
        guard bundle.bundleURL.pathExtension == "appex", let dot = id.lastIndex(of: ".") else { return id }
        return String(id[..<dot])
    }
}
