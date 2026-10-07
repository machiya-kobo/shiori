import Foundation
import Testing

/// AccountPrefs against a fake account (the contract's /machiya/api/prefs:
/// rev, updated, ETag/304, PUT merging): what a device sends, takes and
/// keeps for later.
@Suite(.serialized)
struct AccountPrefsTests {
    static let host = "prefs.example"
    let base = URL(string: "https://\(Self.host)/")!

    /// The account: its values, their times, its revision; `status` forces an answer.
    nonisolated final class Account: @unchecked Sendable {
        var prefs: [String: String] = [:]
        var updated: [String: Int] = [:]
        var rev = 1
        var clock = 1000
        var status: Int?
        var puts: [[String: Any]] = []

        func answer() -> Data {
            (try? JSONSerialization.data(withJSONObject: ["v": 1, "rev": rev, "prefs": prefs, "updated": updated])) ?? Data()
        }

        func handle(_ request: URLRequest) -> (Int, Data) {
            if let status { return (status, Data(#"{"error":"x"}"#.utf8)) }
            if request.httpMethod == "PUT" {
                // A body that isn't the contract's fails the test, not the run.
                guard let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any],
                      let values = body["prefs"] as? [String: Any]
                else {
                    Issue.record("a PUT without a prefs object")
                    return (400, Data())
                }
                puts.append(values)
                var changed = false
                for (key, value) in values {
                    clock += 1
                    if let value = value as? String {
                        if prefs[key] != value { prefs[key] = value; updated[key] = clock; changed = true }
                    } else if prefs[key] != nil {
                        prefs[key] = nil; updated[key] = nil; changed = true
                    }
                }
                if changed { rev += 1 }
                return (200, answer())
            }
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"\(rev)\"" { return (304, Data()) }
            return (200, answer())
        }
    }

    let account = Account()
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "prefs-test-\(UUID().uuidString)")!
        StubProtocol.reset(Self.host)
        let account = account
        StubProtocol.handle(Self.host) { account.handle($0) }
    }

    func contact(_ credential: AccountPrefs.Credential = .session("mhs_" + String(repeating: "a", count: 43))) async -> AccountPrefs.State {
        await AccountPrefs.contact(base: base, credential: credential, defaults: defaults, session: StubProtocol.session())
    }

    @Test func aFirstContactTakesTheAccountsValuesAndFillsItsBlanks() async {
        account.prefs = ["theme": "night", "palette": "nord"]
        account.updated = ["theme": 10, "palette": 10]
        defaults.set("day", forKey: "theme")
        defaults.set("xLarge", forKey: "textSize")
        defaults.set(false, forKey: "showInfobox")
        #expect(await contact() == .synced)
        // The account's wins; this device's own fill the account's blanks.
        #expect(defaults.string(forKey: "theme") == "night")
        #expect(defaults.string(forKey: "palette") == "nord")
        #expect(account.prefs["text_size"] == "large")
        #expect(account.prefs["shiori.show_infobox"] == "off")
        #expect(account.prefs["theme"] == "night")
    }

    @Test func aChangeHereGoesAndOnlyItGoes() async {
        account.prefs = ["theme": "night", "palette": "nord"]
        account.updated = ["theme": 10, "palette": 10]
        _ = await contact()
        account.puts = []
        defaults.set("day", forKey: "theme")
        #expect(await contact() == .synced)
        #expect(account.puts.count == 1)
        #expect(account.puts.first?.keys.sorted() == ["theme"])
        #expect(account.prefs["theme"] == "day")
        #expect(account.prefs["palette"] == "nord")
    }

    @Test func nothingChangedAsksWithItsRevisionAndSendsNothing() async {
        account.prefs = ["theme": "night"]
        account.updated = ["theme": 10]
        _ = await contact()
        account.puts = []
        #expect(await contact() == .synced)
        #expect(account.puts.isEmpty)
        let asked = StubProtocol.requests(Self.host).last
        #expect(asked?.value(forHTTPHeaderField: "If-None-Match") == "\"\(account.rev)\"")
    }

