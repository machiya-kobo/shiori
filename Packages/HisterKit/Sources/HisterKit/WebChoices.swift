import Foundation

/// Images, Videos and News: their own row of choices (an order and
/// filters, as Kagi's), drawn from the results SearXNG already sent. A
/// choice narrows or reorders them in place; the web is never asked again
/// for it (each search counts). A filter shows only when the results differ
/// in it. Twin of search-core's `S.webChoices` / `S.webNarrow` /
/// `S.webChoiceRow`, on scripts/web-choices-cases.json.
public enum WebChoices {
    /// What a choice reads from a result: SearXNG's fields as it sent them.
    public struct Item: Sendable, Equatable, Hashable {
        public var url: String
        /// "1920 x 1080", when the engine says.
        public var resolution: String
        /// "jpeg", or a line such as "JPEG 800×600".
        public var imgFormat: String
        /// The picture's own address (its extension can name the format).
        public var imgSrc: String
        /// A video's length: "3:45", "1:02:10" or seconds.
        public var length: String?
        public var published: Date?

        public init(url: String, resolution: String = "", imgFormat: String = "", imgSrc: String = "", length: String? = nil, published: Date? = nil) {
            self.url = url
            self.resolution = resolution
            self.imgFormat = imgFormat
            self.imgSrc = imgSrc
            self.length = length
            self.published = published
        }
    }

    /// The choices made: the order ("" for SearXNG's own) and each filter's value ("" for any).
    public struct Choices: Sendable, Equatable, Hashable {
        public var order = ""
        public var filters: [String: String] = [:]

        public init(order: String = "", filters: [String: String] = [:]) {
            self.order = order
            self.filters = filters
        }

        public subscript(key: String) -> String {
            get { key == "order" ? order : filters[key] ?? "" }
            set { if key == "order" { order = newValue } else { filters[key] = newValue } }
        }
    }

    /// One menu in the row: its key, its name, and its choices, `value` "" for any.
    public struct Menu: Sendable, Equatable, Identifiable {
        public struct Option: Sendable, Equatable, Hashable {
            public var value: String
            public var label: String
        }

        public var id: String { key }
        public var key: String
        public var name: String
        public var options: [Option]
    }

    static let orders: [String: [(String, String)]] = [
        "images": [("", "Best Match"), ("largest", "Largest")],
        "videos": [("", "Best Match"), ("newest", "Newest"), ("shortest", "Shortest"), ("longest", "Longest")],
        "news": [("", "Best Match"), ("newest", "Newest")],
    ]

    /// [key, the menu's name, its "any" choice, the choices (nil: the results' own values)]
    static let filters: [String: [(key: String, name: String, any: String, fixed: [(String, String)]?)]] = [
        "images": [
            ("size", "Size", "Any Size", [("large", "Large"), ("medium", "Medium"), ("small", "Small")]),
            ("shape", "Shape", "Any Shape", [("wide", "Wide"), ("square", "Square"), ("tall", "Tall")]),
            ("format", "Format", "Any Format", [("jpeg", "JPEG"), ("png", "PNG"), ("gif", "GIF"), ("webp", "WebP"), ("svg", "SVG"), ("avif", "AVIF")]),
        ],
        "videos": [
            ("length", "Length", "Any Length", [("short", "Under 4 Min"), ("medium", "4–20 Min"), ("long", "Over 20 Min")]),
            ("source", "Source", "All Sources", nil),
        ],
        "news": [("source", "Source", "All Sources", nil)],
    ]

    static let keys = ["size": "ws", "shape": "wa", "format": "wf", "length": "wl", "source": "we"]

    /// A picture's size, from SearXNG's `resolution` or its format line; nil when unknown.
    public static func imageSize(resolution: String, imgFormat: String) -> (w: Int, h: Int)? {
        for text in [resolution, imgFormat] {
            guard let m = text.firstMatch(of: /(\d{2,5})\s*[x×X]\s*(\d{2,5})/), let w = Int(m.1), let h = Int(m.2) else { continue }
            return (w, h)
        }
        return nil
    }

