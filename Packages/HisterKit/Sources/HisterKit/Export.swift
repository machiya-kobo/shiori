import Foundation

/// Results written out as a file: JSON (Hister's own import format, so an
/// export can go into `hister import`), CSV for spreadsheets, and RSS.
/// Plus the feed addresses NewsBlur subscribes to, and OPML to subscribe
/// to many at once.
public enum Export {
    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case json, csv, rss
        public var id: Self { self }
        public var fileExtension: String { rawValue }
        public var title: String {
            switch self {
            case .json: "JSON"
            case .csv: "CSV"
            case .rss: "RSS"
            }
        }
    }

    public static func data(_ pages: [StoredPage], as format: Format, title: String, link: URL? = nil) -> Data {
        switch format {
        case .json: json(pages)
        case .csv: Data(csv(pages).utf8)
        case .rss: Data(rss(pages, title: title, link: link).utf8)
        }
    }

    /// A file name for `title`: letters, digits and dashes.
    public static func fileName(_ title: String, format: Format) -> String {
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { s, c in if !(c == "-" && s.hasSuffix("-")) { s.append(c) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "shiori-\(slug.isEmpty ? "results" : String(slug.prefix(60))).\(format.fileExtension)"
    }

    // MARK: JSON

    static func json(_ pages: [StoredPage]) -> Data {
        struct Row: Encodable {
            var url, title, domain, label: String
            var added, updated: Int
        }
        let rows = pages.map {
            Row(url: $0.url, title: $0.title, domain: $0.domain, label: $0.label,
                added: max(0, Int($0.added.timeIntervalSince1970)), updated: max(0, Int($0.updated.timeIntervalSince1970)))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(rows)) ?? Data("[]".utf8)
    }

    // MARK: CSV

    static func csv(_ pages: [StoredPage]) -> String {
        var lines = ["url,title,domain,label,added,updated"]
        for page in pages {
            lines.append([
                page.url, page.title, page.domain, page.label,
                iso(page.added), iso(page.updated),
            ].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quoted when it holds a comma, quote or line break (RFC 4180). A
    /// leading = + - @ is prefixed with ' so a spreadsheet doesn't run it.
    static func csvField(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: RSS

    static func rss(_ pages: [StoredPage], title: String, link: URL?) -> String {
        var out = """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel>
            <title>\(xml("Shiori – " + title))</title>
            <link>\(xml(link?.absoluteString ?? ""))</link>
            <description>\(xml("Hister pages for " + title))</description>

            """
        for page in pages {
            out += "<item><title>\(xml(page.displayTitle))</title><link>\(xml(page.url))</link>"
            out += "<guid isPermaLink=\"true\">\(xml(page.url))</guid>"
            if page.added > .distantPast { out += "<pubDate>\(rfc822(page.added))</pubDate>" }
            if !page.label.isEmpty { out += "<category>\(xml(page.label))</category>" }
            let text = page.snippet.plainText
            if !text.isEmpty { out += "<description>\(xml(String(text.prefix(500))))</description>" }
            out += "</item>\n"
        }
        return out + "</channel></rss>\n"
    }

    // MARK: Feeds

    /// The feed of a Hister query, served beside Hister by a feed
    /// service (`/shiori/feed`).
    /// `excludeLabel`: items with this label left out, by the service
    /// (Hister's `-label:` finds nothing): Library → Pages leaves out notes.
    public static func feedURL(base: URL, query: String, title: String? = nil, excludeLabel: String? = nil) -> URL {
        var components = URLComponents(url: base.appending(path: "shiori/feed"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "q", value: query)]
        if let excludeLabel { items.append(URLQueryItem(name: "exclude_label", value: excludeLabel)) }
        if let title, !title.isEmpty, title != query { items.append(URLQueryItem(name: "title", value: title)) }
        components.setQueryItems(items)
        return components.url!
    }

    /// NewsBlur's "add site" page for a feed, on the user's NewsBlur.
    public static func newsBlurSubscribeURL(newsBlur: String, feed: URL) -> URL? {
        let base = newsBlur.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base.hasSuffix("/") ? base : base + "/"),
            components.scheme == "https" || components.scheme == "http", components.host != nil
        else { return nil }
        components.path = (components.path.hasSuffix("/") ? components.path : components.path + "/")
        components.setQueryItems([URLQueryItem(name: "url", value: feed.absoluteString)])
        return components.url
    }

    /// Many feeds in one file, for NewsBlur's Import (Settings → Import/Export).
    public static func opml(title: String, feeds: [(title: String, url: URL)]) -> Data {
        var out = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0"><head><title>\(xml(title))</title></head><body>
            <outline text="\(xml(title))" title="\(xml(title))">

            """
        for feed in feeds {
            out += "<outline type=\"rss\" text=\"\(xml(feed.title))\" title=\"\(xml(feed.title))\" xmlUrl=\"\(xml(feed.url.absoluteString))\"/>\n"
        }
        out += "</outline></body></opml>\n"
        return Data(out.utf8)
    }

    // MARK: Plumbing

    static func xml(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            // XML 1.0 forbids most control characters, even escaped.
            case _ where scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r": continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Empty for no date (`.distantPast`).
    static func iso(_ date: Date) -> String {
        date > .distantPast ? date.formatted(.iso8601) : ""
    }

    static func rfc822(_ date: Date) -> String {
        rfc822Style.format(date)
    }

    private static let rfc822Style = Date.VerbatimFormatStyle(
        format: "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) +0000",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(identifier: "UTC")!,
        calendar: Calendar(identifier: .gregorian))
}
