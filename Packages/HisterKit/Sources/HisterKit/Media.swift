import Foundation

// Media (docs/media.md): your libraries (Jellyfin, Plex) and what you played
// (Koito for music, Movary for films), one card per item. Every request is a
// GET to a read endpoint. Private like a work note: never to Hister, a model,
// a cache, an export or a feed. The twin of search-core's media section, on
// scripts/media-cases.json; `MediaClient` (MediaClient.swift) asks the services.

/// The four services, each optional.
public enum MediaService: String, CaseIterable, Sendable, Codable {
    case jellyfin, plex, koito, movary

    public var name: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case .plex: "Plex"
        case .koito: "Koito"
        case .movary: "Movary"
        }
    }

    /// Jellyfin and Plex hold your libraries; Koito and Movary what you played.
    public var isLibrary: Bool { self == .jellyfin || self == .plex }
}

/// What a reply's reader needs: where the service is reached (`api`), its
/// address for links (`link`), and the facts it was asked for once.
public struct MediaContext: Sendable, Equatable {
    public var api: String
    public var link: String
    public var user: String
    public var serverId: String
    public var machine: String

    public init(api: String, link: String? = nil, user: String = "", serverId: String = "", machine: String = "") {
        self.api = api
        self.link = link ?? api
        self.user = user
        self.serverId = serverId
        self.machine = machine
    }
}

/// One thing in a library or a history: a film, show, episode, artist,
/// album, track, music video, collection or playlist.
public struct MediaItem: Sendable, Hashable, Identifiable {
    public struct Episodes: Sendable, Hashable {
        public var watched: Int
        public var total: Int
    }
    public struct Outside: Sendable, Hashable {
        public var name: String
        public var score: String
    }

    public var key = ""
    /// film, show, episode, artist, album, track, video, collection, playlist, other.
    public var kind = ""
    public var title = ""
    public var by = ""
    public var context = ""
    public var year: Int?
    /// tmdb, imdb, tvdb, mbid.
    public var ids: [String: String] = [:]
    public var image = ""
    public var library = ""
    public var added: Int?
    public var inLibrary = false
    /// A search's match that isn't in a library (you played it elsewhere).
    public var elsewhere = false
    /// nil: no one who would know was asked; 0: never played.
    public var plays: Int?
    public var last: Int?
    public var playedFrom = ""
    public var episodes: Episodes?
    /// Yours, 0–10.
    public var rating: Int?
    public var ratingFrom = ""
    public var outside: [Outside] = []
    public var source = ""
    /// A merged card's services, in the order they were asked.
    public var sources: [String] = []
    public var sourceId = ""
    /// Where it opens, by service name.
    public var open: [String: String] = [:]
    /// When you listened or watched (a history list's row).
    public var when: Int?
    public var nowPlaying = false
    public var watchlist = false
    public var rank: Int?

    public init() {}

    public var id: String { key.isEmpty ? "\(source):\(sourceId):\(kind):\(title):\(when ?? 0)" : key }

    /// The item as search-core writes it: empty fields left out.
    public var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        func put(_ k: String, _ v: String) { if !v.isEmpty { d[k] = v } }
        func put(_ k: String, _ v: Int?) { if let v { d[k] = v } }
        func put(_ k: String, _ v: Bool) { if v { d[k] = true } }
        put("key", key)
        put("kind", kind)
        put("title", title)
        put("by", by)
        put("context", context)
        put("year", year)
        if !ids.isEmpty { d["ids"] = ids }
        put("image", image)
        put("library", library)
        put("added", added)
        put("inLibrary", inLibrary)
        put("elsewhere", elsewhere)
        put("plays", plays)
        put("last", last)
        put("playedFrom", playedFrom)
        if let episodes { d["episodes"] = ["watched": episodes.watched, "total": episodes.total] }
        put("rating", rating)
        put("ratingFrom", ratingFrom)
        if !outside.isEmpty { d["outside"] = outside.map { ["name": $0.name, "score": $0.score] } }
        put("source", source)
        if !sources.isEmpty { d["sources"] = sources }
        put("sourceId", sourceId)
        if !open.isEmpty { d["open"] = open }
        put("when", when)
        put("nowPlaying", nowPlaying)
        put("watchlist", watchlist)
        put("rank", rank)
        return d
    }

    /// An item from search-core's form of it (the cases file's).
    init(dictionary d: [String: Any]) {
        let s = { (k: String) in d[k] as? String ?? "" }
        let i = { (k: String) in Media.int(d[k]) }
        let b = { (k: String) in d[k] as? Bool ?? false }
        key = s("key")
        kind = s("kind")
        title = s("title")
        by = s("by")
        context = s("context")
        year = i("year")
        ids = d["ids"] as? [String: String] ?? [:]
        image = s("image")
        library = s("library")
        added = i("added")
        inLibrary = b("inLibrary")
        elsewhere = b("elsewhere")
        plays = i("plays")
        last = i("last")
        playedFrom = s("playedFrom")
        if let e = d["episodes"] as? [String: Any], let w = Media.int(e["watched"]), let t = Media.int(e["total"]) { episodes = .init(watched: w, total: t) }
        rating = i("rating")
        ratingFrom = s("ratingFrom")
        outside = (d["outside"] as? [[String: String]] ?? []).map { .init(name: $0["name"] ?? "", score: $0["score"] ?? "") }
        source = s("source")
        sources = d["sources"] as? [String] ?? []
        sourceId = s("sourceId")
        open = d["open"] as? [String: String] ?? [:]
        when = i("when")
        nowPlaying = b("nowPlaying")
        watchlist = b("watchlist")
        rank = i("rank")
    }
}

/// A request's arguments (search-core's `args`).
public struct MediaArgs: Sendable, Equatable {
    public var q: String?
    public var limit: Int?
    public var kind: String?
    public var period: String?
    public var id: String?
    public var user: String?

    public init(q: String? = nil, limit: Int? = nil, kind: String? = nil, period: String? = nil, id: String? = nil, user: String? = nil) {
        self.q = q
        self.limit = limit
        self.kind = kind
        self.period = period
        self.id = id
        self.user = user
    }
}

