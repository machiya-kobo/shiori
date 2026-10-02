import Foundation

/// The log subsystem: the app's bundle identifier, also when this runs
/// inside one of its extensions ("<prefix>.shiori.Share" → "<prefix>.shiori"),
/// so a build with its own bundle prefix logs under its own name. The
/// app target's `ShioriID` is the same rule.
let logSubsystem: String = {
    let bundle = Bundle.main
    guard let id = bundle.bundleIdentifier, !id.isEmpty else { return "shiori" }
    guard bundle.bundleURL.pathExtension == "appex", let dot = id.lastIndex(of: ".") else { return id }
    return String(id[..<dot])
}()