    @Test func aChangeMadeElsewhereComesHere() async {
        account.prefs = ["theme": "night"]
        account.updated = ["theme": 10]
        _ = await contact()
        account.prefs["theme"] = "day"
        account.updated["theme"] = 20
        account.rev += 1
        _ = await contact()
        #expect(defaults.string(forKey: "theme") == "day")
    }

    @Test func aChangeThatCantGoWaitsAndGoesFirstNextTime() async {
        account.prefs = ["theme": "night"]
        account.updated = ["theme": 10]
        _ = await contact()
        defaults.set("day", forKey: "theme")
        account.status = 503
        #expect(await contact() == .unavailable)
        #expect(account.prefs["theme"] == "night")
        account.status = nil
        #expect(await contact() == .synced)
        #expect(account.prefs["theme"] == "day")
    }

    @Test func signedOutSaysSoAndChangesNothing() async {
        account.status = 401
        defaults.set("day", forKey: "theme")
        #expect(await contact(.token("ABCDEFGHJKLMNPQRSTUVWXYZ23")) == .signInNeeded)
        #expect(defaults.string(forKey: "theme") == "day")
    }

    @Test func theCredentialIsTheAppsIdOrHistersToken() {
        let id = AccountPrefs.request(base: base, credential: .session("mhs_x"), method: "GET")
        #expect(id.value(forHTTPHeaderField: "Authorization") == "Bearer mhs_x")
        #expect(id.url?.absoluteString == "https://prefs.example/machiya/api/prefs")
        let token = AccountPrefs.request(base: base, credential: .token("tok"), method: "GET")
        #expect(token.value(forHTTPHeaderField: "X-Access-Token") == "tok")
        #expect(token.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// Against a real helper (read and write), only when PREFS_LIVE_URL (Hister's
    /// host) and PREFS_LIVE_TOKEN_FILE (a dev Hister token) are set: never the
    /// owner's own. Cleans up the keys it wrote.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PREFS_LIVE_URL"] != nil))
    func theLiveHelperTakesAndGives() async throws {
        let env = ProcessInfo.processInfo.environment
        let base = try #require(URL(string: env["PREFS_LIVE_URL"]!))
        let token = try String(contentsOfFile: try #require(env["PREFS_LIVE_TOKEN_FILE"]), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let live = UserDefaults(suiteName: "prefs-live-\(UUID().uuidString)")!
        live.set("night", forKey: "theme")
        live.set(false, forKey: "showRelated")
        // First contact: the account's blanks filled with this device's values.
        #expect(await AccountPrefs.contact(base: base, credential: .token(token), defaults: live) == .synced)
        // A change here goes; an unchanged second contact is a 304.
        live.set("day", forKey: "theme")
        #expect(await AccountPrefs.contact(base: base, credential: .token(token), defaults: live) == .synced)
        #expect(await AccountPrefs.contact(base: base, credential: .token(token), defaults: live) == .synced)
        let seen = try #require(live.data(forKey: AccountPrefs.seenKey))
        let snapshot = try JSONDecoder().decode(PrefsSync.Snapshot.self, from: seen)
        #expect(snapshot.prefs["theme"] == "day")
        #expect(snapshot.prefs["shiori.show_related"] == "off")
        // Clean up: every key this test may have written goes.
        var request = AccountPrefs.request(base: base, credential: .token(token), method: "PUT")
        let keys = Array(snapshot.prefs.keys)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prefs": Dictionary(uniqueKeysWithValues: keys.map { ($0, NSNull()) })])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func anUnknownValueIsNeverTaken() async {
        account.prefs = ["theme": "sepia", "shiori.result_style": "glow"]
        account.updated = ["theme": 10, "shiori.result_style": 10]
        defaults.set("night", forKey: "theme")
        defaults.set("tint", forKey: "resultStyle")
        _ = await contact()
        #expect(defaults.string(forKey: "theme") == "night")
        #expect(defaults.string(forKey: "resultStyle") == "tint")
    }
}