public enum Media {
    static let kinds = [
        "film": "Film", "show": "Show", "episode": "Episode", "artist": "Artist", "album": "Album", "track": "Track",
        "video": "Music Video", "collection": "Collection", "playlist": "Playlist", "other": "Video",
    ]
    static let groups = [
        "film": "films", "show": "tv", "episode": "tv", "artist": "music", "album": "music", "track": "music",
        "video": "music", "collection": "other", "playlist": "other", "other": "other",
    ]
    public static let periods = ["week", "month", "year", "all_time"]
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let idKinds = ["tmdb", "imdb", "tvdb", "mbid"]
    static let history = ["film": MediaService.movary, "artist": .koito, "album": .koito, "track": .koito]

    // MARK: Addresses

    /// A service's address with its trailing slash, or "" (an http(s) address, or a path on this host).
    public static func base(_ raw: String?) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.range(of: #"^https?://[^/\s]+"#, options: .regularExpression) != nil
            || s.range(of: #"^/(?!/)"#, options: .regularExpression) != nil
        else { return "" }
        return s.hasSuffix("/") ? s : s + "/"
    }

    /// encodeURIComponent's escaping.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    static func enc(_ v: String) -> String { v.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }

    static func words(_ q: String?) -> String {
        let joined = (q ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let units = Array(joined.utf16.prefix(200))
        return String(decoding: units, as: UTF16.self)
    }

    static func limit(_ n: Int?, _ d: Int) -> Int { max(1, min(100, n ?? d)) }

    /// One read request's address (search-core's `mediaRequestURL`): "" when
    /// the base or a needed argument is missing. Every one is a GET.
    public static func requestURL(_ service: MediaService, _ what: String, base raw: String, args a: MediaArgs = MediaArgs()) -> String {
        let b = base(raw)
        guard !b.isEmpty else { return "" }
        let q = words(a.q)
        let id = (a.id ?? "").range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil ? a.id! : ""
        let user = a.user ?? ""
        func path(_ p: String, _ pairs: [(String, String)] = []) -> String {
            let query = pairs.filter { !$0.1.isEmpty }.map { "\($0.0)=\(enc($0.1))" }.joined(separator: "&")
            return b + p + (query.isEmpty ? "" : "?" + query)
        }
        let topKinds = ["artists", "albums", "tracks"], itemKinds = ["track", "album", "artist"]
        switch (service, what) {
        case (.koito, "search"): return q.isEmpty ? "" : path("apis/web/v1/search", [("q", q)])
        case (.koito, "listens"): return path("apis/web/v1/listens", [("period", "all_time"), ("limit", "\(limit(a.limit, 10))")])
        case (.koito, "nowPlaying"): return path("apis/web/v1/now-playing")
        case (.koito, "top"):
            guard let kind = a.kind, topKinds.contains(kind) else { return "" }
            let period = periods.contains(a.period ?? "") ? a.period! : "month"
            return path("apis/web/v1/top/\(kind)", [("period", period), ("limit", "\(limit(a.limit, 10))")])
        case (.koito, "item"):
            guard let kind = a.kind, itemKinds.contains(kind), !id.isEmpty else { return "" }
            return path("apis/web/v1/\(kind)/\(id)")
        case (.koito, "last"):
            guard let kind = a.kind, itemKinds.contains(kind), !id.isEmpty else { return "" }
            return path("apis/web/v1/listens", [("period", "all_time"), ("limit", "1"), ("\(kind)_id", id)])
        case (.movary, "me"): return path("api/authentication/token")
        case (.movary, "played"):
            return user.isEmpty || q.isEmpty ? "" : path("api/users/\(enc(user))/played/movies", [("search", q), ("limit", "\(limit(a.limit, 30))")])
        case (.movary, "history"):
            return user.isEmpty ? "" : path("api/users/\(enc(user))/history/movies", [("limit", "\(limit(a.limit, 10))"), ("page", "1")])
        case (.movary, "watchlist"):
            return user.isEmpty
                ? "" : path("api/users/\(enc(user))/watchlist/movies", [("limit", "\(limit(a.limit, 10))"), ("sortBy", "addedAt"), ("sortOrder", "desc")])
        case (.jellyfin, "me"): return path("Users/Me")
        case (.jellyfin, "search"):
            return user.isEmpty || q.isEmpty
                ? ""
                : path(
                    "Users/\(enc(user))/Items",
                    [
                        ("searchTerm", q), ("Recursive", "true"), ("Limit", "\(limit(a.limit, 40))"),
                        ("Fields", "ProviderIds,ProductionYear,DateCreated"),
                        ("IncludeItemTypes", "Movie,Series,Episode,MusicArtist,MusicAlbum,Audio,MusicVideo,BoxSet,Playlist,Video,AudioBook"),
                        ("EnableTotalRecordCount", "false"),
                    ])
        case (.jellyfin, "latest"):
            return user.isEmpty
                ? "" : path("Users/\(enc(user))/Items/Latest", [("Limit", "\(limit(a.limit, 10))"), ("Fields", "ProviderIds,ProductionYear,DateCreated")])
        case (.plex, "identity"): return path("identity")
        case (.plex, "search"): return q.isEmpty ? "" : path("hubs/search", [("query", q), ("limit", "\(limit(a.limit, 10))"), ("includeGuids", "1")])
        case (.plex, "recent"):
            return path("library/recentlyAdded", [("X-Plex-Container-Start", "0"), ("X-Plex-Container-Size", "\(limit(a.limit, 10))"), ("includeGuids", "1")])
        default: return ""
        }
    }

    // MARK: Reading replies (never trusting a value to be the type it should be)

    static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber, !isBool(n) {
            let d = n.doubleValue
            guard d.isFinite else { return "" }
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return "\(d)"
        }
        return ""
    }

    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber, !isBool(n) {
            let d = n.doubleValue
            return d.isFinite && abs(d) < 9e15 ? Int(d.rounded(.towardZero)) : nil
        }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.range(of: #"^-?\d+$"#, options: .regularExpression) != nil { return Int(t) }
        }
        return nil
    }

    static func num(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, !isBool(n) { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil { return Double(t) }
        }
        return nil
    }

    static func arr(_ v: Any?) -> [Any] { v as? [Any] ?? [] }
    static func obj(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }

