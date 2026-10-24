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
    /// Images: the picture itself, through the same image proxy (nil when
    /// SearXNG gave none there), its size and format as the engine says
    /// ("1920 x 1080", "jpeg"), and its own address, read only for a
    /// format its extension names: never loaded.
    public var image: URL?
    public var resolution = ""
    public var imageFormat = ""
    public var imageSource = ""
    /// Videos: the length as SearXNG sends it ("3:45", or seconds).
    public var length: String?

    public init(
        url: String, title: String, content: String, engines: [String], thumbnail: URL?, published: Date?,
        image: URL? = nil, resolution: String = "", imageFormat: String = "", imageSource: String = "", length: String? = nil
    ) {
        self.url = url
        self.title = title
        self.content = content
        self.engines = engines
        self.thumbnail = thumbnail
        self.published = published
        self.image = image
        self.resolution = resolution
        self.imageFormat = imageFormat
        self.imageSource = imageSource
        self.length = length
    }

    public var host: String { URL(string: url)?.host() ?? url }

    /// The picture's own address, to open in the browser (search-core's
    /// `S.originalImage`): the image proxy's `url` when it's proxied, else
    /// the address as given; never anything but the web's schemes.
    public var originalImage: URL? {
        guard let given = SafeHref.url(imageSource) else { return nil }
        guard given.path().hasSuffix("/image_proxy") else { return given }
        return SafeHref.url(URLComponents(url: given, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value)
    }

    /// What Images', Videos' and News' choices read (`WebChoices`).
    public var choiceItem: WebChoices.Item {
        WebChoices.Item(url: url, resolution: resolution, imgFormat: imageFormat, imgSrc: imageSource, length: length, published: published)
    }

    /// What `WebChoices.phrasesFirst` reads for a search's quoted phrases.
    public var phraseFields: (title: String, content: String, url: String, imgSrc: String) {
        (title, content, url, imageSource)
    }
}

/// One page of SearXNG results.
public struct WebPage: Sendable, Equatable {
    public var results: [WebResult]
    public var suggestions: [String]
    public var corrections: [String]
    /// The engines that didn't answer this search (`EngineHealth.names`).
    public var unanswered: [String] = []

    public init(results: [WebResult], suggestions: [String], corrections: [String], unanswered: [String] = []) {
        self.results = results
        self.suggestions = suggestions
        self.corrections = corrections
        self.unanswered = unanswered
    }
}

