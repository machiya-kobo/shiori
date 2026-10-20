import AppIntents
import CoreSpotlight
import HisterKit
import SwiftUI

// Your pages in the system's search: Spotlight lists the newest of them
// (titles, sites and snippets, kept in this device's Spotlight index), and
// Siri and Shortcuts find any of them by asking Hister (`PageQuery`). A tap
// opens the page itself. Pages only: never a note (a private vault's, or
// any), a file or code, as the offline copy. Per device (Settings → Search →
// Spotlight); signing out of Hister, or another token or account, empties it.

/// One of your pages, as Spotlight, Siri and Shortcuts see it. Its id is its address.
struct PageEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let defaultQuery = PageQuery()

    var id: String
    var title: String
    var site: String
    var snippet: String
    var added: Date

    init(id: String, title: String, site: String, snippet: String, added: Date) {
        self.id = id
        self.title = title
        self.site = site
        self.snippet = snippet
        self.added = added
    }

    init(_ page: StoredPage) {
        self.init(id: page.url, title: page.displayTitle, site: page.domain, snippet: page.snippet.plainText, added: page.added)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(site)", image: .init(systemName: "globe"))
    }

    /// What Spotlight shows and matches: the title, the site, the snippet.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .url)
        set.title = title
        set.displayName = title
        set.contentDescription = snippet.isEmpty ? site : "\(site) · \(snippet)"
        set.keywords = [site]
        set.url = URL(string: id)
        set.addedDate = added
        return set
    }
}

/// Finds your pages for Siri and Shortcuts (a search of Hister, never the web), and the ones in Spotlight by id.
struct PageQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PageEntity] {
        let known = SpotlightIndex.known()
        return identifiers.compactMap { id in
            known[id] ?? URL(string: id).map { PageEntity(id: id, title: id, site: $0.host() ?? "", snippet: "", added: .now) }
        }
    }

    func entities(matching string: String) async throws -> [PageEntity] {
        guard let client = SpotlightIndex.client() else { return [] }
        let page = try await client.search(string, limit: 12)
        return page.documents.filter(SpotlightIndex.indexable).map(PageEntity.init)
    }

    func suggestedEntities() async throws -> [PageEntity] {
        Array(SpotlightIndex.known().values.sorted { $0.added > $1.added }.prefix(10))
    }
}

/// Opens one of your pages (a Spotlight result, Siri, a shortcut): the page itself, in the browser.
struct OpenPageIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Page"
    static let description = IntentDescription("Opens one of your pages from Hister.")
    static let openAppWhenRun = false

    @Parameter(title: "Page")
    var target: PageEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = SafeHref.url(target.id) else { throw $target.needsValueError("Which page should Shiori open?") }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// The pages in this device's Spotlight index: the newest `limit` of your
/// pages, refreshed every few hours from the foreground, and the copy of what
/// was given (for Siri's ids and suggestions), in this app's caches.
nonisolated enum SpotlightIndex {
    static let limit = 300
    static let refreshEvery: TimeInterval = 6 * 3600
    /// The switch in Settings (per device, on until turned off).
    static let settingKey = "spotlightPages"

    static var enabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    /// May this page be in the system's search? Your web pages only.
    static func indexable(_ page: StoredPage) -> Bool {
        OfflineStore.keepable(page) && page.label != Notes.label && SafeHref.url(page.url) != nil
    }

    /// Hister with this device's server and sign-in (Siri and Shortcuts run without the app's state).
    static func client() -> HisterClient? {
        let server = SharedSettings.defaults?.string(forKey: SharedSettings.Key.serverURL) ?? ""
        return HisterClient(serverURL: server, token: HisterKeychain.token, histerSession: HisterKeychain.session)
    }

    /// Refreshes the index when it's due (or another server's, or `force`); empties it when switched off.
    static func refresh(force: Bool = false) async {
        guard enabled else { return await clear() }
        guard let client = client() else { return }
        let token = HisterKeychain.token
        let origin = SharedSettings.defaults?.string(forKey: SharedSettings.Key.serverURL) ?? ""
        let saved = read()
        if !force, let saved, saved.origin == origin, Date.now.timeIntervalSince(saved.at) < refreshEvery { return }
        var pages: [StoredPage] = []
        var key: String?
        do {
            repeat {
                let page = try await client.search("*", sort: .newest, pageKey: key, limit: 100)
                pages += page.documents.filter(indexable)
                key = page.nextPageKey
            } while key != nil && pages.count < limit
        } catch {
            return // out of reach: what's there stays until the next try
        }
        var seen = Set<String>()
        let entities = pages.filter { seen.insert($0.url).inserted }.prefix(limit).map(PageEntity.init)
        // Switched off, or signed out, while it was asking: nothing goes in.
        guard enabled, HisterKeychain.token == token else { return }
        do {
            try await CSSearchableIndex.default().deleteAppEntities(ofType: PageEntity.self)
            try await CSSearchableIndex.default().indexAppEntities(Array(entities))
            write(Saved(origin: origin, at: .now, pages: entities.map(Saved.Page.init)))
        } catch {}
    }

    /// Takes every page out of the system's search (switched off, signed out, another account).
    static func clear() async {
        try? await CSSearchableIndex.default().deleteAppEntities(ofType: PageEntity.self)
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    /// A page deleted from Hister leaves Spotlight too.
    static func forget(url: String) async {
        try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [url], ofType: PageEntity.self)
        guard var saved = read() else { return }
        saved.pages.removeAll { $0.id == url }
        write(saved)
    }

    /// The pages given to Spotlight, by id.
    static func known() -> [String: PageEntity] {
        Dictionary((read()?.pages ?? []).map { ($0.id, $0.entity) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: The copy of what was given

    private struct Saved: Codable {
        var origin: String
        var at: Date
        var pages: [Page]

        struct Page: Codable {
            var id, title, site, snippet: String
            var added: Date
            init(_ entity: PageEntity) {
                (id, title, site, snippet, added) = (entity.id, entity.title, entity.site, entity.snippet, entity.added)
            }
            var entity: PageEntity { PageEntity(id: id, title: title, site: site, snippet: snippet, added: added) }
        }
    }

    private static var file: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "spotlight-pages.json")
    }

    private static func read() -> Saved? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    private static func write(_ saved: Saved) {
        guard let file, let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// A Spotlight result tapped where the system hands the app the item rather than running `OpenPageIntent`: the page opens.
struct SpotlightOpening: ViewModifier {
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            // An app entity's item id may carry its type before the address.
            let address = id.range(of: "http").map { String(id[$0.lowerBound...]) } ?? id
            if let url = SafeHref.url(address) { openURL(url) }
        }
    }
}
