import Foundation

/// Lists a build sets for its user's own conventions (local.yml → the
/// app's Info.plist) or, for the command-line tool, the environment:
/// comma-separated names, empty when unset. A public build has none.
public enum BuildDefaults {
    public static func list(plistKey: String, environment: String) -> [String] {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String
        let raw = fromPlist.flatMap { $0.hasPrefix("$(") ? nil : $0 } ?? ProcessInfo.processInfo.environment[environment] ?? ""
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
