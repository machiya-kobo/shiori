import Foundation

/// The preferences that follow the person (machiya docs/contracts/prefs.md):
/// the account's keys for Shiori's settings, and the client rules for one
/// contact with the account. search-core's `S.prefsSync`, `S.accountValues`
/// and `S.localValues` are the twins; scripts/prefs-sync-cases.json holds
/// the cases both run.
enum PrefsSync {
    /// The account's shared keys Shiori keeps, with the values the schema allows.
    static let shared: [String: [String]] = [
        "theme": ["system", "day", "night"],
        "palette": SharedSettings.palettes,
        "text_size": ["xsmall", "small", "standard", "large", "xlarge"],
    ]
    static let defaults: [String: String] = ["theme": "system", "palette": "tokyo-night", "text_size": "standard", "pills": ""]

    /// Shiori's own settings that follow the person, as `shiori.<snake_case>`:
    /// the results' options. Never an address, an AI setting (AI Answer
    /// included) or this device's own (the preview pane, the search mode).
    static var flags: [String] {
        SharedSettings.flagKeys.filter { !["semanticSearch", "previewPane", "aiAnswer"].contains($0) }
    }
    static let counts = [SharedSettings.Key.histerCount, SharedSettings.Key.vaultCount]
    static let choices: [String: [String]] = [
        SharedSettings.Key.resultStyle: SharedSettings.resultStyles,
        SharedSettings.Key.smallWebOpen: SharedSettings.smallWebOpens,
    ]

    /// Shiori's local setting → its account key, for every one that follows the person.
    static var shioriKeys: [String: String] {
        var out: [String: String] = [:]
        for local in flags + counts + Array(choices.keys) { out[local] = "shiori." + snake(local) }
        return out
    }

    static func snake(_ key: String) -> String {
        key.reduce(into: "") { out, c in out += c.isUppercase ? "_" + c.lowercased() : String(c) }
    }

    // MARK: Text size (the house's five steps, HOUSE_STEPS.apple)

    static let toHouse: [String: String] = [
        "xSmall": "xsmall", "small": "small", "medium": "small", "system": "standard", "large": "standard",
        "xLarge": "large", "xxLarge": "xlarge", "xxxLarge": "xlarge",
    ]
    static let toSize: [String: String] = [
        "xsmall": "xSmall", "small": "small", "standard": "system", "large": "xLarge", "xlarge": "xxLarge",
    ]

    // MARK: Pills ({"order": […], "hidden": […]}, compact)

    static func pillsToAccount(_ pills: [String]) -> String {
        let clean = PillOrder.clean(pills)
        guard !clean.isEmpty else { return "" }
        let order = clean.map { $0.hasPrefix("-") ? String($0.dropFirst()) : $0 }
        let hidden = clean.filter { $0.hasPrefix("-") }.map { String($0.dropFirst()) }
        func list(_ items: [String]) -> String { "[" + items.map { "\"\($0)\"" }.joined(separator: ",") + "]" }
        return "{\"order\":\(list(order)),\"hidden\":\(list(hidden))}"
    }

