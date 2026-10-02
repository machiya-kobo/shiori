import Foundation
import os

/// Vault notes: the Obsidian notes Hister indexes (label:vault), stored
/// from their Niwa pages (/n/<path>) or Konbini cards (/p/<slug>).
public enum Notes {
    /// Hister's label for vault notes.
    public static let label = "vault"

    /// The query restricted to vault notes.
    public static func query(_ text: String) -> String {
        "\(text) label:\(label)".trimmingCharacters(in: .whitespaces)
    }

    /// Shiori reads notes only from Kura, so every Hister query leaves them
    /// out with this term. Hister has no exclude parameter (`exclude_label`
    /// is ignored, `NOT label:vault` is wrong), but a negated field works,
    /// with paging and exact totals.
    /// `metadata.source` too, so a note relabelled in Hister's own UI stays
    /// out (Kura marks every note with it; the totals are the same).
    public static let exclusion = "-label:\(label) -metadata.source:\(label)"
    private static let exclusionTerms = exclusion.split(separator: " ").map(String.init)

    /// `text` with the notes left out (once).
    public static func excluding(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(exclusion) { return trimmed }
        return trimmed.isEmpty ? exclusion : "\(trimmed) \(exclusion)"
    }

    /// A query as the user typed it, without the exclusion (the Opened
    /// list says what each page was opened from).
    public static func withoutExclusion(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            .filter { !exclusionTerms.contains($0) }.joined(separator: " ")
    }

    /// A Konbini card: its slug and its note's path in the vault.
    public struct Card: Codable, Sendable, Equatable {
        public var slug: String
        public var path: String

        public init(slug: String, path: String) {
            self.slug = slug
            self.path = path
        }
    }

