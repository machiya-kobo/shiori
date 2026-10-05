import Foundation
import Testing

/// PrefsSync on the cases search-core's S.prefsSync runs too
/// (scripts/prefs-sync-cases.json), and against the contract's schema
/// (scripts/prefs.schema.json, a copy of machiya's).
struct PrefsSyncTests {
    static let scripts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts")

    static func json(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: scripts.appending(path: name))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func snapshot(_ any: Any?) -> PrefsSync.Snapshot? {
        guard let object = any as? [String: Any] else { return nil }
        return PrefsSync.Snapshot(
            rev: object["rev"] as? Int,
            prefs: object["prefs"] as? [String: String] ?? [:],
            updated: (object["updated"] as? [String: Int]) ?? [:])
    }

    @Test func theSharedSyncCases() throws {
        let cases = try #require(try Self.json("prefs-sync-cases.json")["sync"] as? [[String: Any]])
        #expect(cases.count >= 8)
        for c in cases {
            let name = c["name"] as? String ?? ""
            let result = PrefsSync.sync(
                mine: c["mine"] as? [String: String] ?? [:], seen: Self.snapshot(c["seen"]),
                answer: try #require(Self.snapshot(c["answer"])))
            let wantApply = (c["apply"] as? [String: Any] ?? [:]).mapValues { $0 as? String }
            #expect(result.apply == wantApply, "\(name)")
            #expect(result.send == (c["send"] as? [String: String] ?? [:]), "\(name)")
        }
    }

    @Test func theSharedMappingCases() throws {
        let all = try Self.json("prefs-sync-cases.json")
        for c in try #require(all["textSize"] as? [[String: String]]) where c["steps"] == "apple" {
            #expect(PrefsSync.toHouse[c["local"]!] == c["house"], "\(c)")
        }
        for c in try #require(all["textSizeBack"] as? [[String: String]]) where c["steps"] == "apple" {
            #expect(PrefsSync.toSize[c["house"]!] == c["local"], "\(c)")
        }
        for c in try #require(all["pills"] as? [[String: Any]]) {
            let local = c["local"] as? [String] ?? []
            let account = c["account"] as? String ?? ""
            #expect(PrefsSync.pillsToAccount(local) == account)
            #expect(PrefsSync.pillsFromAccount(account) == local)
        }
        for c in try #require(all["valid"] as? [[String: Any]]) {
            let key = c["key"] as! String, value = c["value"] as! String
            #expect(PrefsSync.valid(key, value) == (c["ok"] as! Bool), "\(key)=\(value)")
        }
    }

    @Test func shiorisKeysAreTheContracts() throws {
        let schema = try Self.json("prefs.schema.json")
        let shared = try #require(schema["shared"] as? [String: [String: Any]])
        for (key, spec) in shared {
            if let values = spec["values"] as? [String] { #expect(PrefsSync.shared[key] == values, "\(key)") }
            if let ours = PrefsSync.defaults[key] { #expect(ours == spec["default"] as? String, "\(key)") }
        }
        let pattern = try #require(schema["app_key"] as? String).replacingOccurrences(of: "\\Z", with: "$")
        let appKey = try Regex("^" + pattern)
        for key in PrefsSync.shioriKeys.values {
            #expect(key.wholeMatch(of: appKey) != nil || key.firstMatch(of: appKey) != nil, "\(key)")
            #expect(key.range(of: "url|token|obsidian|ai_|server|address", options: .regularExpression) == nil, "\(key)")
        }
        // What this device sends from its settings is always something the account takes.
        let sample: [String: Any] = [
            "theme": "night", "palette": "nord", "textSize": "xLarge", "pills": ["all", "-web"],
            "showInfobox": false, "histerCount": 10, "resultStyle": "bar", "smallWebOpen": "direct",
        ]
        for (key, value) in PrefsSync.accountValues(sample) { #expect(PrefsSync.valid(key, value), "\(key)=\(value)") }
    }

    @Test func theAccountsValuesComeBackAsSettings() {
        let local = PrefsSync.localValues(["theme": "night", "shiori.show_infobox": "off", "shiori.hister_count": "10", "palette": nil])
        #expect(local["theme"] as? String == "night")
        #expect(local["showInfobox"] as? Bool == false)
        #expect(local["histerCount"] as? Int == 10)
        #expect(local["palette"] as? String == "tokyo-night")
        // An account size that's just this device's rounding keeps its own.
        #expect(PrefsSync.localValues(["text_size": "small"], mine: "medium")["textSize"] == nil)
    }
}