/// The web engines that didn't answer a SearXNG search, from its reply's
/// `unresponsive_engines` (`[[name, reason], …]`, or plain names). Twin of
/// search-core's `S.unansweredEngines` / `S.engineHealthLine`, on
/// scripts/engine-health-cases.json.
public enum EngineHealth {
    /// One entry of `unresponsive_engines`, whatever its shape: never
    /// fails, so an odd entry can't sink the reply.
    struct Entry: Decodable {
        var name: String?

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
                name = text
            } else if var list = try? decoder.unkeyedContainer(), !list.isAtEnd {
                name = try? list.decode(String.self)
            }
        }
    }

    /// A reply's field on its own, for reading it apart from the results.
    struct Field: Decodable {
        var entries: [Entry]?

        enum CodingKeys: String, CodingKey { case entries = "unresponsive_engines" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entries = try? c.decodeIfPresent([Entry].self, forKey: .entries)
        }
    }

    /// Each name once, in order, blanks left out.
    static func names(_ entries: [Entry]) -> [String] {
        var names: [String] = []
        for entry in entries {
            let name = (entry.name ?? "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// The names from a whole SearXNG reply.
    public static func names(inReply data: Data) -> [String] {
        names((try? JSONDecoder().decode(Field.self, from: data))?.entries ?? [])
    }

    /// The line above the web's results: "No answer from alpha, beta", or "".
    public static func line(_ names: [String]) -> String {
        names.isEmpty ? "" : "No answer from \(names.joined(separator: ", "))"
    }
}

/// A client for a SearXNG instance's JSON search. No Origin header or auth
/// needed; the network is the gate.
public struct SearxClient: Sendable {
    public let baseURL: URL
    let session: URLSession
    /// "off" (SearXNG's own setting, nothing sent), "moderate" or "strict".
    public var safeSearch = "off"

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

    /// SearXNG's `safesearch` for a choice: "1" moderate, "2" strict; nil
    /// for off (or anything else), so SearXNG's own setting holds. Twin of
    /// search-core's `S.safeSearchLevel`, on scripts/web-choices-cases.json.
    public static func safeSearchLevel(_ choice: String) -> String? {
        switch choice {
        case "moderate": "1"
        case "strict": "2"
        default: nil
        }
    }

    /// One page of `category`'s results (SearXNG's own: images, videos,
    /// news; nil for its general search).
    public func search(_ query: String, page: Int = 1, category: String? = nil) async throws(HisterError) -> WebPage {
        var components = URLComponents(url: baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "pageno", value: String(page)),
        ]
        if let category { items.append(URLQueryItem(name: "categories", value: category)) }
        if let level = Self.safeSearchLevel(safeSearch) { items.append(URLQueryItem(name: "safesearch", value: level)) }
        components.setQueryItems(items)
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
                var resolution: String?
                var img_format: String?
                /// A string ("3:45") or seconds, depending on the engine.
                var length: Loose?
            }
            /// A string or a number, read as text; anything else as nothing.
            struct Loose: Decodable {
                var text: String?
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let s = try? c.decode(String.self) { text = s }
                    else if let n = try? c.decode(Double.self) { text = n == n.rounded() ? String(Int(n)) : String(n) }
                }
            }
            /// One result that doesn't read is skipped, not the page.
            var results: Lenient<Result>?
            var suggestions: [String]?
            var corrections: [String]?
            /// Read here with the rest: the reply is decoded once.
            var health: EngineHealth.Field

            private enum Keys: String, CodingKey { case results, suggestions, corrections }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                results = try c.decodeIfPresent(Lenient<Result>.self, forKey: .results)
                suggestions = try? c.decodeIfPresent([String].self, forKey: .suggestions)
                corrections = try? c.decodeIfPresent([String].self, forKey: .corrections)
                health = try EngineHealth.Field(from: decoder)
            }
        }
        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            HisterClient.log.error("SearXNG reply didn't decode: \(DecodeLog.describe(error), privacy: .public)")
            throw .badResponse
        }
        var seen = Set<String>()
        let results = (reply.results?.elements ?? []).compactMap { r -> WebResult? in
            guard let url = r.url, url.hasPrefix("http"), seen.insert(url).inserted else { return nil }
            return WebResult(
                url: url,
                title: r.title ?? url,
                content: r.content ?? "",
                engines: r.engines ?? r.engine.map { [$0] } ?? [],
                thumbnail: [r.thumbnail, r.thumbnail_src, r.img_src].lazy.compactMap { self.proxied($0) }.first,
                published: r.publishedDate.flatMap(Self.date),
                image: self.proxied(r.img_src),
                resolution: r.resolution ?? "",
                imageFormat: r.img_format ?? "",
                imageSource: r.img_src ?? "",
                length: r.length?.text)
        }
        return WebPage(
            results: results, suggestions: reply.suggestions ?? [], corrections: reply.corrections ?? [],
            unanswered: EngineHealth.names(reply.health.entries ?? []))
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
    /// Best effort (a failed search marks nothing): for marks on results,
    /// never for deciding whether to save (`heldLabels`).
    public func savedLabels(for urls: [String]) async -> [String: String] {
        let queries = Self.lookupQueries(urls)
        guard !queries.isEmpty else { return [:] }
        let pages = await withTaskGroup(of: SearchPage?.self) { group in
            for query in queries { group.addTask { try? await search(query, limit: 100) } }
            return await group.reduce(into: [SearchPage]()) { if let page = $1 { $0.append(page) } }
        }
        return Self.labels(in: pages)
    }

    /// The same, but a search that fails throws rather than reading as
    /// "not held" (`api/add` would replace a stored page's metadata). URLs
    /// `lookupQueries` can't take are left out: ask `holds` for those.
    public func heldLabels(for urls: [String]) async throws(HisterError) -> [String: String] {
        let queries = Self.lookupQueries(urls)
        guard !queries.isEmpty else { return [:] }
        do {
            let pages = try await withThrowingTaskGroup(of: SearchPage.self) { group in
                for query in queries { group.addTask { try await search(query, limit: 100) } }
                return try await group.reduce(into: [SearchPage]()) { $0.append($1) }
            }
            return Self.labels(in: pages)
        } catch let error as HisterError {
            throw error
        } catch {
            throw .cancelled
        }
    }

    private static func labels(in pages: [SearchPage]) -> [String: String] {
        var labels: [String: String] = [:]
        for d in pages.flatMap(\.documents) {
            labels[d.url] = d.label
            labels[d.url.hasSuffix("/") ? String(d.url.dropLast()) : d.url + "/"] = d.label
        }
        return labels
    }

    /// Whether `lookupQueries` can put this URL in a search.
    public static func lookupTakes(_ url: String) -> Bool {
        !url.isEmpty && url.rangeOfCharacter(from: CharacterSet(charactersIn: "()|\"").union(.whitespacesAndNewlines)) == nil
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
        for u in urls where lookupTakes(u) {
            let other = u.hasSuffix("/") ? String(u.dropLast()) : u + "/"
            let fresh = [u, other].filter { seen.insert($0).inserted }
            if !fresh.isEmpty { pairs.append(fresh) }
        }
        func query(_ list: [String]) -> String { "url:(\(list.joined(separator: "|")))" }
        // Lengths kept as it goes, not each batch joined again per URL:
        // "url:(" and ")" are 6, and each "|" one.
        func length(_ list: [String]) -> Int { list.reduce(list.count - 1) { $0 + $1.count } }
        var out: [String] = []
        var batch: [String] = []
        var batchLength = 0
        for pair in pairs {
            let pairLength = length(pair)
            guard 6 + pairLength <= max else { continue }
            if !batch.isEmpty, 6 + batchLength + 1 + pairLength > max {
                out.append(query(batch))
                batch = []
                batchLength = 0
            }
            batchLength += (batch.isEmpty ? 0 : 1) + pairLength
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
            histerSyntax.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)) == nil
        }.joined(separator: " ")
    }

    /// Compiled once, not per word of every search.
    private static let histerSyntax = try! NSRegularExpression(
        pattern: #"^(-?(label|added|updated|url|domain|type|language|metadata\.[\w.]+):|@\S+$)"#, options: .caseInsensitive)
}
