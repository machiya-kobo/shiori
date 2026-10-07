import Foundation
import os

/// Why a Hister request failed, in the terms the UI shows.
public enum HisterError: Error, Equatable, Sendable {
    /// No answer from the server: VPN off, no signal, wrong address.
    case unreachable
    /// The server answered, but its TLS certificate isn't trusted.
    case untrusted
    /// A plain http:// address, which the system's App Transport Security
    /// refuses: nothing was sent.
    case plainHTTP
    /// A page's preview couldn't be drawn (the app's web view failed).
    case previewUnavailable
    /// The server rejected the query itself (e.g. a bad regexp).
    case invalidQuery(String)
    /// The page is not in the index.
    case notFound
    /// A delete by URL matched this many documents instead of one.
    case unexpectedMatchCount(Int)
    /// Any other non-success reply.
    case server(status: Int, message: String)
    /// The reply was not the JSON we expected.
    case badResponse
    /// A newer request superseded this one; the UI ignores it.
    case cancelled
    /// Hister refused a page for good (skip rule, too large, sensitive).
    case rejected(Rejection)
    /// Hister wants a sign-in (403, or 401): no credential, or one it no
    /// longer takes (signed out elsewhere, a token made anew). Never retried.
    case signedOut
}

/// The orders Hister sorts in itself (its `api/config` lists them). Title
/// and label are not among them: the app sorts those.
public enum SearchSort: String, Sendable, CaseIterable {
    /// Best match first (the server's default).
    case relevance = ""
    /// Most recently updated (last visited) first.
    case newest = "date"
    case oldest = "-date"
    case mostVisited = "visits"
    /// By site, A to Z.
    case domain = "domain"
}

