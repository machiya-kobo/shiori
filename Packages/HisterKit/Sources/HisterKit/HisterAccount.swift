import Foundation

/// Signing in to Hister from the apps (docs/signing-in.md): the app ends up
/// holding a Hister session of its own (`Cookie: hister=…` to Hister) and
/// the sign-in helper's id for it (`Authorization: Bearer mhs_…` to the
/// rooms). The helper (hister-login) sits on Hister's own host under
/// `/machiya/`, so nothing here needs an address of its own.
///
/// Two ways in: the password (Hister's `POST /api/login`, then the
/// helper's `POST /machiya/api/app-session` trades the session for an id),
/// or the helper's sign-in page in an ephemeral web session
/// (`/machiya/signin?app=1&return=shiori://signed-in`), which comes back
/// with `#sid=…&hister=…`. Sign-out goes through the helper, which ends the
/// Hister session and every id on it. Inert until the helper says Hister
/// has users (`availability`). Values are never logged.
public enum HisterAccount {
    /// Hister's session cookie.
    public static let cookieName = "hister"
    /// Where the helper's sign-in page sends the app back.
    public static let callbackScheme = "shiori"
    public static let callbackURL = "shiori://signed-in"

    /// A signed-in app: its Hister session, the helper's id, and who.
    public struct SignedIn: Sendable, Equatable {
        public let session: String
        public let sessionID: String
        public let username: String

        public init(session: String, sessionID: String, username: String) {
            self.session = session
            self.sessionID = sessionID
            self.username = username
        }
    }

    public enum SignInError: Error, Equatable, Sendable {
        /// Hister didn't take the name and password.
        case invalidCredentials
        /// Hister signs in only through its OIDC provider (use the browser).
        case passwordOff
        /// Hister has no users, or it or the helper can't be reached.
        case unavailable
        /// The browser's sign-in came back without a usable answer.
        case badCallback
        case unreachable

        public var message: String {
            switch self {
            case .invalidCredentials: "Hister didn't recognise that name and password."
            case .passwordOff: "This Hister signs in only through its sign-in provider: use Sign In with Saved Password."
            case .unavailable: "Sign-in is unavailable right now: Hister or its sign-in helper isn't answering."
            case .badCallback: "The sign-in didn't come back with a session. Try again."
            case .unreachable: "The server didn't answer. Check your network or VPN, then try again."
            }
        }
    }

    // MARK: Checks

    /// A Hister session value (32 random bytes, base64url, as Hister makes
    /// them), else nil.
    public static func session(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return isBase64URL(value, count: 43) ? value : nil
    }

    /// The helper's id (`mhs_` and 43 base64url characters), else nil.
    public static func sessionID(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("mhs_"), isBase64URL(String(value.dropFirst(4)), count: 43) else { return nil }
        return value
    }

