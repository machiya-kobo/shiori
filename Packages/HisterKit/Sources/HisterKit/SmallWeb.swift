import Foundation

/// Gemini and Gopher search through a small-web gateway
/// (docs/smallweb.md):
/// TLGS, Kennedy and Veronica-2, one engine failing never failing the
/// search. Asked only when a search is submitted, never while typing
/// (the contract, and politeness to volunteer engines).
public struct SmallWebClient: Sendable {
    let http: HisterClient

    /// Nil unless `serverURL` is an absolute http(s) address.
    public init?(serverURL: String, session: URLSession = HisterClient.defaultSession) {
        guard let http = HisterClient(serverURL: serverURL, session: session) else { return nil }
        self.http = http
    }

    public var baseURL: URL { http.baseURL }

    /// One page of results (page n of each engine's own paging).
    public func search(_ text: String, page: Int = 1) async throws(HisterError) -> SmallWebPage {
        let q = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !q.isEmpty else { return SmallWebPage(results: [], engines: [:], errors: [:]) }
        let request = http.makeRequest(
            "api/search",
            query: [URLQueryItem(name: "q", value: String(q.prefix(300))), URLQueryItem(name: "page", value: String(max(1, min(page, 50))))],
            accept: "application/json")
        return try http.decode(await http.send(request))
    }

    /// Asks the gateway to fetch and save a page opened directly in a
    /// Gemini app (it never passes through the gateway then). Best effort:
    /// the gateway answers 202 at once and saves in the background, under
    /// the same rules as a page read through it. `Origin: hister://` is
    /// what it accepts from the native apps.
    /// The answer is `202 {"queued": true, "url": "<canonical>"}`: the URL
    /// Hister will hold the page under, returned (else the one asked for).
    /// 429 when 20 saves already wait; 400 for any other scheme.
    @discardableResult
    public func save(_ url: String) async throws(HisterError) -> String {
        struct Reply: Decodable { var url: String? }
        let body = try http.encodeJSON(["url": url])
        let data = try await http.send(http.makeRequest("api/save", method: "POST", body: body))
        return (try? JSONDecoder().decode(Reply.self, from: data))?.url.flatMap { $0.isEmpty ? nil : $0 } ?? url
    }
}

/// A page of the gateway's results.
public struct SmallWebPage: Sendable, Equatable, Decodable {
    public var results: [SmallWebResult]
    /// Per engine: whether it answered, and whether it has a next page.
    public var engines: [String: Engine]
    /// The engines that failed, and why ("timeout", "rate-limited", …).
    public var errors: [String: String]

    public struct Engine: Sendable, Equatable, Decodable {
        public var ok: Bool
        public var next: Bool
        public var total: Int?
        public init(ok: Bool, next: Bool, total: Int? = nil) {
            self.ok = ok
            self.next = next
            self.total = total
        }
    }

    public init(results: [SmallWebResult], engines: [String: Engine], errors: [String: String]) {
        self.results = results
        self.engines = engines
        self.errors = errors
    }

    /// Some engine has a next page.
    public var hasMore: Bool { engines.values.contains { $0.ok && $0.next } }

    /// The engines that failed, by their names ("Veronica-2 timed out").
    public var failures: [String] {
        errors.keys.sorted().map { key in
            let name = SmallWebResult.engineName(key)
            return switch errors[key] ?? "" {
            case "timeout": "\(name) timed out"
            case "rate-limited", "slow-down": "\(name) asked to slow down"
            case "unreachable": "\(name) couldn't be reached"
            default: "\(name) didn't answer"
            }
        }
    }