/// A client for one Hister server's HTTP API.
///
/// Every request carries `Origin: hister://`, which Hister's CSRF check
/// requires of a non-browser client's writes (403 without it); searches
/// ask for JSON (`Accept: application/json`), which Hister answers from any
/// origin. With a token (`HisterToken`) every request also carries
/// `X-Access-Token`, and signed in (`HisterAccount`) `Cookie: hister=…`
/// (cookies are otherwise off: the session never sets one itself); without
/// them, nothing more is sent.
public struct HisterClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    /// Hister's token, checked; nil sends none. Never logged.
    private let token: String?
    /// The app's own Hister session (`HisterAccount.session`), checked; nil
    /// sends none. Never logged.
    private let histerSession: String?

    /// For the package's network code; replies that don't decode are
    /// logged here rather than vanishing into `.badResponse`.
    static let log = Logger(subsystem: logSubsystem, category: "network")

    /// A session that gives up quickly: the server is only reachable over a
    /// VPN, and a search should say "unreachable" rather than spin.
    public static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    /// Returns nil unless `serverURL` is an absolute http(s) URL.
    public init?(
        serverURL: String, token: String? = nil, histerSession: String? = nil, session: URLSession = HisterClient.defaultSession
    ) {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        self.baseURL = url
        self.session = session
        self.token = HisterToken.clean(token)
        self.histerSession = HisterAccount.session(histerSession)
    }

    /// Whether requests carry a token (for Settings; never the token itself).
    public var sendsToken: Bool { token != nil }
    /// Whether requests carry a Hister session.
    public var sendsSession: Bool { histerSession != nil }

    // MARK: Reads

    public func search(
        _ text: String, sort: SearchSort = .relevance, pageKey: String? = nil, limit: Int = 30,
        options: SearchOptions = SearchOptions()
    ) async throws(HisterError) -> SearchPage {
        // The last word a prefix, never the notes (`SearchText.forHister`).
        var query: [String: any Sendable] = ["text": SearchText.forHister(text), "highlight": "HTML", "limit": limit]
        if sort != .relevance { query["sort"] = sort.rawValue }
        if let pageKey, !pageKey.isEmpty { query["page_key"] = pageKey }
        if options.facets { query["facets"] = true }
        if let from = options.dateFrom { query["date_from"] = Int(from.timeIntervalSince1970) }
        if let to = options.dateTo { query["date_to"] = Int(to.timeIntervalSince1970) }
        if options.semantic { query["semantic_enabled"] = true }
        let json = String(decoding: try encodeJSON(query), as: UTF8.self)
        let request = makeRequest(
            "search", query: [URLQueryItem(name: "query", value: json)], accept: "application/json")
        let response: SearchResponse = try await decode(send(request))
        let documents = (response.documents ?? []).map(\.document)
        let key = response.page_key.flatMap { $0.isEmpty ? nil : $0 }
        return SearchPage(
            total: response.total,
            documents: documents,
            // The server hands out a key even when the page came up short.
            nextPageKey: documents.count < limit ? nil : key,
            suggestion: response.query_suggestion.flatMap { $0.isEmpty ? nil : $0 },
            opened: pageKey == nil ? (response.history ?? []) : [],
            facets: response.facets)
    }

    /// The readable preview; `extractor` picks one of `extractors(for:)`
    /// instead of the server's default chain.
    public func preview(of url: String, extractor: String? = nil) async throws(HisterError) -> PagePreview {
        var items = [URLQueryItem(name: "url", value: url)]
        if let extractor, !extractor.isEmpty { items.append(URLQueryItem(name: "extractor", value: extractor)) }
        let request = makeRequest("api/preview", query: items)
        let response: PreviewResponse = try await decode(send(request))
        return response.preview
    }

    public func favicon(key: String) async throws(HisterError) -> Data {
        try await send(makeRequest("api/favicon", query: [URLQueryItem(name: "key", value: key)]))
    }

    public func rules() async throws(HisterError) -> Rules {
        let response: RulesResponse = try await decode(send(makeRequest("api/rules")))
        return Rules(aliases: response.aliases ?? [:])
    }

    /// Hister's own page for a document, to open in a browser.
    public func webPreviewURL(for url: String) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "preview"), resolvingAgainstBaseURL: false)!
        components.setQueryItems([URLQueryItem(name: "id", value: url)])
        return components.url!
    }

    // MARK: Writes

    /// Sets one page's label; an empty label clears it.
    public func setLabel(_ label: String, for url: String) async throws(HisterError) {
        let body = try encodeJSON(["url": url, "label": label])
        _ = try await send(makeRequest("api/label", method: "POST", body: body))
    }

    /// Adds or replaces a collection (a Hister alias): `keyword` expands to
    /// `value` in every search. Hister's own endpoint, an upsert, saved in
    /// its rules.json. Only Settings → AI's
    /// collection suggestions call this, and only for `@`-keywords.
    public func setAlias(_ keyword: String, value: String) async throws(HisterError) {
        guard !keyword.isEmpty, !value.isEmpty else { throw .invalidQuery("An empty collection") }
        _ = try await send(formRequest("api/add_alias", [
            URLQueryItem(name: "alias-keyword", value: keyword), URLQueryItem(name: "alias-value", value: value),
        ]))
    }

    /// Removes a collection. Hister answers 500 for one it doesn't have, so
    /// callers read `rules()` first.
    public func deleteAlias(_ keyword: String) async throws(HisterError) {
        _ = try await send(formRequest("api/delete_alias", [URLQueryItem(name: "alias", value: keyword)]))
    }

    /// A form POST (the alias endpoints read forms, not JSON), escaped the
    /// way `setQueryItems` escapes a query ("+" included).
    private func formRequest(_ path: String, _ fields: [URLQueryItem]) -> URLRequest {
        var request = makeRequest(path, method: "POST")
        var form = URLComponents()
        form.setQueryItems(fields)
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Deletes exactly one page. A dry run first counts what the query
    /// matches, and nothing is deleted unless that is exactly one document.
    public func delete(url: String) async throws(HisterError) {
        let query = Self.exactURLQuery(url)
        let matched = try await deleteRequest(query: query, dryRun: true)
        guard matched == 1 else { throw .unexpectedMatchCount(matched) }
        _ = try await deleteRequest(query: query, dryRun: false)
    }

    /// Whether Hister holds this exact address, or it with or without a
    /// trailing slash (`HEAD api/document`: 200 or 404, no body). Exact for
    /// every address, unlike a `url:(…)` search, which can't take `( ) |`;
    /// a failed lookup throws rather than reading as "not held".
    public func holds(_ url: String) async throws(HisterError) -> Bool {
        let twin = url.hasSuffix("/") ? String(url.dropLast()) : url + "/"
        for candidate in [url, twin] {
            do {
                _ = try await send(makeRequest("api/document", query: [URLQueryItem(name: "url", value: candidate)], method: "HEAD"))
                return true
            } catch .notFound {
                continue
            }
        }
        return false
    }

    /// `url:"…"`, with quotes and backslashes escaped.
    static func exactURLQuery(_ url: String) -> String {
        let escaped = url.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "url:\"\(escaped)\""
    }

    private func deleteRequest(query: String, dryRun: Bool) async throws(HisterError) -> Int {
        struct Reply: Decodable {
            var matched: Int?
            var deleted: Int?
        }
        let body = try encodeJSON(["query": query, "dry_run": dryRun] as [String: any Sendable])
        let reply: Reply = try await decode(send(makeRequest("api/delete", method: "POST", body: body)))
        return (dryRun ? reply.matched : reply.deleted) ?? 0
    }

    // MARK: Plumbing

    func sendAdd(_ body: Data) async throws(HisterError) -> Data {
        try await send(makeRequest("api/add", method: "POST", body: body))
    }

    func makeRequest(
        _ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil,
        accept: String? = nil
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.setQueryItems(query) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("hister://", forHTTPHeaderField: "Origin")
        if let token { request.setValue(token, forHTTPHeaderField: HisterToken.header) }
        if let histerSession { request.setValue("\(HisterAccount.cookieName)=\(histerSession)", forHTTPHeaderField: "Cookie") }
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send(_ request: URLRequest) async throws(HisterError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            // A redirect elsewhere never takes the token along.
            let carries = token != nil || histerSession != nil
            (data, response) = try await session.data(for: request, delegate: carries ? TokenKeepingRedirects() : nil)
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw HisterError(transport: error)
        }
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 404:
            throw .notFound
        case 400:
            throw .invalidQuery(Self.message(from: data))
        case 401, 403:
            throw .signedOut
        default:
            throw .server(status: http.statusCode, message: Self.message(from: data))
        }
    }

    private static func message(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? String
        {
            return error
        }
        return String(decoding: data.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decode<T: Decodable>(_ data: Data) throws(HisterError) -> T {
        // Stored page text can carry raw control characters that Hister
        // does not escape, which strict JSON parsers reject. Outside
        // strings they are whitespace anyway (and escaped ones are plain
        // text), so a reply holding any is blanked first: one decode, not
        // a failed one and another.
        let readable = data.contains { $0 < 0x20 } ? Self.blankingControlCharacters(data) : data
        do {
            return try JSONDecoder().decode(T.self, from: readable)
        } catch {
            // A server-side schema change shows up here, with the key
            // path (the error names fields, not page content).
            Self.log.error("\(T.self, privacy: .public) didn't decode: \(DecodeLog.describe(error), privacy: .public)")
            throw .badResponse
        }
    }

    /// In place: one copy of the reply, not a byte array and then another.
    static func blankingControlCharacters(_ data: Data) -> Data {
        var data = data
        data.withUnsafeMutableBytes { bytes in
            for i in bytes.indices where bytes[i] < 0x20 { bytes[i] = 0x20 }
        }
        return data
    }

    func encodeJSON(_ object: [String: any Sendable]) throws(HisterError) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw .badResponse
        }
    }
}