    /// The work vault a note belongs to ("work"), from its address: Kura
    /// keeps the default vault's notes at `/n/<slug>` for good and every
    /// other vault's at `/v/<vault>/n/<slug>`. Nil
    /// for the default vault, and for anything that isn't a note.
    /// Everything that must not reach a work note (Hister, AI, caches,
    /// exports) asks this.
    ///
    /// Read as Kura reads it: Kura serves `/v/` however the path reaches it
    /// (its server folds a leading `//`, then it decodes `%XX` once), so
    /// `//v/…` and `/%76/…` are a work note too. Only ASCII escapes are
    /// decoded: a vault's name and the `/v/…/n/` around it are ASCII. Kura
    /// refuses a public address with a path, so `/v/` starts the path.
    /// search-core's `noteVault` is the twin.
    public static func otherVault(of url: String) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        var path = decodingASCIIEscapes(components.percentEncodedPath)
        while path.hasPrefix("//") { path.removeFirst() }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        // "", "v", vault, "n", …
        guard parts.count >= 5, parts[1] == "v", parts[3] == "n", !parts[2].isEmpty else { return nil }
        // A name that won't decode is still another vault's.
        return parts[2].removingPercentEncoding ?? String(parts[2])
    }

    /// `%XX` escapes of ASCII characters decoded once; every other one left
    /// as it is.
    static func decodingASCIIEscapes(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if scalars[i] == "%", i + 2 < scalars.count,
               scalars[i + 1].properties.isASCIIHexDigit, scalars[i + 2].properties.isASCIIHexDigit,
               let byte = UInt8(String(Character(scalars[i + 1])) + String(Character(scalars[i + 2])), radix: 16),
               byte < 0x80 {
                out.append(Unicode.Scalar(byte))
                i += 3
            } else {
                out.append(scalars[i])
                i += 1
            }
        }
        return String(out)
    }

    /// A note's chip, naming its vault ("Work vault"), since Notes mix
    /// vaults: the vault from its address, else
    /// Kura's default one. `name` is "" while the default isn't known, and
    /// the text then is just "vault". search-core's `vaultChip` is the twin.
    public static func vaultChip(of url: String, vaults: [KuraVault]) -> (name: String, text: String) {
        let name = otherVault(of: url) ?? vaults.first(where: \.isDefault)?.name ?? ""
        guard !name.isEmpty else { return ("", "vault") }
        let title = vaults.first { $0.name == name }?.title ?? name
        return (name, "\(title) vault")
    }

    /// A note in a vault other than the default: kept out of Hister, AI,
    /// on-device caches, exports and feeds.
    public static func isOtherVault(_ url: String) -> Bool { otherVault(of: url) != nil }

    /// The vault path ("Projects/Example.md") of a note at this URL.
    public static func path(of url: String, cards: [Card]) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        var path = components.percentEncodedPath
        // A work vault's note: /v/<vault>/n/<slug>.
        if otherVault(of: url) != nil {
            path = "/" + path.split(separator: "/", omittingEmptySubsequences: false).dropFirst(3).joined(separator: "/")
        }
        if path.hasPrefix("/n/") {
            var rest = String(path.dropFirst(3))
            while rest.hasSuffix("/") { rest.removeLast() }
            guard !rest.isEmpty, let decoded = rest.removingPercentEncoding else { return nil }
            return decoded + ".md"
        }
        if path.hasPrefix("/p/") {
            let slug = path.dropFirst(3).split(separator: "/").first.map(String.init) ?? ""
            return cards.first { $0.slug == slug }?.path
        }
        return nil
    }

    public static func obsidianURL(vault: String, path: String) -> URL? {
        guard !vault.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.setQueryItems([
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: stripped(path)),
        ])
        return components.url
    }

    /// A note's reader page (Kura; Niwa before it): the
    /// note's own address when that already is a reader page (/n/…), else
    /// one built on the reader's address (a Konbini project card's note).
    public static func readerURL(page: String, base: String, path: String) -> URL? {
        if let components = URLComponents(string: page), components.percentEncodedPath.hasPrefix("/n/") || isOtherVault(page) {
            return URL(string: page)
        }
        return niwaURL(base: base, path: path)
    }

    /// A vault tag's page in Kura (`/t/topic/docker`; `/t/topic` lists every
    /// topic/…). Kura owns browsing the vault by tag, folder and backlink:
    /// Shiori links there rather than growing its own.
    public static func tagURL(base: String, tag: String) -> URL? {
        let tag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        guard !tag.isEmpty, let base = URL(string: base.hasSuffix("/") ? base : base + "/"), base.scheme != nil
        else { return nil }
        var url = base.appending(path: "t")
        for segment in tag.split(separator: "/") { url = url.appending(path: String(segment)) }
        return url
    }

    public static func niwaURL(base: String, path: String) -> URL? {
        guard let base = URL(string: base.hasSuffix("/") ? base : base + "/"), !base.absoluteString.isEmpty,
            base.scheme != nil
        else { return nil }
        var url = base.appending(path: "n")
        for segment in stripped(path).split(separator: "/") { url = url.appending(path: String(segment)) }
        return url
    }

    public static func konbiniURL(base: String, path: String, cards: [Card]) -> URL? {
        guard let card = cards.first(where: { $0.path == path }),
            let base = URL(string: base.hasSuffix("/") ? base : base + "/"), base.scheme != nil
        else { return nil }
        return base.appending(path: "p").appending(path: card.slug)
    }

    /// Konbini's cards, for linking notes and cards both ways.
    public static func fetchCards(base: String, session: URLSession = HisterClient.defaultSession) async -> [Card] {
        guard let url = URL(string: (base.hasSuffix("/") ? base : base + "/") + "api/cards"), url.scheme != nil else {
            return []
        }
        struct Wrapped: Decodable { var cards: [Card] }
        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            HisterClient.log.notice("Konbini cards not fetched: \(String(describing: error), privacy: .public)")
            return []
        }
        if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) { return wrapped.cards }
        do {
            return try JSONDecoder().decode([Card].self, from: data)
        } catch {
            // Without the cards, notes lose their Konbini links, quietly.
            HisterClient.log.error("Konbini cards didn't decode: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private static func stripped(_ path: String) -> String {
        path.hasSuffix(".md") ? String(path.dropLast(3)) : path
    }
}
