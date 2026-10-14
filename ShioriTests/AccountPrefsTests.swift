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

    @Test func oneValueTheAccountRefusesDoesntTakeTheRestWithIt() async {
        account.prefs = ["theme": "night", "palette": "nord"]
        account.updated = ["theme": 10, "palette": 10]
        _ = await contact()
        defaults.set("day", forKey: "theme")
        defaults.set("dracula", forKey: "palette")
        // The account refuses any batch holding the palette, and the palette alone.
        let account = account
        StubProtocol.handle(Self.host) { request in
            if request.httpMethod == "PUT",
               let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any],
               (body["prefs"] as? [String: Any])?["palette"] != nil {
                return (400, Data(#"{"error":"bad value"}"#.utf8))
            }
            return account.handle(request)
        }
        #expect(await contact() == .synced)
        #expect(account.prefs["theme"] == "day")
        #expect(account.prefs["palette"] == "nord")
        // The palette was in the refused batch: it was really sent.
        let puts = StubProtocol.requests(Self.host).filter { $0.httpMethod == "PUT" }
        #expect(puts.count >= 2)
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
    /// owner's own. Puts back only what it changed, as it was before.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PREFS_LIVE_URL"] != nil))
    func theLiveHelperTakesAndGives() async throws {
        let env = ProcessInfo.processInfo.environment
        let base = try #require(URL(string: env["PREFS_LIVE_URL"]!))
        let token = try String(contentsOfFile: try #require(env["PREFS_LIVE_TOKEN_FILE"]), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // The account as it was, read on the helper's own session (no
        // redirect followed: the request carries the token).
        func prefs() async throws -> [String: String] {
            let request = AccountPrefs.request(base: base, credential: .token(token), method: "GET")
            let (data, response) = try await AccountPrefs.session.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (object["prefs"] as? [String: String]) ?? [:]
        }
        let before = try await prefs()
        let suite = "prefs-live-\(UUID().uuidString)"
        let live = UserDefaults(suiteName: suite)!
        defer { live.removePersistentDomain(forName: suite) }
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
        // Clean up: each key whose value moved goes back to what it was
        // (or away, if it wasn't there); the rest are left alone.
        let after = try await prefs()
        var restore: [String: Any] = [:]
        for key in Set(after.keys).union(before.keys) where after[key] != before[key] {
            restore[key] = before[key].map { $0 as Any } ?? NSNull()
        }
        if !restore.isEmpty {
            var request = AccountPrefs.request(base: base, credential: .token(token), method: "PUT")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["prefs": restore])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await AccountPrefs.session.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
        #expect(try await prefs() == before)
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