    private static func isBase64URL(_ s: String, count: Int) -> Bool {
        s.utf8.count == count
            && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D || $0 == 0x5F }
    }

    // MARK: Addresses

    /// The helper's sign-in page for the app (opened in an ephemeral web
    /// session). `provider` (one of `oauthProviders`, "oidc" for the
    /// tailnet's): the helper goes straight on to it, so it's one tap to
    /// signed in; a helper that doesn't know the parameter shows its page.
    public static func browserSignInURL(server: URL, provider: String? = nil) -> URL {
        var components = URLComponents(url: server.appending(path: "machiya/signin"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "app", value: "1"), URLQueryItem(name: "return", value: callbackURL)]
        if let provider, !provider.isEmpty, provider.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
            items.append(URLQueryItem(name: "provider", value: provider))
        }
        components.setQueryItems(items)
        return components.url!
    }

    /// The sign-in providers Hister offers besides the password (its
    /// `/api/config` `oauthProviders`: "oidc" for the tailnet's); none on
    /// any failure.
    public static func oauthProviders(server: URL, session: URLSession = HisterClient.defaultSession) async -> [String] {
        var request = URLRequest(url: server.appending(path: "api/config"), timeoutInterval: 6)
        request.setValue("hister://", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request, delegate: NoRedirects()),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return (reply["oauthProviders"] as? [String] ?? []).filter { !$0.isEmpty }
    }

    /// The browser flow's answer, `shiori://signed-in#sid=…&hister=…`: the
    /// id and the Hister session, both checked; nil for anything else.
    public static func callback(_ url: URL) -> (sessionID: String, session: String)? {
        guard url.scheme?.lowercased() == callbackScheme, url.host() == "signed-in", let fragment = url.fragment(percentEncoded: true)
        else { return nil }
        var parts = URLComponents()
        parts.percentEncodedQuery = fragment
        let items = parts.queryItems ?? []
        guard let sid = sessionID(items.first { $0.name == "sid" }?.value),
            let hister = session(items.first { $0.name == "hister" }?.value)
        else { return nil }
        return (sid, hister)
    }

    // MARK: Network

    /// Whether signing in is possible: the helper answers on Hister's host
    /// and Hister has users. False otherwise (no helper, no users, down):
    /// then no sign-in is offered.
    public static func available(server: URL, session: URLSession = HisterClient.defaultSession) async -> Bool {
        var request = URLRequest(url: server.appending(path: "machiya/healthz"), timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request, delegate: NoRedirects()),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return reply["ok"] as? Bool == true && reply["hister"] as? String == "ok"
    }

    /// Signs in with a name and password: Hister's own login, then the
    /// helper trades the new session for an id (`label` names this device
    /// on the helper's sessions page). A session the helper won't take is
    /// logged out again, so none is left behind.
    public static func signIn(
        server: URL, username: String, password: String, label: String,
        session: URLSession = HisterClient.defaultSession
    ) async throws(SignInError) -> SignedIn {
        let hister = try await login(server: server, username: username, password: password, session: session)
        do {
            let (sid, user) = try await appSession(server: server, hister: hister, label: label, session: session)
            return SignedIn(session: hister, sessionID: sid, username: user)
        } catch {
            await logout(server: server, hister: hister, session: session)
            throw error
        }
    }

    /// Hister's own password login (`POST /api/login`): the new session.
    static func login(
        server: URL, username: String, password: String, session: URLSession
    ) async throws(SignInError) -> String {
        var login = URLRequest(url: server.appending(path: "api/login"), timeoutInterval: 15)
        login.httpMethod = "POST"
        login.setValue("hister://", forHTTPHeaderField: "Origin")
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try? JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let (status, headers, _) = try await send(login, session)
        switch status {
        case 200: break
        case 401: throw .invalidCredentials
        case 403: throw .passwordOff
        default: throw .unavailable
        }
        guard let hister = sessionCookie(in: headers, for: login.url!) else { throw .unavailable }
        return hister
    }

    /// The helper's id for a Hister session the app holds (`POST
    /// /machiya/api/app-session`), and who it is.
    static func appSession(
        server: URL, hister: String, label: String, session: URLSession
    ) async throws(SignInError) -> (String, String) {
        var request = URLRequest(url: server.appending(path: "machiya/api/app-session"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["hister": hister, "label": String(label.prefix(80))])
        let (status, _, data) = try await send(request, session)
        guard status == 200 else { throw status == 401 ? .invalidCredentials : .unavailable }
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let sid = sessionID(reply?["sid"] as? String) else { throw .unavailable }
        return (sid, String(((reply?["username"] as? String) ?? "").prefix(64)))
    }

    /// Who a Hister session belongs to (`GET /api/profile`): the name, or
    /// nil when it isn't signed in. A bare 200 (Hister without users) is
    /// never "signed in".
    public static func username(
        server: URL, hister: String, session: URLSession = HisterClient.defaultSession
    ) async throws(SignInError) -> String? {
        var request = URLRequest(url: server.appending(path: "api/profile"), timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(cookieName)=\(hister)", forHTTPHeaderField: "Cookie")
        let (status, _, data) = try await send(request, session)
        if status == 401 || status == 403 { return nil }
        guard status == 200 else { throw .unavailable }
        let name = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["username"] as? String
        guard let name, !name.isEmpty else { throw .unavailable }
        return String(name.prefix(64))
    }

    /// The browser flow's answer made whole: who the session is.
    public static func finishBrowserSignIn(
        server: URL, callback url: URL, session: URLSession = HisterClient.defaultSession
    ) async throws(SignInError) -> SignedIn {
        guard let (sid, hister) = callback(url) else { throw .badCallback }
        guard let name = try await username(server: server, hister: hister, session: session) else { throw .badCallback }
        return SignedIn(session: hister, sessionID: sid, username: name)
    }

    /// Signs out through the helper (`POST /machiya/signout`, `Bearer
    /// mhs_…`): the Hister session and every id on it end. Best effort: the
    /// app forgets both whatever the answer.
    public static func signOut(server: URL, sessionID: String, session: URLSession = HisterClient.defaultSession) async {
        guard let sid = self.sessionID(sessionID) else { return }
        var request = URLRequest(url: server.appending(path: "machiya/signout"), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(sid)", forHTTPHeaderField: "Authorization")
        _ = try? await send(request, session)
    }

    /// Hister's own logout for a session the helper never took.
    static func logout(server: URL, hister: String, session: URLSession) async {
        var request = URLRequest(url: server.appending(path: "api/logout"), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("hister://", forHTTPHeaderField: "Origin")
        request.setValue("\(cookieName)=\(hister)", forHTTPHeaderField: "Cookie")
        _ = try? await send(request, session)
    }

    /// The `hister` cookie Hister set, checked.
    static func sessionCookie(in headers: [String: String], for url: URL) -> String? {
        HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .first { $0.name == cookieName && ($0.expiresDate.map { $0 > .now } ?? true) }
            .flatMap { session($0.value) }
    }

    /// One request, following no redirect (a credential never goes along).
    private static func send(
        _ request: URLRequest, _ session: URLSession
    ) async throws(SignInError) -> (Int, [String: String], Data) {
        do {
            let (data, response) = try await session.data(for: request, delegate: NoRedirects())
            guard let http = response as? HTTPURLResponse else { throw SignInError.unavailable }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
            return (http.statusCode, headers, data)
        } catch let error as SignInError {
            throw error
        } catch {
            throw .unreachable
        }
    }
}
