import Foundation
import Testing

@testable import HisterKit

/// Media, on scripts/media-cases.json: the cases search-core is tested on too.
struct MediaTests {
    nonisolated(unsafe) static let cases: [String: Any] = {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/media-cases.json")
        return (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] ?? [:]
    }()

    static func list(_ key: String) -> [[String: Any]] { cases[key] as? [[String: Any]] ?? [] }

    static func context(_ raw: Any?) -> MediaContext {
        let c = raw as? [String: Any] ?? [:]
        return MediaContext(
            api: c["api"] as? String ?? "", link: c["link"] as? String ?? "", user: c["user"] as? String ?? "",
            serverId: c["serverId"] as? String ?? "", machine: c["machine"] as? String ?? "")
    }

    static func items(_ raw: Any?) -> [MediaItem] { (raw as? [[String: Any]] ?? []).map(MediaItem.init(dictionary:)) }

    /// Equal as JSON: Foundation's numbers and strings compared as search-core wrote them.
    static func same(_ a: Any, _ b: Any) -> Bool { NSArray(array: [a]).isEqual(to: [b]) }

    static func describe(_ v: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .fragmentsAllowed])).map { String(decoding: $0, as: UTF8.self) } ?? "\(v)"
    }

    @Test func eachReadRequestHasItsAddress() throws {
        let cases = Self.list("urls")
        #expect(cases.count > 20)
        for c in cases {
            let service = try #require(MediaService(rawValue: c["service"] as? String ?? ""))
            let a = c["args"] as? [String: Any] ?? [:]
            let args = MediaArgs(
                q: a["q"] as? String, limit: a["limit"] as? Int, kind: a["kind"] as? String, period: a["period"] as? String,
                id: a["id"].map { Media.str($0) }, user: a["user"] as? String)
            let got = Media.requestURL(service, c["what"] as? String ?? "", base: c["base"] as? String ?? "", args: args)
            #expect(got == c["want"] as? String, "\(c["service"]!).\(c["what"]!) \(a)")
        }
    }

    @Test func repliesAreReadAndWhatCantBeReadIsLeftOut() throws {
        for c in Self.list("parse") {
            let service = try #require(MediaService(rawValue: c["service"] as? String ?? ""))
            let what = c["what"] as? String ?? ""
            let got: Any
            if c["want"] is [Any] {
                got = Media.parse(service, what, reply: c["reply"], ctx: Self.context(c["ctx"])).map(\.dictionary)
            } else {
                got = Media.parseFacts(service, what, reply: c["reply"])
            }
            #expect(Self.same(got, c["want"]!), "\(service).\(what): \(Self.describe(got))")
        }
    }

    @Test func oneCardPerItem() {
        for c in Self.list("merge") {
            let lists = (c["lists"] as? [Any] ?? []).map(Self.items)
            let opts = c["opts"] as? [String: Any] ?? [:]
            let asked = Set((opts["asked"] as? [String: Bool] ?? [:]).filter(\.value).keys.compactMap(MediaService.init(rawValue:)))
            let got = Media.merge(lists, q: opts["q"] as? String ?? "", asked: asked).map(\.dictionary)
            #expect(Self.same(got, c["want"]!), "\(opts): \(Self.describe(got))")
        }
    }

    @Test func theFilters() {
        let f = Self.cases["filter"] as? [String: Any] ?? [:]
        let items = Self.items(f["items"])
        for c in f["cases"] as? [[String: Any]] ?? [] {
            let raw = c["filter"] as? [String: String] ?? [:]
            let got = Media.filter(items, .init(kind: raw["kind"], played: raw["played"], rated: raw["rated"])).map(\.key)
            #expect(got == c["want"] as? [String], "\(raw)")
        }
    }

    @Test func whatACardSays() {
        for c in Self.list("lines") {
            let item = MediaItem(dictionary: c["item"] as? [String: Any] ?? [:])
            #expect(Media.playedLine(item, offsetMinutes: c["offset"] as? Int ?? 0) == c["played"] as? String, "\(item.title) \(c["offset"]!)")
        }
        for c in Self.list("text") {
            let item = MediaItem(dictionary: c["item"] as? [String: Any] ?? [:])
            #expect(Media.subtitle(item) == c["subtitle"] as? String, "\(item.title)")
            #expect(Media.outsideLine(item) == c["outside"] as? String, "\(item.title)")
            let want = c["places"] as? [String: Any] ?? [:]
            let got = Media.places(item)
            #expect(got.href == want["href"] as? String, "\(item.title)")
            #expect(got.places.map { ["key": $0.key, "name": $0.name, "url": $0.url] } == want["places"] as? [[String: String]], "\(item.title)")
        }
        for c in Self.list("stars") {
            #expect(Media.stars((c["rating"] as? NSNumber)?.doubleValue) == c["want"] as? String, "\(c["rating"] ?? "nil")")
        }
    }

    @Test func matchingTitlesReducedIdsFirst() {
        for c in Self.list("norm") {
            #expect(Media.norm(c["in"] as? String ?? "") == c["want"] as? String, "\(c["in"]!)")
        }
        for c in Self.list("same") {
            let a = MediaItem(dictionary: c["a"] as? [String: Any] ?? [:]), b = MediaItem(dictionary: c["b"] as? [String: Any] ?? [:])
            #expect(Media.same(a, b) == c["want"] as? Bool, "\(a.title) \(b.title)")
        }
    }

    @Test func imagesOnlyFromTheServiceOrTMDB() {
        for c in Self.list("images") {
            #expect(Media.imageURL(c["raw"], Self.context(c["ctx"])) == c["want"] as? String, "\(c["raw"]!)")
        }
    }
}

