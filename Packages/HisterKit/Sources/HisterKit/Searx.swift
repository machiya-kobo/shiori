import Foundation
import os

/// A web result from SearXNG's JSON API.
public struct WebResult: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { url }
    public var url: String
    public var title: String
    public var content: String
    public var engines: [String]
    /// Only a URL on the SearXNG host (its /image_proxy), else nil: the
    /// device never loads images from the engines' own hosts.
    public var thumbnail: URL?
    public var published: Date?

    public init(url: String, title: String, content: String, engines: [String], thumbnail: URL?, published: Date?) {
        self.url = url
        self.title = title
        self.content = content
        self.engines = engines
        self.thumbnail = thumbnail
        self.published = published
    }

    public var host: String { URL(string: url)?.host() ?? url }
}

/// One page of SearXNG results.
public struct WebPage: Sendable, Equatable {
    public var results: [WebResult]
    public var suggestions: [String]
    public var corrections: [String]
}

/// A client for a SearXNG instance's JSON search. No Origin header or auth
/// needed; the network is the gate.
public struct SearxClient: Sendable {
    public let baseURL: URL
    let session: URLSession

    public init?(serverURL: String, session: URLSession = HisterClient.defaultSession) {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        self.baseURL = url
        self.session = session
    }

    public func search(_ query: String, page: Int = 1) async throws(HisterError) -> WebPage {
        var components = URLComponents(url: baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)!
        components.setQueryItems([
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "pageno", value: String(page)),
        ])
        let request = URLRequest(url: components.url!)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw HisterError(transport: error)
        }
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw .server(status: http.statusCode, message: "")
        }
        struct Reply: Decodable {
            struct Result: Decodable {
                var url: String?
                var title: String?
                var content: String?
                var engine: String?
                var engines: [String]?
                var thumbnail: String?
                var thumbnail_src: String?
                var img_src: String?
                var publishedDate: String?
            }
            var results: [Result]?
            var suggestions: [String]?
            var corrections: [String]?
        }
        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            HisterClient.log.error("SearXNG reply didn't decode: \(String(describing: error), privacy: .public)")
            throw .badResponse
        }
        var seen = Set<String>()
        let results = (reply.results ?? []).compactMap { r -> WebResult? in
            guard let url = r.url, url.hasPrefix("http"), seen.insert(url).inserted else { return nil }
            return WebResult(
                url: url,
                title: r.title ?? url,
                content: r.content ?? "",
                engines: r.engines ?? r.engine.map { [$0] } ?? [],
                thumbnail: [r.thumbnail, r.thumbnail_src, r.img_src].lazy.compactMap { self.proxied($0) }.first,
                published: r.publishedDate.flatMap(Self.date))
        }
        return WebPage(results: results, suggestions: reply.suggestions ?? [], corrections: reply.corrections ?? [])
    }

    /// An image URL served by this SearXNG (its image proxy), else nil.
    /// SearXNG writes its image-proxy links for its own configured address,
    /// which can differ from the one used here (a renamed host, or the web
    /// page's path): those are moved onto this address. Still only ever
    /// the image proxy.
    func proxied(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw, relativeTo: baseURL)?.absoluteURL else { return nil }
        if url.scheme == baseURL.scheme && url.host() == baseURL.host() && url.port == baseURL.port { return url }
        guard url.path().hasSuffix("/image_proxy"),
            var components = URLComponents(url: baseURL.appending(path: "image_proxy"), resolvingAgainstBaseURL: false)
        else { return nil }
        components.percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        return components.url
    }

    // Format styles are values: made once, shared, no formatter per result.
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let internet = Date.ISO8601FormatStyle()
    /// SearXNG often omits the time zone: "2026-06-25T03:32:37" (read as UTC).
    private static let zoneless = Date.ISO8601FormatStyle().year().month().day()
        .dateTimeSeparator(.standard).time(includingFractionalSeconds: false)

    static func date(_ raw: String) -> Date? {
        guard raw != "None" else { return nil }
        return (try? Date(raw, strategy: withFraction))
            ?? (try? Date(raw, strategy: internet))
            ?? (try? Date(raw, strategy: zoneless))
    }
}

extension HisterClient {
    /// Which of these URLs Hister has, and their labels ("" = visited, not
    /// kept), in a few searches: url:(a|a/|b|…) in batches short enough to
    /// send (`lookupQueries`). URLs with ( ) | or spaces can't go in the
    /// alternation and are skipped.
    public func savedLabels(for urls: [String]) async -> [String: String] {
        let queries = Self.lookupQueries(urls)
        guard !queries.isEmpty else { return [:] }
        let pages = await withTaskGroup(of: SearchPage?.self) { group in
            for query in queries { group.addTask { try? await search(query, limit: 100) } }
            return await group.reduce(into: [SearchPage]()) { if let page = $1 { $0.append(page) } }
        }
        var labels: [String: String] = [:]
        for d in pages.flatMap(\.documents) {
            labels[d.url] = d.label
            labels[d.url.hasSuffix("/") ? String(d.url.dropLast()) : d.url + "/"] = d.label
        }
        return labels
    }

    /// A query's longest: a proxy in front of Hister (the hosted pages'
    /// nginx) answers 414 past its 8 KB request line, and the query goes
    /// out JSON-wrapped and percent-encoded, about half as long again.
    public static let lookupMax = 2000

    /// `url:(a|a/|b|…)` in batches of at most `max` characters, a URL and
    /// its other form together (one URL longer than that alone is left
    /// out). `S.urlLookupQueries` in search-core.js is the twin.
    public static func lookupQueries(_ urls: [String], max: Int = lookupMax) -> [String] {
        var pairs: [[String]] = []
        var seen = Set<String>()
        for u in urls where !u.isEmpty && u.rangeOfCharacter(from: CharacterSet(charactersIn: "()|\"").union(.whitespacesAndNewlines)) == nil {
            let other = u.hasSuffix("/") ? String(u.dropLast()) : u + "/"
            let fresh = [u, other].filter { seen.insert($0).inserted }
            if !fresh.isEmpty { pairs.append(fresh) }
        }
        func query(_ list: [String]) -> String { "url:(\(list.joined(separator: "|")))" }
        var out: [String] = []
        var batch: [String] = []
        for pair in pairs where query(pair).count <= max {
            if !batch.isEmpty, query(batch + pair).count > max {
                out.append(query(batch))
                batch = []
            }
            batch += pair
        }
        if !batch.isEmpty { out.append(query(batch)) }
        return out
    }
}

extension SearxClient {
    /// What of a search the web can use: the words, without Hister's own
    /// syntax (`label:foo`, `domain:…`, `-label:…`, `added:…`), so a
    /// label search doesn't ask the web for "label:foo" (it matched
    /// unrelated pages). Empty when only syntax is left:
    /// then the web isn't asked. The same rule as search-core.js's webQuery.
    public static func webQuery(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).map(String.init).filter { word in
            word.range(of: #"^(-?(label|added|updated|url|domain|type|language|metadata\.[\w.]+):|@\S+$)"#,
                       options: [.regularExpression, .caseInsensitive]) == nil
        }.joined(separator: " ")
    }
}