    static func year(_ v: Any?) -> Int? {
        guard let n = int(v), n > 1800, n < 3000 else { return nil }
        return n
    }

    static func unix(_ v: Any?) -> Int? {
        guard let n = int(v), n > 0 else { return nil }
        return n
    }

    static let timePattern = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$"#)

    /// Unix seconds from an ISO time (no zone reads as UTC; fractions
    /// dropped), or from a plain date (noon UTC, so the day reads the same
    /// in every zone).
    static func time(_ v: Any?) -> Int? {
        let s = str(v)
        let ns = s as NSString
        guard let m = timePattern.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let n = (1...6).map { Int(group($0) ?? "0") ?? 0 }
        let (y, mo, d, h, mi, sec) = (n[0], n[1], n[2], n[3], n[4], n[5])
        guard (1...12).contains(mo), (1...31).contains(d), h <= 23, mi <= 59, sec <= 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Day 1 of the month plus the days, as Date.UTC counts (Feb 31 is Mar 3).
        guard let month = calendar.date(from: DateComponents(year: y, month: mo, day: 1)) else { return nil }
        let midnight = Int(month.timeIntervalSince1970) + (d - 1) * 86400
        if group(4) == nil { return midnight + 12 * 3600 }
        var zone = 0
        if let z = group(7), z != "Z" {
            let digits = z.replacingOccurrences(of: ":", with: "")
            let sign = digits.hasPrefix("-") ? -1 : 1
            let hh = Int(digits.dropFirst().prefix(2)) ?? 0, mm = Int(digits.dropFirst(3).prefix(2)) ?? 0
            zone = sign * (hh * 60 + mm)
        }
        return midnight + h * 3600 + mi * 60 + sec - zone * 60
    }

