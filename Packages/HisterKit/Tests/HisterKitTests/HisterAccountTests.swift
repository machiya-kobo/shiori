import Foundation
import Testing

@testable import HisterKit

/// Signing in to Hister from the apps, against stubs only (never a live Hister).
@Suite(.serialized)
struct HisterAccountTests {
    static let host = "account.example"
    static let server = URL(string: "https://account.example/")!
    static let S = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde"   // 43 characters
    static let sid = "mhs_" + "Z".repeat43
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
        StubProtocol.reset(Self.host)
    }

    var requests: [URLRequest] { StubProtocol.requests(Self.host) }

    @Test func valuesAreChecked() {
        #expect(HisterAccount.session(Self.S) == Self.S)
        #expect(HisterAccount.session("short") == nil)
        #expect(HisterAccount.session(Self.S + "x") == nil)
        #expect(HisterAccount.session(String(Self.S.dropLast()) + "=") == nil)
        #expect(HisterAccount.sessionID(Self.sid) == Self.sid)
        #expect(HisterAccount.sessionID("mch_" + String(Self.sid.dropFirst(4))) == nil)
        #expect(HisterAccount.sessionID(Self.S) == nil)
    }

    @Test func theBrowserFlowsAnswerIsReadFromTheFragment() {
        let url = URL(string: "shiori://signed-in#sid=\(Self.sid)&hister=\(Self.S)")!
        #expect(HisterAccount.callback(url)?.sessionID == Self.sid)
        #expect(HisterAccount.callback(url)?.session == Self.S)
        #expect(HisterAccount.callback(URL(string: "shiori://signed-in?sid=\(Self.sid)&hister=\(Self.S)")!) == nil)
        #expect(HisterAccount.callback(URL(string: "evil://signed-in#sid=\(Self.sid)&hister=\(Self.S)")!) == nil)
        #expect(HisterAccount.callback(URL(string: "shiori://signed-in#sid=nope&hister=\(Self.S)")!) == nil)
        let start = HisterAccount.browserSignInURL(server: Self.server).absoluteString
        #expect(start == "https://account.example/machiya/signin?app=1&return=shiori://signed-in")
    }

    @Test func availableOnlyWhenTheHelperSaysHisterHasUsers() async {
        for (status, body, want) in [
            (200, #"{"ok":true,"hister":"ok"}"#, true),
            (200, #"{"ok":true,"hister":"user-handling-off"}"#, false),
            (200, #"{"ok":true,"hister":"down"}"#, false),
            (404, "not found", false),
        ] {
            StubProtocol.handle(Self.host) { _ in (status, Data(body.utf8)) }
            #expect(await HisterAccount.available(server: Self.server, session: session) == want)
        }
    }

    @Test func aPasswordSignInTradesTheSessionForAnId() async throws {
        StubProtocol.headers(Self.host, ["Set-Cookie": "hister=\(Self.S); Path=/; HttpOnly; Secure"])
        StubProtocol.handle(Self.host) { request in
            switch request.url?.path() {
            case "/api/login": (200, Data(#"{"username":"alex"}"#.utf8))
            case "/machiya/api/app-session": (200, Data(#"{"sid":"\#(Self.sid)","username":"alex","user_id":1}"#.utf8))
            default: (404, Data())
            }
        }
        let signedIn = try await HisterAccount.signIn(server: Self.server, username: "alex", password: "pw", label: "iPhone", session: session)
        #expect(signedIn == HisterAccount.SignedIn(session: Self.S, sessionID: Self.sid, username: "alex"))
        let login = try #require(requests.first)
        #expect(login.value(forHTTPHeaderField: "Origin") == "hister://")
        #expect(login.httpMethod == "POST")
        let trade = try #require(requests.last)
        let body = try JSONSerialization.jsonObject(with: trade.httpBody ?? Data()) as? [String: String]
        #expect(body == ["hister": Self.S, "label": "iPhone"])
        #expect(trade.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func wrongPasswordAndPasswordOff() async {
        StubProtocol.handle(Self.host) { _ in (401, Data("invalid credentials".utf8)) }
        await #expect(throws: HisterAccount.SignInError.invalidCredentials) {
            try await HisterAccount.signIn(server: Self.server, username: "a", password: "b", label: "", session: session)
        }
        StubProtocol.handle(Self.host) { _ in (403, Data()) }
        await #expect(throws: HisterAccount.SignInError.passwordOff) {
            try await HisterAccount.signIn(server: Self.server, username: "a", password: "b", label: "", session: session)
        }
    }

    @Test func aSessionTheHelperWontTakeIsLoggedOut() async throws {
        StubProtocol.headers(Self.host, ["Set-Cookie": "hister=\(Self.S); Path=/"])
        StubProtocol.handle(Self.host) { request in
            request.url?.path() == "/api/login" ? (200, Data("{}".utf8)) : (503, Data(#"{"error":"sign-in is unavailable"}"#.utf8))
        }
        await #expect(throws: HisterAccount.SignInError.unavailable) {
            try await HisterAccount.signIn(server: Self.server, username: "a", password: "b", label: "", session: session)
        }
        let logout = try #require(requests.last)
        #expect(logout.url?.path() == "/api/logout")
        #expect(logout.value(forHTTPHeaderField: "Cookie") == "hister=\(Self.S)")
    }

    @Test func signOutGoesThroughTheHelperWithTheId() async throws {
        StubProtocol.handle(Self.host) { _ in (204, Data()) }
        await HisterAccount.signOut(server: Self.server, sessionID: Self.sid, session: session)
        let request = try #require(requests.first)
        #expect(request.url?.path() == "/machiya/signout")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.sid)")
    }

    @Test func theClientSendsTheSessionAndHearsASignOut() async throws {
        StubProtocol.handle(Self.host) { _ in (403, Data()) }
        let client = try #require(HisterClient(serverURL: "https://\(Self.host)", histerSession: Self.S, session: session))
        #expect(client.sendsSession)
        await #expect(throws: HisterError.signedOut) { try await client.search("x") }
        #expect(requests.first?.value(forHTTPHeaderField: "Cookie") == "hister=\(Self.S)")
        let none = try #require(HisterClient(serverURL: "https://\(Self.host)", histerSession: "nope", session: session))
        #expect(!none.sendsSession)
    }

    @Test func theRoomsGetTheIdAsABearer() throws {
        let signIn = try #require(MachiyaSignIn(sessionID: Self.sid, rooms: ["https://kura.example"]))
        let request = signIn.authorize(URLRequest(url: URL(string: "https://kura.example/api/search")!))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.sid)")
        let elsewhere = signIn.authorize(URLRequest(url: URL(string: "https://hister.example/search")!))
        #expect(elsewhere.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(MachiyaSignIn(sessionID: "mch_abcdefgh", rooms: []) == nil)
    }
}

private extension String {
    var repeat43: String { String(repeating: self, count: 43) }
}

/// Against a throwaway Hister with users (never the live one: a login
/// writes a session): HISTER_USERS_URL, HISTER_USERS_NAME and
/// HISTER_USERS_PASSWORD. Skipped without them.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HISTER_USERS_URL"] != nil))
struct HisterUsersLiveTests {
    let env = ProcessInfo.processInfo.environment

    @Test func passwordLoginProfileAndASignedInSearch() async throws {
        let server = try #require(URL(string: env["HISTER_USERS_URL"] ?? ""))
        let hister = try await HisterAccount.login(
            server: server, username: env["HISTER_USERS_NAME"] ?? "", password: env["HISTER_USERS_PASSWORD"] ?? "",
            session: HisterClient.defaultSession)
        #expect(HisterAccount.session(hister) == hister)
        #expect(try await HisterAccount.username(server: server, hister: hister) == env["HISTER_USERS_NAME"])
        let signedIn = try #require(HisterClient(serverURL: server.absoluteString, histerSession: hister))
        _ = try await signedIn.search("*", limit: 1)
        let anonymous = try #require(HisterClient(serverURL: server.absoluteString))
        await #expect(throws: HisterError.signedOut) { try await anonymous.search("*", limit: 1) }
        await HisterAccount.logout(server: server, hister: hister, session: HisterClient.defaultSession)
        #expect(try await HisterAccount.username(server: server, hister: hister) == nil)
        // The user's token (HISTER_USERS_TOKEN, optional) works on its own.
        if let token = env["HISTER_USERS_TOKEN"] {
            let byToken = try #require(HisterClient(serverURL: server.absoluteString, token: token))
            _ = try await byToken.search("*", limit: 1)
        }
        await #expect(throws: HisterAccount.SignInError.invalidCredentials) {
            _ = try await HisterAccount.login(server: server, username: "nobody", password: "wrong", session: HisterClient.defaultSession)
        }
    }
}