/// MediaClient against stubs of the four services, from the cases' replies.
struct MediaClientTests {
    /// Each test its own hosts: the suites run in parallel.
    static func hosts(_ tag: String) -> [MediaService: String] {
        Dictionary(uniqueKeysWithValues: MediaService.allCases.map { ($0, "\($0.rawValue).\(tag).media-client.test") })
    }

    static func reply(_ name: String) -> Data {
        let c = MediaTests.list("parse").first { "\($0["service"]!).\($0["what"]!)" == name }
        return (try? JSONSerialization.data(withJSONObject: c?["reply"] ?? [:])) ?? Data()
    }

    static func client(_ tag: String, failing: [MediaService: Int] = [:]) -> MediaClient {
        let hosts = hosts(tag)
        for (service, host) in hosts {
            StubProtocol.reset(host)
            StubProtocol.handle(host) { request in
                if let status = failing[service] { return (status, Data("{}".utf8)) }
                let path = request.url?.path() ?? ""
                let query = request.url?.query() ?? ""
                let name: String =
                    switch service {
                    case .koito:
                        path.hasSuffix("/search") ? "koito.search"
                            : path.range(of: #"/(track|album|artist)/\d+$"#, options: .regularExpression) != nil ? "koito.item"
                            : path.hasSuffix("/listens") ? (query.contains("_id=") ? "koito.last" : "koito.listens")
                            : path.hasSuffix("/now-playing") ? "koito.nowPlaying" : "koito.topArtists"
                    case .movary:
                        path.hasSuffix("/authentication/token") ? "movary.me"
                            : path.hasSuffix("/played/movies") ? "movary.played"
                            : path.hasSuffix("/history/movies") ? "movary.history" : "movary.watchlist"
                    case .jellyfin: path.hasSuffix("/Users/Me") ? "jellyfin.me" : path.hasSuffix("/Latest") ? "jellyfin.latest" : "jellyfin.search"
                    case .plex: path.hasSuffix("/identity") ? "plex.identity" : path.hasSuffix("/hubs/search") ? "plex.search" : "plex.recent"
                    }
                return (200, reply(name))
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let accounts = Dictionary(uniqueKeysWithValues: hosts.map { ($0.key, MediaAccount(base: "https://\($0.value)/", token: "tok-\($0.key.rawValue)")!) })
        return MediaClient(accounts: accounts, session: URLSession(configuration: config))
    }

    @Test func aSearchAsksEachServiceWithItsOwnTokenAndMerges() async throws {
        let client = Self.client("search")
        let results = await client.search("night")
        #expect(results.failures.isEmpty)
        let top = try #require(results.items.first)
        #expect(top.title == "Night Drive")
        #expect(top.plays == 12)
        #expect(top.playedFrom == "koito")
        #expect(top.last == 1_748_820_600)
        let header = ["koito": ("Authorization", "Token tok-koito"), "movary": ("Authorization", "Bearer tok-movary"),
                      "jellyfin": ("Authorization", "MediaBrowser Token=tok-jellyfin"), "plex": ("X-Plex-Token", "tok-plex")]
        for (service, host) in Self.hosts("search") {
            let requests = StubProtocol.requests(host)
            #expect(!requests.isEmpty, "\(service)")
            for r in requests {
                #expect(r.httpMethod == "GET")
                #expect(r.value(forHTTPHeaderField: header[service.rawValue]!.0) == header[service.rawValue]!.1)
                #expect(r.url?.absoluteString.contains("tok-") == false)
            }
        }
        // Facts are asked once.
        _ = await client.search("night")
        #expect(StubProtocol.requests(Self.hosts("search")[.movary]!).filter { $0.url?.path().hasSuffix("/authentication/token") == true }.count == 1)
    }

    @Test func oneServiceFailingNeverFailsTheSearch() async {
        let results = await Self.client("failing", failing: [.plex: 401, .movary: 503]).search("night")
        #expect(Set(results.failures) == ["Plex refused Shiori's token", "Movary didn't answer"])
        #expect(results.items.contains { $0.title == "Night Drive" })
    }

    @Test func theMediaTabBeforeASearch() async {
        let shelves = await Self.client("browse").browse(period: "year")
        #expect(shelves.failures.isEmpty)
        #expect(shelves.period == "year")
        #expect(shelves.nowPlaying.first?.title == "Night Drive")
        #expect(shelves.artists.first?.plays == 55)
        #expect(shelves.watchlist.first?.title == "Next Film")
        #expect(shelves.added.map(\.title) == ["New Film", "Example Film"])
        #expect(StubProtocol.requests(Self.hosts("browse")[.koito]!).contains { $0.url?.absoluteString.contains("/top/albums?period=year") == true })
    }

    @Test func artOnlyFromTheServicesAndPlexsWithItsTokenInAHeader() async {
        let client = Self.client("images")
        let plexHost = Self.hosts("images")[.plex]!, koitoHost = Self.hosts("images")[.koito]!
        for host in [plexHost, koitoHost] {
            StubProtocol.headers(host, ["Content-Type": "image/webp"])
            StubProtocol.handle(host) { _ in (200, Data("img".utf8)) }
        }
        #expect(await client.imageData("https://\(plexHost)/library/metadata/1/thumb/2") == Data("img".utf8))
        #expect(StubProtocol.requests(plexHost).last?.value(forHTTPHeaderField: "X-Plex-Token") == "tok-plex")
        #expect(StubProtocol.requests(plexHost).last?.url?.absoluteString.contains("tok-") == false)
        #expect(await client.imageData("https://\(koitoHost)/image/x/300.webp") != nil)
        #expect(StubProtocol.requests(koitoHost).last?.value(forHTTPHeaderField: "X-Plex-Token") == nil)
        // Anywhere else: never asked.
        #expect(await client.imageData("https://elsewhere.example/x.jpg") == nil)
        #expect(await client.imageData("javascript:alert(1)") == nil)
        // Not an image: nothing.
        StubProtocol.headers(koitoHost, ["Content-Type": "text/html"])
        #expect(await client.imageData("https://\(koitoHost)/image/x/300.webp") == nil)
    }

    @Test func anAccountNeedsAnAddressAndAToken() {
        #expect(MediaAccount(base: "https://koito.example.ts.net", token: " t ")?.base == "https://koito.example.ts.net/")
        #expect(MediaAccount(base: "https://koito.example.ts.net", token: " ") == nil)
        #expect(MediaAccount(base: "koito.example.ts.net", token: "t") == nil)
        #expect(MediaAccount(base: "/koito/", token: "t") == nil)
    }
}