    /// A video's length in seconds ("3:45", "1:02:10" or seconds), or nil.
    public static func lengthSeconds(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty, raw != "None" else { return nil }
        if raw.contains(":") {
            var total = 0.0
            for part in raw.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false) {
                let piece = part.trimmingCharacters(in: .whitespaces)
                // As JavaScript's Number(): "" is 0, anything else not a number spoils the lot.
                guard let n = piece.isEmpty ? 0 : Double(piece), n.isFinite else { return nil }
                total = total * 60 + n
            }
            return Int(total)
        }
        guard let n = Double(raw.trimmingCharacters(in: .whitespaces)), n.isFinite else { return nil }
        let rounded = Int(n.rounded())
        return rounded > 0 ? rounded : nil
    }

    /// What an item is under one of the choices (a picture's size, a video's length…), or "" when unknown.
    public static func value(_ key: String, _ item: Item) -> String {
        switch key {
        case "size", "shape":
            guard let size = imageSize(resolution: item.resolution, imgFormat: item.imgFormat), size.w > 0, size.h > 0 else { return "" }
            if key == "size" {
                let side = max(size.w, size.h)
                return side >= 1200 ? "large" : side >= 500 ? "medium" : "small"
            }
            let ratio = Double(size.w) / Double(size.h)
            return ratio >= 1.2 ? "wide" : ratio <= 0.83 ? "tall" : "square"
        case "format":
            let path = item.imgSrc.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
            // JavaScript's \b (a word character beside a non-word one): Unicode's default treats "b.jpg" as one word.
            let format = /(?i)\b(jpe?g|png|gif|webp|svg|avif)\b/.wordBoundaryKind(.simple)
            guard let m = "\(item.imgFormat) \(path)".firstMatch(of: format) else { return "" }
            let found = m.1.lowercased()
            return found == "jpg" ? "jpeg" : found
        case "length":
            guard let seconds = lengthSeconds(item.length) else { return "" }
            return seconds < 240 ? "short" : seconds <= 1200 ? "medium" : "long"
        case "source":
            guard let host = URL(string: item.url)?.host()?.lowercased() else { return "" }
            return host.replacing(/^(www|m)\./, with: "")
        default:
            return ""
        }
    }

    /// The tab's choices from its kept values (the web pages' address: `wo`, `ws`…).
    public static func choices(_ category: String, params: [String: String]) -> Choices {
        var out = Choices()
        let order = params["wo"] ?? ""
        if (orders[category] ?? []).contains(where: { $0.0 == order }) { out.order = order }
        for filter in filters[category] ?? [] {
            out.filters[filter.key] = params[keys[filter.key] ?? ""] ?? ""
        }
        return out
    }

    /// The address's key for one of the choices ("order" is wo).
    public static func choiceKey(_ key: String) -> String {
        key == "order" ? "wo" : keys[key] ?? ""
    }

    /// The items under the tab's choices, in its order (unknown values last;
    /// otherwise SearXNG's own order).
    public static func narrow<T>(_ category: String, _ results: [T], _ choices: Choices, item: (T) -> Item) -> [T] {
        let tabFilters = filters[category] ?? []
        let keep = results.filter { r in
            tabFilters.allSatisfy { f in choices[f.key].isEmpty || value(f.key, item(r)) == choices[f.key] }
        }
        let key: ((Item) -> Double?)? = switch choices.order {
        case "largest": { imageSize(resolution: $0.resolution, imgFormat: $0.imgFormat).map { -Double($0.w * $0.h) } }
        case "newest": { $0.published.map { -$0.timeIntervalSince1970 } }
        case "shortest": { lengthSeconds($0.length).map(Double.init) }
        case "longest": { lengthSeconds($0.length).map { -Double($0) } }
        default: nil
        }
        guard let key else { return keep }
        return keep.enumerated()
            .map { (index: $0.offset, value: $0.element, k: key(item($0.element))) }
            .sorted { a, b in
                if (a.k == nil) != (b.k == nil) { return a.k != nil }
                if let ak = a.k, let bk = b.k, ak != bk { return ak < bk }
                return a.index < b.index
            }
            .map(\.value)
    }

    /// Text as phrases are compared: lowercase words, one space apart, a space at each end.
    static func phraseText(_ text: String) -> String {
        let words = text.lowercased().replacing(/[^\p{L}\p{N}]+/.matchingSemantics(.unicodeScalar), with: " ")
        return " \(words.trimmingCharacters(in: .whitespaces)) "
    }

    /// The search's "quoted phrases", as `phraseText` writes them; an unclosed quote counts for nothing.
    public static func quotedPhrases(_ query: String) -> [String] {
        query.matches(of: /"([^"]*)"/).map { phraseText(String($0.1)) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Image results naming more of the search's quoted phrases first, in
    /// their title, snippet, page or picture address ("stevie-case.jpg"
    /// names "Stevie Case"); otherwise as they came. Image engines treat
    /// quotes loosely, so the picture that names the phrase leads and
    /// nothing is hidden. Twin of search-core's `S.phrasesFirst`.
    public static func phrasesFirst<T>(
        _ query: String, _ results: [T], fields: (T) -> (title: String, content: String, url: String, imgSrc: String)
    ) -> [T] {
        let phrases = quotedPhrases(query)
        guard !phrases.isEmpty else { return results }
        func score(_ r: T) -> Int {
            let f = fields(r)
            let parts: [String] = [f.title, f.content, f.url.removingPercentEncoding ?? f.url, f.imgSrc.removingPercentEncoding ?? f.imgSrc]
            let words = phraseText(parts.joined(separator: " "))
            return phrases.filter { words.contains($0) }.count
        }
        let scored: [(index: Int, value: T, k: Int)] = results.enumerated().map { ($0.offset, $0.element, score($0.element)) }
        return scored.sorted { $0.k != $1.k ? $0.k > $1.k : $0.index < $1.index }.map(\.value)
    }

    /// The row's menus for the tab: the order first, then each filter whose
    /// results differ in it (or one chosen), every choice counted against
    /// the other choices made.
    public static func row(_ category: String, _ results: [Item], _ choices: Choices) -> [Menu] {
        guard let tabOrders = orders[category] else { return [] }
        var out: [Menu] = []
        let shownOrders = tabOrders.filter { value, _ in
            if value.isEmpty || value == choices.order { return true }
            switch value {
            case "largest": return results.contains { !Self.value("size", $0).isEmpty }
            case "newest": return results.contains { $0.published != nil }
            default: return results.contains { !Self.value("length", $0).isEmpty }
            }
        }
        if shownOrders.count > 1 {
            out.append(Menu(key: "order", name: "Order", options: shownOrders.map { .init(value: $0.0, label: $0.1) }))
        }
        for filter in filters[category] ?? [] {
            var others = choices
            others.order = ""
            others[filter.key] = ""
            var counts: [String: Int] = [:]
            var firstSeen: [String] = []
            for r in narrow(category, results, others, item: { $0 }) {
                let v = value(filter.key, r)
                guard !v.isEmpty else { continue }
                if counts[v] == nil { firstSeen.append(v) }
                counts[v, default: 0] += 1
            }
            let chosen = choices[filter.key]
            var values: [(String, String)]
            if let fixed = filter.fixed {
                values = fixed.filter { counts[$0.0] != nil || $0.0 == chosen }
            } else {
                values = firstSeen.sorted { a, b in counts[a]! != counts[b]! ? counts[a]! > counts[b]! : a < b }.map { ($0, $0) }
                if !chosen.isEmpty, counts[chosen] == nil { values.append((chosen, chosen)) }
            }
            if values.count < 2 && chosen.isEmpty { continue }
            out.append(Menu(
                key: filter.key, name: filter.name,
                options: [.init(value: "", label: filter.any)] + values.map { .init(value: $0.0, label: "\($0.1) · \(counts[$0.0] ?? 0)") }))
        }
        return out
    }
}