extension URLComponents {
    /// Query items with "+" (and "&", "=", "#") escaped. URLComponents
    /// leaves a "+" as is, and servers read a bare "+" in a query as a
    /// space: that broke paging (Hister's page keys hold "+") and searches
    /// like "c++".
    mutating func setQueryItems(_ items: [URLQueryItem]) {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=#"))
        percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: allowed))
        }
    }
}

extension HisterError {

    /// What a failed request means for the user. A certificate problem is
    /// its own case (not "check Tailscale"); anything else, a name that
    /// doesn't resolve included (MagicDNS with Tailscale off), stays
    /// .unreachable, which the outbox treats as "keep for later". A plain
    /// http:// address is its own case too: the system refused it, so the
    /// fix is the address. The code is logged, so Console can tell the
    /// causes apart.
    public init(transport error: any Error) {
        let code = (error as? URLError)?.code
        HisterClient.log.error("request failed: URLError \(code?.rawValue ?? 0, privacy: .public)")
        switch code {
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
            .serverCertificateHasUnknownRoot, .secureConnectionFailed, .clientCertificateRejected,
            .clientCertificateRequired:
            self = .untrusted
        case .appTransportSecurityRequiresSecureConnection:
            self = .plainHTTP
        default:
            self = .unreachable
        }
    }
}