    static func ids(_ pairs: [(String, Any?)]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, raw) in pairs {
            let v = str(raw).lowercased()
            guard !v.isEmpty, out[k] == nil else { continue }
            if k == "imdb", v.range(of: #"^tt\d+$"#, options: .regularExpression) == nil { continue }
            if k == "tmdb" || k == "tvdb", v.range(of: #"^\d+$"#, options: .regularExpression) == nil { continue }
            if k == "mbid", v.range(of: #"^[0-9a-f-]{36}$"#, options: .regularExpression) == nil { continue }
            out[k] = v
        }
        return out
    }

    /// An image on the service's own address (a relative path joined to
    /// `api`), or TMDB's: anything else is dropped.
    public static func imageURL(_ raw: Any?, _ ctx: MediaContext?) -> String {
        let s = str(raw)
        let api = base(ctx?.api)
        guard !s.isEmpty, !api.isEmpty else { return "" }
        if s.range(of: #"^/[^/]"#, options: .regularExpression) != nil { return api + s.dropFirst() }
        if s.range(of: #"^https://image\.tmdb\.org/t/p/[A-Za-z0-9_/.-]+$"#, options: .regularExpression) != nil { return s }
        let link = base(ctx?.link)
        if !link.isEmpty, link.hasPrefix("http"), s.hasPrefix(link) {
            let rest = String(s.dropFirst(link.count))
            if !rest.contains(".."), !rest.contains("?"), !rest.contains("#") { return api + rest }
        }
        return ""
    }

    /// A score to one decimal, halves up ("7.3" for 7.25).
    static func score1(_ n: Double) -> String { String(format: "%.1f", (n * 10).rounded() / 10) }

    static func names(_ list: Any?) -> String {
        arr(list).map { str(obj($0)["name"]) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func koitoItem(_ kind: String, _ raw: Any?, _ ctx: MediaContext?) -> MediaItem {
        let r = obj(raw)
        let id = int(r["id"])
        let link = base(ctx?.link)
        let image = obj(r["image"])
        var it = MediaItem()
        it.kind = kind
        it.title = str(kind == "artist" ? r["name"] : r["title"])
        it.by = kind == "artist" ? "" : names(r["artists"])
        it.ids = ids([("mbid", r["musicbrainz_id"])])
        it.image = imageURL(str(image["medium"]).isEmpty ? image["small"] : image["medium"], ctx)
        it.source = "koito"
        if let id, id != 0 {
            it.sourceId = String(id)
            if !link.isEmpty { it.open = ["koito": "\(link)\(kind)/\(id)"] }
        }
        return it
    }

    static func movaryFilm(_ raw: Any?, _ ctx: MediaContext?) -> MediaItem {
        let m = obj(raw)
        let ids = obj(m["ids"])
        let link = base(ctx?.link)
        let movaryId = int(ids["movary"])
        let tmdb = num(obj(obj(m["externalRatings"])["tmdb"])["average"])
        let rating = int(m["userRating"])
        var it = MediaItem()
        it.kind = "film"
        it.title = str(m["title"])
        it.year = year(String(str(m["releaseDate"]).prefix(4)))
        it.ids = Self.ids([("tmdb", ids["tmdb"]), ("imdb", ids["imdb"])])
        let poster = str(m["posterPath"]).isEmpty && !str(m["tmdbPosterPath"]).isEmpty
            ? "https://image.tmdb.org/t/p/w342" + str(m["tmdbPosterPath"]) : m["posterPath"]
        it.image = imageURL(poster, ctx)
        if let rating, rating > 0, rating <= 10 {
            it.rating = rating
            it.ratingFrom = "movary"
        }
        if let tmdb, tmdb > 0 { it.outside = [.init(name: "TMDB", score: score1(tmdb))] }
        it.source = "movary"
        if let movaryId, movaryId != 0 {
            it.sourceId = String(movaryId)
            if !link.isEmpty, let user = ctx?.user, !user.isEmpty { it.open = ["movary": "\(link)users/\(enc(user))/movies/\(movaryId)"] }
        }
        return it
    }

    static let jellyfinKinds = [
        "Movie": "film", "Series": "show", "Episode": "episode", "MusicArtist": "artist", "MusicAlbum": "album", "Audio": "track",
        "MusicVideo": "video", "BoxSet": "collection", "Playlist": "playlist", "Video": "other", "AudioBook": "other",
    ]
    static let plexKinds = [
        "movie": "film", "show": "show", "episode": "episode", "artist": "artist", "album": "album", "track": "track",
        "clip": "video", "collection": "collection", "playlist": "playlist",
    ]
    static let plexSkip: Set<String> = ["photo", "photoalbum", "actor", "director", "genre", "tag", "place", "autotag", "shared", "season"]

    static func episodeContext(_ season: Any?, _ episode: Any?) -> String {
        [int(season).map { "S\($0)" }, int(episode).map { "E\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    static func isHex32(_ s: String) -> Bool { s.range(of: #"^[0-9a-fA-F]{32}$"#, options: .regularExpression) != nil }

    static func jellyfinItem(_ raw: Any?, _ ctx: MediaContext?) -> MediaItem? {
        let r = obj(raw)
        let id = str(r["Id"])
        guard let kind = jellyfinKinds[str(r["Type"])], isHex32(id) else { return nil }
        let p = obj(r["ProviderIds"])
        let mb: Any? = kind == "album" ? p["MusicBrainzAlbum"] : kind == "artist" ? p["MusicBrainzArtist"] : kind == "track" ? p["MusicBrainzTrack"] : nil
        let tags = obj(r["ImageTags"])
        let api = base(ctx?.api)
        var it = MediaItem()
        if !api.isEmpty, !str(tags["Primary"]).isEmpty {
            it.image = "\(api)Items/\(id)/Images/Primary?tag=\(enc(str(tags["Primary"])))&maxWidth=300"
        } else if !api.isEmpty, kind == "track", isHex32(str(r["AlbumId"])), !str(r["AlbumPrimaryImageTag"]).isEmpty {
            it.image = "\(api)Items/\(str(r["AlbumId"]))/Images/Primary?tag=\(enc(str(r["AlbumPrimaryImageTag"])))&maxWidth=300"
        }
        let link = base(ctx?.link)
        let server = ctx?.serverId ?? ""
        it.kind = kind
        it.title = str(r["Name"])
        if kind == "episode" {
            it.by = str(r["SeriesName"])
        } else if ["album", "track", "video"].contains(kind) {
            let album = str(r["AlbumArtist"])
            it.by = album.isEmpty ? arr(r["Artists"]).map { str($0) }.filter { !$0.isEmpty }.joined(separator: ", ") : album
        }
        it.context = kind == "track" ? str(r["Album"]) : kind == "episode" ? episodeContext(r["ParentIndexNumber"], r["IndexNumber"]) : ""
        it.year = year(r["ProductionYear"])
        it.ids = ids([("tmdb", p["Tmdb"]), ("imdb", p["Imdb"]), ("tvdb", p["Tvdb"]), ("mbid", mb)])
        it.added = time(r["DateCreated"])
        it.inLibrary = true
        it.source = "jellyfin"
        it.sourceId = id
        if !link.isEmpty, !server.isEmpty { it.open = ["jellyfin": "\(link)web/#/details?id=\(id)&serverId=\(enc(server))"] }
        return it
    }

    /// Plex's rating images ("rottentomatoes://image.rating.ripe") to the name shown and the score as it reads there.
    static func plexOutside(_ value: Any?, _ image: Any?) -> MediaItem.Outside? {
        guard let n = num(value), n > 0 else { return nil }
        let img = str(image)
        if img.hasPrefix("imdb://") { return .init(name: "IMDb", score: score1(n)) }
        if img.hasPrefix("themoviedb://") { return .init(name: "TMDB", score: score1(n)) }
        if img.range(of: #"^rottentomatoes://image\.rating\.(ripe|rotten|certified)"#, options: .regularExpression) != nil {
            return .init(name: "RT", score: "\(Int((n * 10).rounded()))%")
        }
        if img.range(of: #"^rottentomatoes://image\.rating\.(upright|spilled)"#, options: .regularExpression) != nil {
            return .init(name: "RT Audience", score: "\(Int((n * 10).rounded()))%")
        }
        return nil
    }

    static func plexItem(_ raw: Any?, _ ctx: MediaContext?) -> MediaItem? {
        let r = obj(raw)
        let key = str(r["ratingKey"])
        guard let kind = plexKinds[str(r["type"])], key.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return nil }
        func guid(_ scheme: String) -> String {
            let g = arr(r["Guid"]).map { str(obj($0)["id"]) }.first { $0.hasPrefix(scheme + "://") }
            return g.map { String($0.dropFirst(scheme.count + 3)) } ?? ""
        }
        let api = base(ctx?.api)
        let thumb = [str(r["thumb"]), str(r["parentThumb"]), str(r["grandparentThumb"])].first { !$0.isEmpty } ?? ""
        let link = base(ctx?.link)
        let machine = ctx?.machine ?? ""
        let rating = num(r["userRating"])
        let show = kind == "show"
        let views = int(show ? r["viewedLeafCount"] : r["viewCount"])
        let played = (views ?? 0) > 0
        var it = MediaItem()
        it.kind = kind
        it.title = str(r["title"])
        it.by = kind == "track" || kind == "episode" ? str(r["grandparentTitle"]) : kind == "album" ? str(r["parentTitle"]) : ""
        it.context = kind == "track" ? str(r["parentTitle"]) : kind == "episode" ? episodeContext(r["parentIndex"], r["index"]) : ""
        it.year = year(r["year"]) ?? (kind == "album" ? year(r["parentYear"]) : nil)
        it.ids = ids([("tmdb", guid("tmdb")), ("imdb", guid("imdb")), ("tvdb", guid("tvdb")), ("mbid", guid("mbid"))])
        if !api.isEmpty, thumb.range(of: #"^/library/metadata/\d+/(thumb|art)/\d+$"#, options: .regularExpression) != nil {
            it.image = api + thumb.dropFirst()
        }
        it.library = str(r["librarySectionTitle"])
        it.added = unix(r["addedAt"])
        it.inLibrary = true
        it.plays = ["collection", "playlist"].contains(kind) ? nil : played ? views : 0
        it.last = played ? unix(r["lastViewedAt"]) : nil
        it.playedFrom = played ? "plex" : ""
        if show, let total = int(r["leafCount"]), total != 0 {
            it.episodes = .init(watched: max(0, int(r["viewedLeafCount"]) ?? 0), total: total)
        }
        if let rating, rating > 0 {
            it.rating = min(10, Int(rating.rounded()))
            it.ratingFrom = "plex"
        }
        it.outside = [plexOutside(r["audienceRating"], r["audienceRatingImage"]), plexOutside(r["rating"], r["ratingImage"])].compactMap { $0 }
        it.source = "plex"
        it.sourceId = key
        if !link.isEmpty, machine.range(of: #"^[0-9a-fA-F]{20,64}$"#, options: .regularExpression) != nil {
            it.open = ["plex": "\(link)web/index.html#!/server/\(machine)/details?key=\(enc("/library/metadata/" + key))"]
        }
        return it
    }

    /// A list reply, read (search-core's `mediaParse` for its lists). What it can't read is left out.
    public static func parse(_ service: MediaService, _ what: String, reply: Any?, ctx: MediaContext?) -> [MediaItem] {
        let r = obj(reply)
        switch (service, what) {
        case (.koito, "search"):
            return (arr(r["tracks"]).map { koitoItem("track", $0, ctx) } + arr(r["albums"]).map { koitoItem("album", $0, ctx) }
                + arr(r["artists"]).map { koitoItem("artist", $0, ctx) })
                .filter { !$0.title.isEmpty && !$0.sourceId.isEmpty }
        case (.koito, "listens"):
            return arr(r["items"]).compactMap { x in
                var it = koitoItem("track", obj(x)["track"], ctx)
                guard !it.title.isEmpty, let when = time(obj(x)["time"]) else { return nil }
                it.when = when
                return it
            }
        case (.koito, "nowPlaying"):
            guard (r["currently_playing"] as? NSNumber).map({ isBool($0) && $0.boolValue }) == true else { return [] }
            var it = koitoItem("track", r["track"], ctx)
            it.nowPlaying = true
            return it.title.isEmpty ? [] : [it]
        case (.koito, "topArtists"), (.koito, "topAlbums"), (.koito, "topTracks"):
            let kind = ["topArtists": "artist", "topAlbums": "album", "topTracks": "track"][what]!
            return arr(r["items"]).compactMap { x in
                var it = koitoItem(kind, obj(x)["item"], ctx)
                guard !it.title.isEmpty else { return nil }
                let plays = int(obj(obj(x)["item"])["listen_count"])
                it.rank = int(obj(x)["rank"])
                if let plays, plays > 0 {
                    it.plays = plays
                    it.playedFrom = "koito"
                }
                return it
            }
        case (.movary, "played"):
            return arr(r["played"]).compactMap { x in
                var it = movaryFilm(obj(x)["movie"], ctx)
                guard !it.title.isEmpty else { return nil }
                let dates = arr(obj(x)["watchDates"])
                let plays = dates.reduce(0) { $0 + max(1, int(obj($1)["plays"]) ?? 1) }
                if plays > 0 {
                    it.plays = plays
                    it.playedFrom = "movary"
                }
                it.last = dates.compactMap { time(obj($0)["date"]) }.max()
                return it
            }
        case (.movary, "history"):
            return arr(r["history"]).compactMap { x in
                var it = movaryFilm(obj(x)["movie"], ctx)
                guard !it.title.isEmpty else { return nil }
                it.when = time(obj(x)["watchedAt"])
                return it
            }
        case (.movary, "watchlist"):
            return arr(r["watchlist"]).compactMap { x in
                let o = obj(x)
                var it = movaryFilm(o["movie"] is [String: Any] ? o["movie"] : x, ctx)
                guard !it.title.isEmpty else { return nil }
                it.watchlist = true
                it.added = time(o["addedAt"])
                return it
            }
        case (.jellyfin, "search"), (.jellyfin, "latest"):
            return ((reply as? [Any]) ?? arr(r["Items"])).compactMap { jellyfinItem($0, ctx) }.filter { !$0.title.isEmpty }
        case (.plex, "search"):
            return arr(obj(r["MediaContainer"])["Hub"]).filter { !plexSkip.contains(str(obj($0)["type"])) }
                .flatMap { arr(obj($0)["Metadata"]) }.compactMap { plexItem($0, ctx) }.filter { !$0.title.isEmpty }
        case (.plex, "recent"):
            return arr(obj(r["MediaContainer"])["Metadata"]).filter { !plexSkip.contains(str(obj($0)["type"])) }
                .compactMap { plexItem($0, ctx) }.filter { !$0.title.isEmpty }
        default:
            return []
        }
    }

    /// The facts replies (search-core's `mediaParse` for the rest):
    /// `koito.item` {plays, first}, `koito.last` {last}, `movary.me` {user},
    /// `jellyfin.me` {user, serverId}, `plex.identity` {machine}.
    public static func parseFacts(_ service: MediaService, _ what: String, reply: Any?) -> [String: Any] {
        let r = obj(reply)
        var out: [String: Any] = [:]
        switch (service, what) {
        case (.koito, "item"):
            if let plays = int(r["listen_count"]), plays >= 0 { out["plays"] = plays }
            if let first = unix(r["first_listen"]) { out["first"] = first }
        case (.koito, "last"):
            if let last = time(obj(arr(r["items"]).first)["time"]) { out["last"] = last }
        case (.movary, "me"):
            let user = str(obj(r["user"])["name"])
            if !user.isEmpty { out["user"] = user }
        case (.jellyfin, "me"):
            let user = str(r["Id"]), server = str(r["ServerId"])
            if isHex32(user) { out["user"] = user }
            if isHex32(server) { out["serverId"] = server }
        case (.plex, "identity"):
            let machine = str(obj(r["MediaContainer"])["machineIdentifier"])
            if machine.range(of: #"^[0-9a-fA-F]{20,64}$"#, options: .regularExpression) != nil { out["machine"] = machine }
        default:
            break
        }
        return out
    }

    // MARK: One card per item

    /// A title or name reduced for matching: no case, accents, punctuation
    /// or spaces; "&" reads as "and".
    public static func norm(_ s: String) -> String {
        let marks: Set<Unicode.GeneralCategory> = [.nonspacingMark, .spacingMark, .enclosingMark]
        let letters: Set<Unicode.GeneralCategory> = [
            .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .decimalNumber, .letterNumber, .otherNumber,
        ]
        var noMarks = String.UnicodeScalarView()
        noMarks.append(contentsOf: s.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !marks.contains($0.properties.generalCategory) })
        let lowered = String(noMarks).lowercased().replacingOccurrences(of: "&", with: " and ")
        var out = String.UnicodeScalarView()
        out.append(contentsOf: lowered.unicodeScalars.filter { letters.contains($0.properties.generalCategory) })
        return String(out)
    }

    /// Whether two items are the same thing: one shared id, or the same
    /// title and artist (or show) and year when neither id disagrees.
    public static func same(_ a: MediaItem, _ b: MediaItem) -> Bool {
        guard a.kind == b.kind else { return false }
        var conflict = false
        for k in idKinds {
            if let x = a.ids[k], let y = b.ids[k] {
                if x == y { return true }
                conflict = true
            }
        }
        if conflict { return false }
        let ta = norm(a.title)
        guard !ta.isEmpty, ta == norm(b.title) else { return false }
        let ba = norm(a.by), bb = norm(b.by)
        if !ba.isEmpty, !bb.isEmpty, ba != bb { return false }
        if let x = a.year, let y = b.year, x != 0, y != 0, x != y { return false }
        return true
    }

    static func relevance(_ item: MediaItem, _ q: String) -> Int {
        let t = norm(item.title), w = norm(q)
        let r = w.isEmpty ? 0 : t == w ? 0 : t.hasPrefix(w) ? 1 : t.contains(w) ? 2 : 3
        return item.kind == "episode" ? 4 + r : r
    }

    /// One card per item (search-core's `mediaMerge`). `lists` are the
    /// services' items, libraries first; `asked` the history services that
    /// were asked. Played comes from Movary (films) or Koito (music) first,
    /// the library's own count where they have nothing; a library item no
    /// one has a play for is "Never Played" (plays 0) when someone who
    /// would know was asked. Ratings: Movary's for films, else Plex's.
    public static func merge(_ lists: [[MediaItem]], q: String = "", asked: Set<MediaService> = []) -> [MediaItem] {
        var groups: [[MediaItem]] = []
        for list in lists {
            for item in list where !item.kind.isEmpty && !item.title.isEmpty {
                if let i = groups.firstIndex(where: { members in
                    !members.contains { $0.source == item.source } && members.contains { same($0, item) }
                }) {
                    groups[i].append(item)
                } else {
                    groups.append([item])
                }
            }
        }
        let merged: [(order: Int, item: MediaItem)] = groups.enumerated().map { order, members in
            func first(_ f: (MediaItem) -> String) -> String { members.map(f).first { !$0.isEmpty } ?? "" }
            let lib = members.first { MediaService(rawValue: $0.source)?.isLibrary == true }
            let head = lib ?? members[0]
            var ids: [String: String] = [:]
            for m in members { for k in idKinds where ids[k] == nil { if let v = m.ids[k] { ids[k] = v } } }
            var open: [String: String] = [:]
            for m in members { open.merge(m.open) { _, new in new } }
            let historyService = history[head.kind]
            let hist = members.first { $0.source == historyService?.rawValue }
            let plex = members.first { $0.source == "plex" }
            var it = MediaItem()
            if let hist, (hist.plays ?? 0) > 0 {
                it.plays = hist.plays
                it.last = hist.last
                it.playedFrom = hist.source
            } else if let plex, (plex.plays ?? 0) > 0 {
                it.plays = plex.plays
                it.last = plex.last
                it.playedFrom = "plex"
            } else if lib != nil, !["collection", "playlist"].contains(head.kind),
                (historyService.map { asked.contains($0) } ?? false) || plex != nil
            {
                it.plays = 0
            } else if lib == nil, let hist, hist.plays == 0 {
                it.plays = 0
            }
            let rated = (head.kind == "film" ? members.first { $0.source == "movary" && ($0.rating ?? 0) != 0 } : nil)
                ?? members.first { $0.source == "plex" && ($0.rating ?? 0) != 0 }
            var outside: [MediaItem.Outside] = []
            for m in members { for o in m.outside where !outside.contains(where: { $0.name == o.name }) && outside.count < 3 { outside.append(o) } }
            let by = head.by.isEmpty ? first(\.by) : head.by
            let year = members.compactMap { $0.year }.first { $0 != 0 }
            let fallback = "\(norm(head.title)):\(norm(first(\.by))):\(year.map(String.init) ?? "")"
            it.key = "\(head.kind):" + (idKinds.compactMap { k in ids[k].map { "\(k):\($0)" } }.first ?? fallback)
            it.kind = head.kind
            it.title = head.title
            it.by = by
            it.context = head.context.isEmpty ? first(\.context) : head.context
            it.year = year
            it.ids = ids
            it.image = (lib.map { $0.image }.flatMap { $0.isEmpty ? nil : $0 }) ?? first(\.image)
            it.library = first(\.library)
            it.added = members.compactMap { $0.added }.first { $0 != 0 }
            it.inLibrary = lib != nil
            it.elsewhere = lib == nil
            // When it was last heard or watched in a history list (a browse's Recently Played).
            it.when = members.compactMap(\.when).max().flatMap { $0 > 0 ? $0 : nil }
            var seen = Set<String>()
            it.sources = members.map(\.source).filter { !$0.isEmpty && seen.insert($0).inserted }
            it.episodes = plex?.episodes
            it.rating = rated?.rating
            it.ratingFrom = rated?.ratingFrom ?? ""
            it.outside = outside
            it.open = open
            return (order, it)
        }
        return merged.sorted { a, b in
            let la = a.item.inLibrary ? 0 : 1, lb = b.item.inLibrary ? 0 : 1
            if la != lb { return la < lb }
            if !q.isEmpty {
                let ra = relevance(a.item, q), rb = relevance(b.item, q)
                if ra != rb { return ra < rb }
            } else {
                let aa = a.item.added ?? 0, ab = b.item.added ?? 0
                if aa != ab { return aa > ab }
            }
            return a.order < b.order
        }.map(\.item)
    }

    // MARK: Filters and what a card says

    /// The Kind filter's group: films, tv, music or other.
    public static func group(_ item: MediaItem) -> String { groups[item.kind] ?? "other" }

    public struct Filter: Sendable, Equatable {
        /// films, tv, music, other.
        public var kind: String?
        /// never (in a library, never played), played, elsewhere (not in a library).
        public var played: String?
        /// loved (4★+), liked (3★+), any, unrated.
        public var rated: String?
        /// week, month, year (last played within it), older (before a year ago).
        public var date: String?
        /// jellyfin, plex, koito, movary.
        public var service: String?
        public init(kind: String? = nil, played: String? = nil, rated: String? = nil, date: String? = nil, service: String? = nil) {
            self.kind = kind
            self.played = played
            self.rated = rated
            self.date = date
            self.service = service
        }
        public var isEmpty: Bool { kind == nil && played == nil && rated == nil && date == nil && service == nil }

        public subscript(key: String) -> String? {
            get {
                switch key {
                case "kind": kind
                case "played": played
                case "rated": rated
                case "date": date
                case "service": service
                default: nil
                }
            }
            set {
                switch key {
                case "kind": kind = newValue
                case "played": played = newValue
                case "rated": rated = newValue
                case "date": date = newValue
                case "service": service = newValue
                default: break
                }
            }
        }
    }

    /// The Filter sheet's sections and their choices (search-core's MEDIA_FILTERS).
    public static let filters: [(key: String, title: String, choices: [(String, String)])] = [
        ("date", "Date", [("week", "Past Week"), ("month", "Past Month"), ("year", "Past Year"), ("older", "Older")]),
        ("kind", "Kind", [("films", "Films"), ("tv", "TV"), ("music", "Music"), ("other", "Other")]),
        ("played", "Played", [("played", "Played"), ("never", "Never Played"), ("elsewhere", "Not in Library")]),
        ("rated", "Rating", [("loved", "4★+"), ("liked", "3★+"), ("any", "Any Rating"), ("unrated", "Unrated")]),
        ("service", "Service", [("jellyfin", "Jellyfin"), ("plex", "Plex"), ("koito", "Koito"), ("movary", "Movary")]),
    ]
    static let dateDays = ["week": 7, "month": 30, "year": 365]

    /// How many items each Filter choice would keep, the other filters held (search-core's `mediaFacets`).
    public static func facets(_ items: [MediaItem], _ f: Filter, now: Int) -> [String: [String: Int]] {
        var out: [String: [String: Int]] = [:]
        for section in filters {
            var counts: [String: Int] = [:]
            for (value, _) in section.choices {
                var g = f
                g[section.key] = value
                counts[value] = filter(items, g, now: now).count
            }
            out[section.key] = counts
        }
        return out
    }

    public static func filter(_ items: [MediaItem], _ f: Filter, now: Int = 0) -> [MediaItem] {
        items.filter { it in
            if let kind = f.kind, group(it) != kind { return false }
            if f.played == "never", !(it.inLibrary && it.plays == 0) { return false }
            if f.played == "played", !((it.plays ?? 0) > 0 || (it.when ?? 0) != 0) { return false }
            if f.played == "elsewhere", !it.elsewhere { return false }
            if let service = f.service, !(it.sources.isEmpty ? [it.source] : it.sources).contains(service) { return false }
            if let date = f.date {
                let at = lastPlayed(it)
                if at == 0 { return false }
                if date == "older" ? now - at <= 365 * 86400 : now - at > (dateDays[date] ?? 0) * 86400 { return false }
            }
            let r = it.rating ?? 0
            switch f.rated {
            case "loved": if r < 8 { return false }
            case "liked": if r < 6 { return false }
            case "any": if r <= 0 { return false }
            case "unrated": if r > 0 { return false }
            default: break
            }
            return true
        }
    }

    /// Sort and Group, as the other pills' (search-core's MEDIA_ORDERS, MEDIA_GROUPINGS).
    public static let orders = [("best", "Best Match"), ("newest", "Newest"), ("oldest", "Oldest"), ("plays", "Most Played"),
                                ("rating", "Top Rated"), ("title", "Title"), ("year", "Year"), ("added", "Recently Added")]
    public static let groupings = [("", "No Groups"), ("day", "Day"), ("month", "Month"), ("kind", "Kind"), ("played", "Played")]
    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// When it was last played (or listened to, watched): 0 when no one knows.
    static func lastPlayed(_ it: MediaItem) -> Int { (it.last ?? 0) != 0 ? it.last! : (it.when ?? 0) }

    /// The items in an order (search-core's `mediaSort`): Best Match keeps
    /// the merge's; Newest and Oldest by when you last played (the never or
    /// unknown after the rest), Most Played, Top Rated (unrated last), Title,
    /// Recently Added. Ties keep their order.
    public static func sort(_ items: [MediaItem], _ order: String) -> [MediaItem] {
        func later(_ f: @escaping (MediaItem) -> Int, desc: Bool) -> (MediaItem, MediaItem) -> Int {
            { a, b in
                let x = f(a), y = f(b)
                if (x == 0) != (y == 0) { return x != 0 ? -1 : 1 }
                return x == y ? 0 : (desc ? (y > x ? 1 : -1) : (x > y ? 1 : -1))
            }
        }
        let cmp: ((MediaItem, MediaItem) -> Int)? =
            switch order {
            case "newest": later(lastPlayed, desc: true)
            case "oldest": later(lastPlayed, desc: false)
            case "plays": later({ $0.plays ?? 0 }, desc: true)
            case "rating": later({ $0.rating ?? 0 }, desc: true)
            case "added": later({ $0.added ?? 0 }, desc: true)
            case "year": later({ $0.year ?? 0 }, desc: true)
            case "title": { a, b in
                let x = norm(a.title), y = norm(b.title)
                return x < y ? -1 : x > y ? 1 : 0
            }
            default: nil
            }
        guard let cmp else { return items }
        return items.enumerated().sorted { a, b in
            let c = cmp(a.element, b.element)
            return c != 0 ? c < 0 : a.offset < b.offset
        }.map(\.element)
    }

    /// The items in groups (search-core's `mediaGroups`), in the order they
    /// first appear: by Kind (Films, TV, Music, Other) or the Month you last
    /// played them ("October 2026"; "Never Played", or "No Date"). No
    /// grouping: one group with no title.
    public static func groups(_ items: [MediaItem], _ grouping: String, offsetMinutes: Int = 0) -> [(title: String, items: [MediaItem])] {
        let titleOf: ((MediaItem) -> String)? =
            switch grouping {
            case "kind": { ["films": "Films", "tv": "TV", "music": "Music", "other": "Other"][group($0)] ?? "Other" }
            case "day": { it in
                let at = lastPlayed(it)
                return at != 0 ? date(at, offsetMinutes: offsetMinutes) : it.plays == 0 ? "Never Played" : "No Date"
            }
            case "played": { it in
                (it.plays ?? 0) > 0 || (it.when ?? 0) != 0 ? "Played" : it.elsewhere ? "Not in Library" : it.plays == 0 ? "Never Played" : "Not Known"
            }
            case "month": { it in
                let at = lastPlayed(it)
                guard at != 0 else { return it.plays == 0 ? "Never Played" : "No Date" }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                let d = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: TimeInterval(at + offsetMinutes * 60)))
                return "\(monthNames[(d.month ?? 1) - 1]) \(d.year ?? 1970)"
            }
            default: nil
            }
        guard let titleOf else { return [("", items)] }
        var out: [(title: String, items: [MediaItem])] = []
        for it in items {
            let title = titleOf(it)
            if let i = out.firstIndex(where: { $0.title == title }) { out[i].items.append(it) } else { out.append((title, [it])) }
        }
        let ranks = ["kind": ["Films", "TV", "Music", "Other"], "played": ["Played", "Never Played", "Not in Library", "Not Known"]]
        if let rank = ranks[grouping] {
            out = out.enumerated().sorted { a, b in
                let x = rank.firstIndex(of: a.element.title) ?? 9, y = rank.firstIndex(of: b.element.title) ?? 9
                return x != y ? x < y : a.offset < b.offset
            }.map(\.element)
        }
        return out
    }

    /// "Mar 6, 2014", at `offsetMinutes` from UTC.
    public static func date(_ secs: Int, offsetMinutes: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let d = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(secs + offsetMinutes * 60)))
        return "\(months[(d.month ?? 1) - 1]) \(d.day ?? 1), \(d.year ?? 1970)"
    }

    /// What a card says about playing it: "Played 3× · Last Mar 6, 2014",
    /// "Played Mar 6, 2014", "Played 8 of 8 Episodes", "Never Played", with
    /// "Not in Library" before it for a search's match that isn't in a library.
    public static func playedLine(_ it: MediaItem, offsetMinutes: Int = 0) -> String {
        if it.nowPlaying { return "Now Playing" }
        if let when = it.when, when != 0 {
            return (groups[it.kind] == "music" ? "Listened " : "Watched ") + date(when, offsetMinutes: offsetMinutes)
        }
        var parts: [String] = []
        if it.elsewhere { parts.append("Not in Library") }
        if let e = it.episodes, e.total != 0 {
            parts.append(e.watched != 0 ? "Played \(e.watched) of \(e.total) Episodes" : "Never Played")
            if e.watched != 0, let last = it.last, last != 0 { parts.append("Last \(date(last, offsetMinutes: offsetMinutes))") }
        } else if let plays = it.plays, plays > 0 {
            if plays == 1, let last = it.last, last != 0 {
                parts.append("Played \(date(last, offsetMinutes: offsetMinutes))")
            } else {
                parts.append("Played \(plays)×")
                if let last = it.last, last != 0 { parts.append("Last \(date(last, offsetMinutes: offsetMinutes))") }
            }
        } else if it.plays == 0 {
            parts.append("Never Played")
        }
        return parts.joined(separator: " · ")
    }

    /// Your rating as five stars with halves ("★★★★½" for 9); "" when unrated.
    public static func stars(_ rating: Double?) -> String {
        let r = Int((rating ?? 0).rounded(.toNearestOrAwayFromZero))
        guard r > 0 else { return "" }
        let n = min(10, r)
        return String(repeating: "★", count: n / 2) + (n % 2 == 1 ? "½" : "")
    }

    /// The others' ratings, quieter: "RT 93% · IMDb 7.8".
    public static func outsideLine(_ it: MediaItem) -> String { it.outside.map { "\($0.name) \($0.score)" }.joined(separator: " · ") }

    /// "Film · 1979", "Track · Artist · Album", "Episode · Show · S1 · E2".
    public static func subtitle(_ it: MediaItem) -> String {
        [kinds[it.kind] ?? "", it.by, it.context, it.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public struct Place: Sendable, Hashable {
        public var key: String
        public var name: String
        public var url: String
    }

    /// Where a card opens and its other places. Koito or Movary first (the
    /// history), then Jellyfin, then Plex; the outside sites (IMDb, TMDB,
    /// Letterboxd, MusicBrainz) are links only, never fetched.
    public static func places(_ it: MediaItem) -> (href: String, places: [Place]) {
        var places: [Place] = []
        for s in [MediaService.koito, .movary, .jellyfin, .plex] {
            if let url = it.open[s.rawValue], url.hasPrefix("http://") || url.hasPrefix("https://") { places.append(.init(key: s.rawValue, name: s.name, url: url)) }
        }
        let film = it.kind == "film" || it.kind == "collection"
        let tv = it.kind == "show" || it.kind == "episode"
        if let imdb = it.ids["imdb"], film || tv { places.append(.init(key: "imdb", name: "IMDb", url: "https://www.imdb.com/title/\(imdb)/")) }
        if let tmdb = it.ids["tmdb"], it.kind == "film" { places.append(.init(key: "tmdb", name: "TMDB", url: "https://www.themoviedb.org/movie/\(tmdb)")) }
        if let tmdb = it.ids["tmdb"], it.kind == "show" { places.append(.init(key: "tmdb", name: "TMDB", url: "https://www.themoviedb.org/tv/\(tmdb)")) }
        if let tmdb = it.ids["tmdb"], it.kind == "film" { places.append(.init(key: "letterboxd", name: "Letterboxd", url: "https://letterboxd.com/tmdb/\(tmdb)/")) }
        let mb = ["artist": "artist", "album": "release", "track": "recording"][it.kind]
        if let mbid = it.ids["mbid"], let mb { places.append(.init(key: "musicbrainz", name: "MusicBrainz", url: "https://musicbrainz.org/\(mb)/\(mbid)")) }
        let own = places.filter { MediaService(rawValue: $0.key) != nil }
        return (own.first?.url ?? "", places)
    }
}