    private enum Keys: String, CodingKey { case results, sources, errors }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        // One result the app can't read is left out, not the page.
        results = ((try? c.decodeIfPresent([Lossy<SmallWebResult>].self, forKey: .results)) ?? nil)?.compactMap(\.value) ?? []
        engines = (try? c.decodeIfPresent([String: Engine].self, forKey: .sources)) ?? [:]
        errors = (try? c.decodeIfPresent([String: String].self, forKey: .errors)) ?? [:]
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

/// One Gemini or Gopher result.
public struct SmallWebResult: Sendable, Hashable, Identifiable, Decodable {
    public var id: String { url }
    /// The canonical address (`gemini://…`, `gopher://…`): what Hister keeps
    /// and what a Gemini app such as Lagrange opens.
    public var url: String
    public var title: String
    /// The gateway's HTML rendering, for a browser.
    public var proxyURL: String
    /// Plain text; `marks` are [start, end) offsets of the matched words, in
    /// Unicode scalars (the gateway is Python).
    public var snippet: String
    public var marks: [[Int]]
    public var source: String
    public var sources: [String]
    /// "gemini" or "gopher".
    public var scheme: String
    public var kind: String?
    public var size: String?

    public init(
        url: String, title: String, proxyURL: String, snippet: String = "", marks: [[Int]] = [],
        source: String = "", sources: [String] = [], scheme: String = "gemini", kind: String? = nil, size: String? = nil
    ) {
        self.url = url
        self.title = title
        self.proxyURL = proxyURL
        self.snippet = snippet
        self.marks = marks
        self.source = source
        self.sources = sources
        self.scheme = scheme
        self.kind = kind
        self.size = size
    }

    private enum Keys: String, CodingKey {
        case url, title, snippet, marks, source, sources, scheme, kind, size
        case proxyURL = "proxy_url"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        url = try c.decode(String.self, forKey: .url)
        proxyURL = try c.decode(String.self, forKey: .proxyURL)
        guard url.hasPrefix("gemini://") || url.hasPrefix("gopher://"),
            proxyURL.hasPrefix("https://") || proxyURL.hasPrefix("http://")
        else { throw DecodingError.dataCorruptedError(forKey: .url, in: c, debugDescription: "not a small-web result") }
        let rawTitle = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        title = rawTitle.isEmpty ? url : rawTitle
        snippet = try c.decodeIfPresent(String.self, forKey: .snippet) ?? ""
        marks = (try? c.decodeIfPresent([[Int]].self, forKey: .marks)) ?? []
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        sources = (try? c.decodeIfPresent([String].self, forKey: .sources)) ?? []
        scheme = try c.decodeIfPresent(String.self, forKey: .scheme) ?? (url.hasPrefix("gopher://") ? "gopher" : "gemini")
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        size = try? c.decodeIfPresent(String.self, forKey: .size)
    }

    /// The snippet in runs, the marked ones true. Offsets out of range or
    /// overlapping are skipped, never trusted.
    public var snippetRuns: [(text: String, marked: Bool)] {
        let scalars = Array(snippet.unicodeScalars)
        var runs: [(String, Bool)] = []
        var at = 0
        func text(_ range: Range<Int>) -> String {
            var s = String.UnicodeScalarView()
            s.append(contentsOf: scalars[range])
            return String(s)
        }
        for mark in marks.sorted(by: { ($0.first ?? 0) < ($1.first ?? 0) }) {
            guard mark.count == 2, mark[0] >= at, mark[0] < mark[1], mark[1] <= scalars.count else { continue }
            if mark[0] > at { runs.append((text(at..<mark[0]), false)) }
            runs.append((text(mark[0]..<mark[1]), true))
            at = mark[1]
        }
        if at < scalars.count { runs.append((text(at..<scalars.count), false)) }
        return runs
    }

    /// The canonical address without its scheme, for a row's second line.
    public var place: String {
        url.replacingOccurrences(of: #"^(gemini|gopher)://"#, with: "", options: .regularExpression)
    }

    /// "TLGS · Kennedy": the engines that found it.
    public var engineNames: String {
        (sources.isEmpty ? [source] : sources).filter { !$0.isEmpty }.map(Self.engineName).joined(separator: " · ")
    }

    static func engineName(_ key: String) -> String {
        switch key {
        case "tlgs": "TLGS"
        case "kennedy": "Kennedy"
        case "veronica": "Veronica-2"
        default: key
        }
    }
}
