import Foundation

/// The Machiya sign-in: with Machiya's identity file the rooms (Kura,
/// Konbini, Niwa) want a proof, a token sent as `Authorization: Bearer …`:
/// `mch_…` (a stored token, pasted) or `mcd_…` (a device token, from
/// pairing with a one-time code, `POST /api/pair`).
///
/// The token goes to exactly the configured rooms, compared by origin, and
/// never to Hister, SearXNG or any other host, nor across a redirect to
/// another origin. search-core.js's `machiya…` functions are the twins
/// (scripts/machiya.test.mjs has the same cases as MachiyaTests).
public enum Machiya {
    /// A pairing code as typed: uppercase, spaces and dashes gone; "" when
    /// it can't be one.
    public static func code(_ raw: String) -> String {
        let code = String(raw.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "-" })
            .uppercased()
        guard (1...64).contains(code.unicodeScalars.count), code.unicodeScalars.allSatisfy(isASCIIAlphanumeric)
        else { return "" }
        return code
    }

    /// A pasted token, trimmed; "" unless it looks like one (`mch_…` or
    /// `mcd_…`, nothing that could split a header).
    public static func token(_ raw: String) -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix("mch_") || token.hasPrefix("mcd_") else { return "" }
        let rest = token.unicodeScalars.dropFirst(4)
        guard (8...4096).contains(rest.count),
            rest.allSatisfy({ isASCIIAlphanumeric($0) || $0 == "_" || $0 == "." || $0 == "-" })
        else { return "" }
        return token
    }

    /// A device's label for pairing: no control characters, at most 64
    /// characters, `fallback` when empty.
    public static func device(_ raw: String, fallback: String = "Shiori") -> String {
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = String(cleaned.unicodeScalars.prefix(64).map(Character.init)).trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? fallback : label
    }

    /// The Authorization header's value.
    public static func authHeader(_ token: String) -> String { "Bearer " + token }

    /// An address's origin ("https://host:port", default ports dropped),
    /// or nil for anything but plain http(s): a user or password in it
    /// counts as not plain.
    public static func origin(of raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: text) else { return nil }
        return origin(components)
    }

    public static func origin(of url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        return origin(components)
    }

    private static func origin(_ components: URLComponents) -> String? {
        guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            components.user == nil, components.password == nil,
            let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        let standard = scheme == "https" ? 443 : 80
        let shownHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        if let port = components.port, port != standard { return "\(scheme)://\(shownHost):\(port)" }
        return "\(scheme)://\(shownHost)"
    }

    /// The origins a token may go to: the rooms' bases (Kura, Konbini,
    /// Niwa; empty or unreadable ones left out), less any origin in
    /// `excluding` (Hister's, SearXNG's): a room sharing an origin with
    /// them gets none.
    public static func rooms(_ bases: [String], excluding others: [String] = []) -> [String] {
        let never = Set(others.compactMap { origin(of: $0) })
        var seen: [String] = []
        for base in bases {
            if let o = origin(of: base), !never.contains(o), !seen.contains(o) { seen.append(o) }
        }
        return seen
    }

    /// Whether a request to `url` may carry the token: its origin is one of
    /// `rooms` (from `rooms(_:excluding:)`).
    public static func mayCarryToken(to url: URL, rooms: [String]) -> Bool {
        guard let o = origin(of: url) else { return false }
        return rooms.contains(o)
    }

    public static func mayCarryToken(to raw: String, rooms: [String]) -> Bool {
        guard let o = origin(of: raw) else { return false }
        return rooms.contains(o)
    }

    /// The request with the token's header when the host rule allows it,
    /// else as it was (any Authorization it had removed).
    public static func authorize(_ request: URLRequest, token: String, rooms: [String]) -> URLRequest {
        var request = request
        // The identity file's token, or the Hister sign-in's id (`mhs_…`).
        let clean = Self.token(token).isEmpty ? (HisterAccount.sessionID(token) ?? "") : Self.token(token)
        guard !clean.isEmpty, let url = request.url, mayCarryToken(to: url, rooms: rooms) else {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            return request
        }
        request.setValue(authHeader(clean), forHTTPHeaderField: "Authorization")
        return request
    }

    /// A redirect's new request: it keeps the header only when it stays on
    /// the origin the original went to and that origin is still a room.
    /// (URLSession would otherwise copy the header to wherever it leads.)
    public static func redirected(_ new: URLRequest, from original: URLRequest?, rooms: [String]) -> URLRequest {
        var new = new
        guard new.value(forHTTPHeaderField: "Authorization") != nil else { return new }
        let from = original?.url.flatMap { origin(of: $0) }
        let to = new.url.flatMap { origin(of: $0) }
        if from == nil || from != to || !rooms.contains(to ?? "") {
            new.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return new
    }

    /// What pairing answered, or why it couldn't.
    public struct Pairing: Sendable, Equatable {
        public var token: String
        public var principal: String
    }

    public enum PairError: Error, Equatable, Sendable {
        /// 400: the room didn't take it as a code; also a typed code that can't be one.
        case invalid
        /// 401: wrong or expired.
        case badCode
        /// 404: the room runs without the identity file.
        case noSignIn
        /// 415.
        case notJSON
        /// 429: five tries per address per ten minutes.
        case throttled
        /// No Kura address to pair with.
        case noRoom
        case unreachable
        /// 200 without a token.
        case badReply
        case server(status: Int)

        /// search-core's `machiyaPairError` / `machiyaPair` messages.
        public var message: String {
            switch self {
            case .invalid: "The room didn't take that as a pairing code."
            case .badCode: "That code is wrong or has expired. Make a new one with identity pair."
            case .noSignIn: "This room has no sign-in: it runs without Machiya's identity file."
            case .notJSON: "The room wanted JSON and refused the request."
            case .throttled: "Too many tries. Wait ten minutes, then try again."
            case .noRoom: "Set Kura’s address first."
            case .unreachable: "The room didn't answer. Check your network or VPN, then try again."
            case .badReply: "The room's answer held no token."
            case .server(let status): "The room answered HTTP \(status)."
            }
        }

        static func from(status: Int) -> PairError {
            switch status {
            case 400: .invalid
            case 401: .badCode
            case 404: .noSignIn
            case 415: .notJSON
            case 429: .throttled
            default: .server(status: status)
            }
        }
    }

    /// The pairing request: `POST <base>api/pair` with `{code, device}`.
    static func pairRequest(base: String, code: String, device: String) -> URLRequest? {
        var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard origin(of: text) != nil else { return nil }
        if !text.hasSuffix("/") { text += "/" }
        guard let url = URL(string: text + "api/pair") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "device": Self.device(device)], options: [.sortedKeys])
        return request
    }

    /// Pairs this device with a code from `identity pair`, against `base`
    /// (Kura's address): the device token and who it signs in as.
    public static func pair(
        base: String, code rawCode: String, device: String, session: URLSession = HisterClient.defaultSession
    ) async throws(PairError) -> Pairing {
        let code = Self.code(rawCode)
        guard !code.isEmpty else { throw .invalid }
        guard let request = pairRequest(base: base, code: code, device: device) else { throw .noRoom }
        let data: Data
        let response: URLResponse
        do {
            // No redirects: a code is a proof too.
            (data, response) = try await session.data(for: request, delegate: NoRedirects())
        } catch {
            throw .unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw .unreachable }
        guard http.statusCode == 200 else { throw PairError.from(status: http.statusCode) }
        struct Reply: Decodable {
            var token: String?
            var principal: String?
        }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        let token = Self.token(reply?.token ?? "")
        let principal = String((reply?.principal ?? "").prefix(64))
        guard !token.isEmpty, !principal.isEmpty else { throw .badReply }
        return Pairing(token: token, principal: principal)
    }

    /// What was typed in Sign in to Machiya's one field.
    public enum Entry: Equatable, Sendable {
        case token(String)
        case code(String)
    }

    /// A pasted token, a pairing code (normalised), or nil for neither
    /// (search-core's `machiyaEntry`).
    public static func entry(_ raw: String) -> Entry? {
        let token = Self.token(raw)
        if !token.isEmpty { return .token(token) }
        let code = Self.code(raw)
        return code.isEmpty ? nil : .code(code)
    }

    /// The signed-in line (search-core's `machiyaStatusText`).
    public static func statusText(token: String, principal: String) -> String {
        if token.isEmpty { return "Not signed in" }
        return principal.isEmpty ? "Signed in with a token" : "Signed in as \(principal)"
    }

    private static func isASCIIAlphanumeric(_ s: Unicode.Scalar) -> Bool {
        ("A"..."Z").contains(s) || ("a"..."z").contains(s) || ("0"..."9").contains(s)
    }
}