    static func pillsFromAccount(_ value: String) -> [String]? {
        if value.isEmpty { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
              let order = object["order"] as? [String], let hidden = object["hidden"] as? [String]
        else { return nil }
        let out = PillOrder.clean(order.map { hidden.contains($0) ? "-" + $0 : $0 })
        return out.isEmpty && !order.isEmpty ? nil : out
    }

    // MARK: Values

    /// Whether the account may hold this value for this key and Shiori may
    /// apply it (the contract's rule 5).
    static func valid(_ key: String, _ value: String) -> Bool {
        if let allowed = shared[key] { return allowed.contains(value) }
        if key == "pills" { return pillsFromAccount(value) != nil }
        guard let local = shioriKeys.first(where: { $0.value == key })?.key else { return false }
        if flags.contains(local) { return value == "on" || value == "off" }
        if counts.contains(local) { return Int(value).map { SharedSettings.pageCounts.contains($0) && String($0) == value } ?? false }
        return choices[local]?.contains(value) ?? false
    }

    /// This device's settings (the App Group's, `extensionPayload`'s keys) in
    /// the account's words.
    static func accountValues(_ settings: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        if let theme = settings[SharedSettings.Key.theme] as? String, shared["theme"]!.contains(theme) { out["theme"] = theme }
        if let palette = settings[SharedSettings.Key.palette] as? String, shared["palette"]!.contains(palette) { out["palette"] = palette }
        if let size = settings[SharedSettings.Key.textSize] as? String, let house = toHouse[size] { out["text_size"] = house }
        if let pills = settings[SharedSettings.Key.pills] as? [String] { out["pills"] = pillsToAccount(pills) }
        for (local, key) in shioriKeys {
            if flags.contains(local), let v = settings[local] as? Bool { out[key] = v ? "on" : "off" }
            else if counts.contains(local), let v = settings[local] as? Int, SharedSettings.pageCounts.contains(v) { out[key] = String(v) }
            else if let allowed = choices[local], let v = settings[local] as? String, allowed.contains(v) { out[key] = v }
        }
        return out
    }

    /// The account's values as this device's settings, valid ones only;
    /// NSNull removes (back to the default). `mine` is this device's text
    /// size: an account size that's just its house rounding keeps it.
    static func localValues(_ prefs: [String: String?], mine: String = "") -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in prefs {
            guard let value else {
                switch key {
                case "theme": out[SharedSettings.Key.theme] = "system"
                case "palette": out[SharedSettings.Key.palette] = "tokyo-night"
                case "text_size": out[SharedSettings.Key.textSize] = "system"
                case "pills": out[SharedSettings.Key.pills] = [String]()
                default: if let local = shioriKeys.first(where: { $0.value == key })?.key { out[local] = NSNull() }
                }
                continue
            }
            guard valid(key, value) else { continue }
            switch key {
            case "theme": out[SharedSettings.Key.theme] = value
            case "palette": out[SharedSettings.Key.palette] = value
            case "text_size": if toHouse[mine] != value, let size = toSize[value] { out[SharedSettings.Key.textSize] = size }
            case "pills": out[SharedSettings.Key.pills] = pillsFromAccount(value)
            default:
                guard let local = shioriKeys.first(where: { $0.value == key })?.key else { continue }
                if flags.contains(local) { out[local] = value == "on" }
                else if counts.contains(local) { out[local] = Int(value) }
                else { out[local] = value }
            }
        }
        return out
    }

    // MARK: One contact

    /// The account's answer, or what this client saw at its last contact.
    struct Snapshot: Codable, Equatable {
        var rev: Int?
        var prefs: [String: String]
        var updated: [String: Int]
    }

    /// One contact, after any pending change was sent: `mine` is this
    /// client's values now (the account's words), `seen` the answer at its
    /// last contact, `answer` the account's now. `apply`: values to take
    /// here (nil: back to the default); `send`: values to write there.
    static func sync(mine: [String: String], seen: Snapshot?, answer: Snapshot) -> (apply: [String: String?], send: [String: String]) {
        var apply: [String: String?] = [:]
        var send: [String: String] = [:]
        let before = seen?.prefs ?? [:]
        let beforeUpdated = seen?.updated ?? [:]
        let ownKeys = Set(shioriKeys.values)
        let keys = Set(mine.keys).union(answer.prefs.keys).union(before.keys)
        for key in keys where defaults[key] != nil || ownKeys.contains(key) {
            let ours = mine[key]
            if let theirs = answer.prefs[key] {
                guard valid(key, theirs), theirs != ours else { continue }
                let unchanged = seen != nil && before[key] == theirs && beforeUpdated[key] == answer.updated[key]
                if unchanged, let ours { send[key] = ours } else { apply[key] = .some(theirs) }
            } else if seen != nil, before[key] != nil {
                apply[key] = .some(nil)
            } else if let ours, ours != (defaults[key] ?? "") {
                send[key] = ours
            }
        }
        return (apply, send)
    }
}
