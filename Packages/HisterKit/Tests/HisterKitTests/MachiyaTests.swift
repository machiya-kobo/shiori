import Foundation
import Testing

@testable import HisterKit

/// The Machiya sign-in, with scripts/machiya.test.mjs's cases: pairing,
/// the token's header, and the host rule that keeps it to the rooms.
@Suite(.serialized)
struct MachiyaTests {
    static let kuraHost = "kura.machiya.example"
    static let konbiniHost = "konbini.machiya.example"
    static let kura = "https://\(kuraHost)/"
    static let konbini = "https://\(konbiniHost)/"
    static let hister = "https://hister.example/"
    static let searx = "https://searx.example/"
    static let token = "mch_q9xa_" + String(repeating: "A", count: 43)
    static let deviceToken = "mcd_eyJwIjoiYWxleCJ9.c2lnbmF0dXJl"
    let rooms = Machiya.rooms([kura, konbini], excluding: [hister, searx])
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset(Self.kuraHost)
        StubProtocol.reset(Self.konbiniHost)
    }

    @Test func codesAreUppercasedWithoutSpacesOrDashes() {
        #expect(Machiya.code("abcd-efgh") == "ABCDEFGH")
        #expect(Machiya.code("  abcd efgh ") == "ABCDEFGH")
        #expect(Machiya.code("ab-cd - ef\tgh") == "ABCDEFGH")
        #expect(Machiya.code("") == "")
        #expect(Machiya.code(" - ") == "")
        #expect(Machiya.code("abcd/efgh") == "")
    }

    @Test func tokensAreMchOrMcdWithNothingThatSplitsAHeader() {
        #expect(Machiya.token("  \(Self.token)\n") == Self.token)
        #expect(Machiya.token(Self.deviceToken) == Self.deviceToken)
        #expect(Machiya.token("Bearer " + Self.token) == "")
        #expect(Machiya.token("mch_short") == "")
        #expect(Machiya.token(Self.token + "\r\nX-Evil: 1") == "")
        #expect(Machiya.token("mcx_" + String(repeating: "A", count: 20)) == "")
        #expect(Machiya.authHeader(Self.token) == "Bearer " + Self.token)
    }

    @Test func deviceLabels() {
        #expect(Machiya.device(" iPhone\n") == "iPhone")
        #expect(Machiya.device("") == "Shiori")
        #expect(Machiya.device("\u{07}", fallback: "Mac") == "Mac")
        #expect(Machiya.device(String(repeating: "é", count: 80)).count == 64)
    }

    @Test func theTokenGoesToExactlyTheRoomsByOrigin() {
        let yes = [
            "https://\(Self.kuraHost)/api/search?q=x",
            "https://KURA.machiya.example/api/vaults",
            "https://\(Self.kuraHost):443/api/note",
            "https://\(Self.konbiniHost)/api/cards",
            "https://\(Self.kuraHost)/other/path",
        ]
        for url in yes { #expect(Machiya.mayCarryToken(to: url, rooms: rooms), "\(url)") }
        let no = [
            Self.hister + "api/add",
            Self.searx + "search?q=x",
            "https://\(Self.kuraHost)@evil.example/api/search",  // userinfo trick: the host is evil.example
            "https://user:pw@\(Self.kuraHost)/api/search",  // userinfo on the room itself
            "https://\(Self.kuraHost).evil.example/",  // lookalike: a longer host
            "https://evil\(Self.kuraHost)/",  // lookalike: a prefix
            "https://\(Self.kuraHost):8443/",  // another port
            "http://\(Self.kuraHost)/",  // http where https is configured
            "https://evil.example/?u=https://\(Self.kuraHost)/",
            "ftp://\(Self.kuraHost)/",
            "javascript:alert(1)",
            "not a url",
            "",
        ]
        for url in no { #expect(!Machiya.mayCarryToken(to: url, rooms: rooms), "\(url)") }
    }

    @Test func roomsAreHTTPBasesNeverOnHisterOrSearXNG() {
        #expect(rooms == ["https://\(Self.kuraHost)", "https://\(Self.konbiniHost)"])
        #expect(Machiya.rooms(["https://hister.example/kura/", Self.konbini], excluding: [Self.hister, Self.searx]) == ["https://\(Self.konbiniHost)"])
        #expect(Machiya.rooms(["", "__SHIORI_KURA_URL__", "ftp://kura.example/", "https://u:p@kura.example/"]).isEmpty)
        let local = Machiya.rooms(["http://localhost:8080/"])
        #expect(Machiya.mayCarryToken(to: "http://localhost:8080/api/vaults", rooms: local))
        #expect(!Machiya.mayCarryToken(to: "https://localhost:8080/api/vaults", rooms: local))
        #expect(!Machiya.mayCarryToken(to: "http://localhost/api/vaults", rooms: local))
    }

    @Test func requestsGetTheHeaderOnlyWhereTheRuleAllows() throws {
        let signIn = try #require(MachiyaSignIn(token: Self.token, rooms: rooms))
        let kura = signIn.authorize(URLRequest(url: URL(string: Self.kura + "api/search")!))
        #expect(kura.value(forHTTPHeaderField: "Authorization") == "Bearer " + Self.token)
        for url in [Self.hister + "search", Self.searx + "search", "https://\(Self.kuraHost)@evil.example/"] {
            var request = URLRequest(url: URL(string: url)!)
            request.setValue("Bearer stale", forHTTPHeaderField: "Authorization")
            #expect(signIn.authorize(request).value(forHTTPHeaderField: "Authorization") == nil, "\(url)")
        }
        #expect(MachiyaSignIn(token: "", rooms: rooms) == nil)
        #expect(MachiyaSignIn(token: "not a token", rooms: rooms) == nil)
    }

    @Test func aRedirectToAnotherOriginLosesTheHeader() throws {
        let signIn = try #require(MachiyaSignIn(token: Self.token, rooms: rooms))
        let original = signIn.authorize(URLRequest(url: URL(string: Self.kura + "api/vaults")!))
        func follow(_ to: String) -> String? {
            var next = URLRequest(url: URL(string: to)!)
            next.setValue(original.value(forHTTPHeaderField: "Authorization"), forHTTPHeaderField: "Authorization")
            return Machiya.redirected(next, from: original, rooms: rooms).value(forHTTPHeaderField: "Authorization")
        }
        #expect(follow(Self.kura + "api/vaults/") == "Bearer " + Self.token)
        #expect(follow("https://evil.example/") == nil)
        #expect(follow(Self.konbini + "api/cards") == nil)  // another room, but not where it was sent
        #expect(follow("http://\(Self.kuraHost)/api/vaults") == nil)
        #expect(follow(Self.hister) == nil)
    }

    @Test func kuraAndKonbiniSendTheSignIn() async throws {
        let signIn = try #require(MachiyaSignIn(token: Self.token, rooms: rooms))
        StubProtocol.handle(Self.kuraHost) { _ in (200, Data(#"{"vaults":[{"name":"main","default":true}],"total":0,"results":[]}"#.utf8)) }
        StubProtocol.handle(Self.konbiniHost) { _ in (200, Data(#"{"cards":[]}"#.utf8)) }
        let kura = try #require(KuraClient(serverURL: Self.kura, session: session, signIn: signIn))
        _ = try await kura.vaults()
        _ = try await kura.search("garden")
        _ = await Notes.fetchCards(base: Self.konbini, session: session, signIn: signIn)
        let sent = StubProtocol.requests(Self.kuraHost) + StubProtocol.requests(Self.konbiniHost)
        #expect(sent.count == 3)
        for request in sent { #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + Self.token) }
        // Without a sign-in, none.
        StubProtocol.reset(Self.kuraHost)
        StubProtocol.handle(Self.kuraHost) { _ in (200, Data(#"{"vaults":[]}"#.utf8)) }
        _ = try await KuraClient(serverURL: Self.kura, session: session)!.vaults()
        #expect(StubProtocol.requests(Self.kuraHost).first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aKuraOffTheRoomsGetsNoToken() async throws {
        // Signed in for other rooms: this Kura's origin isn't one.
        let signIn = try #require(MachiyaSignIn(token: Self.token, rooms: Machiya.rooms([Self.konbini])))
        StubProtocol.handle(Self.kuraHost) { _ in (200, Data(#"{"vaults":[]}"#.utf8)) }
        _ = try await KuraClient(serverURL: Self.kura, session: session, signIn: signIn)!.vaults()
        #expect(StubProtocol.requests(Self.kuraHost).first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func pairingPostsTheCodeAndDeviceAndAnswersTheToken() async throws {
        StubProtocol.handle(Self.kuraHost) { _ in (200, Data(#"{"token":"\#(Self.deviceToken)","principal":"alex"}"#.utf8)) }
        let pairing = try await Machiya.pair(base: "https://\(Self.kuraHost)", code: "abcd-efgh", device: "iPhone", session: session)
        #expect(pairing == Machiya.Pairing(token: Self.deviceToken, principal: "alex"))
        let request = try #require(StubProtocol.requests(Self.kuraHost).first)
        #expect(request.url?.absoluteString == Self.kura + "api/pair")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["code": "ABCDEFGH", "device": "iPhone"])
    }

    @Test(arguments: [
        (401, #"{"error":"unknown or expired code"}"#, Machiya.PairError.badCode),
        (429, #"{"error":"too many tries"}"#, .throttled),
        (415, #"{"error":"send JSON"}"#, .notJSON),
        (404, #"{"error":"not found"}"#, .noSignIn),
        (400, #"{"error":"send code"}"#, .invalid),
        (503, "unavailable", .server(status: 503)),
        (200, #"{"principal":"alex"}"#, .badReply),
        (200, #"{"token":"Bearer x","principal":"alex"}"#, .badReply),
    ])
    func pairingRefusalsSayWhatToDo(status: Int, body: String, expected: Machiya.PairError) async {
        StubProtocol.reset(Self.kuraHost)
        StubProtocol.handle(Self.kuraHost) { _ in (status, Data(body.utf8)) }
        await #expect(throws: expected) {
            _ = try await Machiya.pair(base: Self.kura, code: "ABCD-EFGH", device: "iPhone", session: session)
        }
    }

    @Test func pairingMessagesAreSearchCoresOwn() {
        #expect(Machiya.PairError.badCode.message.contains("wrong or has expired"))
        #expect(Machiya.PairError.throttled.message.contains("Wait ten minutes"))
        #expect(Machiya.PairError.noSignIn.message.contains("no sign-in"))
        #expect(Machiya.PairError.server(status: 503).message.contains("HTTP 503"))
    }

    @Test func pairingSendsNothingWithoutACodeOrARoom() async {
        StubProtocol.handle(Self.kuraHost) { _ in (200, Data("{}".utf8)) }
        await #expect(throws: Machiya.PairError.invalid) {
            _ = try await Machiya.pair(base: Self.kura, code: " - ", device: "x", session: session)
        }
        await #expect(throws: Machiya.PairError.noRoom) {
            _ = try await Machiya.pair(base: "", code: "ABCD", device: "x", session: session)
        }
        await #expect(throws: Machiya.PairError.noRoom) {
            _ = try await Machiya.pair(base: "https://u:p@\(Self.kuraHost)/", code: "ABCD", device: "x", session: session)
        }
        #expect(StubProtocol.requests(Self.kuraHost).isEmpty)
    }

    @Test func theSignInFieldAndStatusLine() {
        #expect(Machiya.entry(" \(Self.token) ") == .token(Self.token))
        #expect(Machiya.entry("abcd-efgh") == .code("ABCDEFGH"))
        #expect(Machiya.entry("") == nil)
        #expect(Machiya.entry("what?") == nil)
        #expect(Machiya.statusText(token: "", principal: "") == "Not signed in")
        #expect(Machiya.statusText(token: Self.token, principal: "alex") == "Signed in as alex")
        #expect(Machiya.statusText(token: Self.token, principal: "") == "Signed in with a token")
    }
}