/// A signed-in device's proof and where it may go: the rooms' origins
/// (`Machiya.rooms`). The room clients (`KuraClient`, `Notes.fetchCards`)
/// take one; Hister's and SearXNG's never do.
public struct MachiyaSignIn: Sendable, Equatable {
    public var token: String
    public var rooms: [String]

    /// nil without a token that looks like one.
    public init?(token: String, rooms: [String]) {
        let clean = Machiya.token(token)
        guard !clean.isEmpty else { return nil }
        self.token = clean
        self.rooms = rooms
    }

    /// Signed in through Hister (`HisterAccount`): the helper's id, which
    /// rooms in Hister sign-in mode take as `Bearer mhs_…`, under the same
    /// host rule. nil without one that looks like one.
    public init?(sessionID: String, rooms: [String]) {
        guard let sid = HisterAccount.sessionID(sessionID) else { return nil }
        self.token = sid
        self.rooms = rooms
    }

    /// The request with the header where the host rule allows.
    public func authorize(_ request: URLRequest) -> URLRequest {
        Machiya.authorize(request, token: token, rooms: rooms)
    }
}

/// Keeps the header off a redirect to another origin: a per-task
/// delegate, since the session is HisterClient's shared one.
final class MachiyaRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    let rooms: [String]
    init(rooms: [String]) { self.rooms = rooms }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Machiya.redirected(request, from: task.originalRequest, rooms: rooms))
    }
}

/// Follows no redirect (pairing).
final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension URLSession {
    /// A room's request: signed in where the host rule allows, and the
    /// header kept off any redirect to another origin.
    func roomData(for request: URLRequest, signIn: MachiyaSignIn?) async throws -> (Data, URLResponse) {
        guard let signIn else { return try await data(for: request) }
        return try await data(for: signIn.authorize(request), delegate: MachiyaRedirects(rooms: signIn.rooms))
    }
}
