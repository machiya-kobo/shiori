import Foundation
import HisterKit
import Observation

/// One list of search results, loaded a page at a time.
@Observable
final class ResultsModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(HisterError)
    }

    /// What was searched, before any filters (a respelling replaces it).
    private(set) var baseQuery: String
    /// For a typed search: its text and how this list wraps it, so one
    /// that finds nothing can retry a respelling.
    let respellable: (text: String, wrap: (String) -> String)?
    /// The web's related searches for a text (`AppState.webSuggestions`),
    /// set by the list before it loads.
    var webSuggestions: ((String) async -> [String])?
    /// The spelling searched instead, when the typed one found nothing
    /// ("pyhton tutorial" → "python tutorial"): Hister matches words exactly.
    private(set) var respelledAs: String?
    /// Filter words added to it (`domain:github.com`, `updated:<7d`, …):
    /// Hister reads filters as query words, so they're kept apart only to
    /// show and remove them one at a time. Changing them reloads.
    private(set) var filters: [String] = []
    /// A custom date range (the presets are filter words).
    private(set) var dateRange: ClosedRange<Date>?
    /// Offers the filters (and their counts).
    let filterable: Bool
    /// What's searched: the base query and its filters.
    var query: String { ([baseQuery] + filters).joined(separator: " ") }

    /// How the list is ordered. All but Title are Hister's own sorts.
    enum Order: String, CaseIterable, Identifiable {
        case bestMatch, newest, oldest, mostVisited, site, title
        var id: Self { self }
        var name: String {
            switch self {
            case .bestMatch: "Best Match"
            case .newest: "Newest"
            case .oldest: "Oldest"
            case .mostVisited: "Most Visited"
            case .site: "Site A–Z"
            case .title: "Title A–Z"
            }
        }
        var serverSort: SearchSort {
            switch self {
            case .bestMatch: .relevance
            case .newest, .title: .newest
            case .oldest: .oldest
            case .mostVisited: .mostVisited
            case .site: .domain
            }
        }
        init(_ sort: SearchSort) {
            switch sort {
            case .relevance: self = .bestMatch
            case .newest: self = .newest
            case .oldest: self = .oldest
            case .mostVisited: self = .mostVisited
            case .domain: self = .site
            }
        }
    }

    /// Sections the list is split into, each with its count.
    enum Grouping: String, CaseIterable, Identifiable {
        case none, day, month, label, site
        var id: Self { self }
        var name: String {
            switch self {
            case .none: "None"
            case .day: "By Day"
            case .month: "By Month"
            case .label: "By Label"
            case .site: "By Site"
            }
        }
    }

    private(set) var order: Order
    private(set) var grouping = Grouping.none
    var sort: SearchSort { order.serverSort }
    /// Title order and label or site groups need every result at once (up
    /// to `allLimit`): Hister can't sort by those, and a group's count must
    /// be the whole group's, not the loaded part's.
    var loadsAll: Bool { order == .title || grouping == .label || grouping == .site }
    static let allLimit = 1000
    /// Loaded everything the server would give, but stopped at `allLimit`.
    private(set) var capped = false
    /// Where the list comes from:
    /// your pages from Hister (which never sends notes, `SearchText`), your
    /// notes from Kura, or both, newest first (the Library's All).
    enum Source {
        case pages, notes, all
    }

    let source: Source

    private(set) var documents: [StoredPage] = []
    private(set) var total = 0
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var suggestion: String?
    /// Results you opened before for this search (first page), shown first.
    private(set) var opened: [OpenedResult] = []
    /// Counts per filter value, from the first page.
    private(set) var facets: Facets?
    /// Set by the list from Settings before it loads.
    var wantsFacets = false
    var semantic = false
    /// Kura, for a notes list and the Library's All (nil without a Kura
    /// address in Settings → Notes: then there are no notes). Set by the
    /// list before it loads.
    var kura: KuraClient?
    /// Which of Kura's vaults a notes list searches ("all", or a name);
    /// nil for the default only. Set by the list (`AppState.notesVault`).
    var vaults: String?
    /// The Library's All while it merges (newest first, no filters).
    private var merge: NewestFirstMerge?
    private var nextPageKey: String?
    /// Bumped on every fresh load, so a stale page never lands.
    private var generation = 0

    init(
        query: String, sort: SearchSort = .relevance, source: Source = .pages, filterable: Bool = true,
        respellable: (text: String, wrap: (String) -> String)? = nil
    ) {
        self.baseQuery = query
        self.respellable = respellable
        self.order = Order(sort)
        self.source = source
        self.filterable = filterable
    }

    /// The caller reloads.
    func setOrder(_ order: Order) {
        self.order = order
        // Day and month groups follow the date; any other order would
        // scatter a day across the list.
        if order != .newest, order != .oldest, grouping == .day || grouping == .month { grouping = .none }
    }

    func setGrouping(_ grouping: Grouping) {
        self.grouping = grouping
        if grouping == .day || grouping == .month, order != .newest, order != .oldest { order = .newest }
    }

    struct Section: Identifiable {
        var id: String
        var title: String
        var pages: [StoredPage]
    }

    /// The loaded pages in their groups: in list order for days and
    /// months, A to Z for labels and sites (no label last).
    func sections(of pages: [StoredPage], calendar: Calendar = .current, now: Date = .now) -> [Section] {
        switch grouping {
        case .none:
            return [Section(id: "all", title: "", pages: pages)]
        case .day, .month:
            var out: [Section] = []
            for page in pages {
                let key = grouping == .day
                    ? calendar.startOfDay(for: page.updated)
                    : calendar.date(from: calendar.dateComponents([.year, .month], from: page.updated)) ?? page.updated
                let id = key.timeIntervalSince1970.description
                if out.last?.id == id {
                    out[out.count - 1].pages.append(page)
                } else if let i = out.firstIndex(where: { $0.id == id }) {
                    out[i].pages.append(page)
                } else {
                    out.append(Section(id: id, title: Self.title(for: key, byDay: grouping == .day, calendar: calendar, now: now), pages: [page]))
                }
            }
            return out
        case .label, .site:
            let groups = Dictionary(grouping: pages) { grouping == .label ? $0.label : $0.domain }
            return groups.keys.sorted { a, b in
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                return a.localizedStandardCompare(b) == .orderedAscending
            }.map { key in
                Section(id: key, title: key.isEmpty ? (grouping == .label ? "No Label" : "No Site") : key, pages: groups[key] ?? [])
            }
        }
    }

    /// "Today", "Yesterday", "Friday, Sep 26"; "September 2026".
    static func title(for date: Date, byDay: Bool, calendar: Calendar = .current, now: Date = .now) -> String {
        guard byDay else { return date.formatted(.dateTime.month(.wide).year()) }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear
            ? date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private var options: SearchOptions {
        SearchOptions(
            facets: filterable && wantsFacets, dateFrom: dateRange?.lowerBound, dateTo: dateRange?.upperBound,
            semantic: semantic)
    }

    /// Adds or removes one filter word; the caller reloads.
    func toggleFilter(_ word: String) {
        if let i = filters.firstIndex(of: word) { filters.remove(at: i) } else { filters.append(word) }
    }

    /// Replaces the filter words that start with `prefix` (one date preset
    /// at a time, say) with `word`, or removes them for nil.
    func setFilter(_ word: String?, replacing prefix: String) {
        filters.removeAll { $0.hasPrefix(prefix) }
        if let word { filters.append(word) }
        if word != nil, prefix.hasPrefix("updated:") { dateRange = nil }
    }

    func setDateRange(_ range: ClosedRange<Date>?) {
        dateRange = range
        if range != nil { filters.removeAll { $0.hasPrefix("updated:") } }
    }

    func clearFilters() {
        filters = []
        dateRange = nil
    }

    /// Drops one opened result from the list shown (after forgetting it).
    func removeOpened(_ url: String) {
        opened.removeAll { $0.url == url }
    }

    /// Every URL in `documents`, kept as they're added (not rebuilt from
    /// the whole list for each page).
    private var seen = Set<String>()

    /// Appends what's new, returning how many were.
    @discardableResult
    private func append(_ page: [StoredPage]) -> Int {
        let fresh = page.filter { seen.insert($0.url).inserted }
        documents += fresh
        return fresh.count
    }

    var hasMore: Bool { merge.map { !$0.finished } ?? (nextPageKey != nil) }

    /// One page from Hister, or from Kura for a notes list (it takes no
    /// filters or facets; its page key is an offset). No Kura, no notes.
    private func search(
        _ client: HisterClient, _ text: String, sort: SearchSort, pageKey: String? = nil, limit: Int = 30,
        options: SearchOptions = SearchOptions()
    ) async throws(HisterError) -> SearchPage {
        guard source == .notes else {
            return try await client.search(text, sort: sort, pageKey: pageKey, limit: limit, options: options)
        }
        guard let kura else { return SearchPage(total: 0, documents: [], nextPageKey: nil, suggestion: nil) }
        return try await kura.search(text, sort: sort, pageKey: pageKey, limit: limit, vaults: vaults)
    }

    /// The Library's All interleaves your notes only newest first and
    /// unfiltered: Kura has no visits, sites or Hister's filter words, so
    /// any other order, a filter, or a whole-list sort shows your pages.
    private var merges: Bool {
        source == .all && kura != nil && order == .newest && filters.isEmpty && dateRange == nil && !loadsAll
    }

    /// The Library's All, first page: a page of each, placed by date.
    private func loadMerged(using client: HisterClient, kura: KuraClient, generation mine: Int) async {
        do {
            async let notesPage = try? kura.search(query, sort: .newest)
            let pages = try await client.search(query, sort: .newest, options: options)
            let notes = await notesPage
            guard mine == generation else { return }
            var merge = NewestFirstMerge()
            merge.add(pages: pages.documents, next: pages.nextPageKey)
            if let notes { merge.add(notes: notes.documents, next: notes.nextPageKey) } else { merge.endNotes() }
            documents = []
            seen = []
            append(merge.take())
            self.merge = merge
            nextPageKey = nil
            total = pages.total + (notes?.total ?? 0)
            suggestion = nil
            opened = []
            if pages.facets != nil || !options.facets { facets = pages.facets }
            phase = .loaded
        } catch .cancelled {
        } catch {
            guard mine == generation else { return }
            if documents.isEmpty { phase = .failed(error) }
        }
    }

    /// The Library's All, on scrolling: the next page of whichever list
    /// ran out, until something can be placed (a few tries at most).
    private func loadMoreMerged(using client: HisterClient) async {
        guard var merge, let kura, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let mine = generation
        for _ in 0..<6 where !merge.finished {
            if merge.needsPages, let key = merge.pagesKey {
                guard let page = try? await client.search(query, sort: .newest, pageKey: key, options: options) else { return }
                merge.add(pages: page.documents, next: page.nextPageKey)
            }
            if merge.needsNotes, let key = merge.notesKey {
                if let page = try? await kura.search(query, sort: .newest, pageKey: key) {
                    merge.add(notes: page.documents, next: page.nextPageKey)
                } else {
                    merge.endNotes()
                }
            }
            guard mine == generation else { return }
            let placed = merge.take()
            self.merge = merge
            if !placed.isEmpty {
                append(placed)
                return
            }
        }
    }

    private func loadEverything(using client: HisterClient, generation mine: Int) async {
        do {
            // The first page for its extras (opened results, counts, total).
            let first = try await search(client, query, sort: sort, options: options)
            var all = try await allResults(using: client, limit: Self.allLimit)
            guard mine == generation else { return }
            if order == .title {
                all.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
            }
            documents = all
            seen = Set(all.map(\.url))
            total = first.total
            nextPageKey = nil
            capped = all.count >= Self.allLimit
            suggestion = first.suggestion
            opened = first.opened
            if first.facets != nil || !options.facets { facets = first.facets }
            phase = .loaded
        } catch .cancelled {
        } catch {
            guard mine == generation else { return }
            if documents.isEmpty { phase = .failed(error) }
        }
    }

    /// Every result for Export, up to `limit`, paging on from the first
    /// (not only what's been scrolled to).
    func allResults(using client: HisterClient, limit: Int = 1000) async throws(HisterError) -> [StoredPage] {
        var out: [StoredPage] = []
        var urls = Set<String>()
        var key: String?
        let range = SearchOptions(dateFrom: dateRange?.lowerBound, dateTo: dateRange?.upperBound)
        repeat {
            let page = try await search(client, query, sort: sort, pageKey: key, limit: 100, options: range)
            // No work note leaves the device in an export.
            out += page.documents.filter { !Notes.isPrivateNote($0.url) && urls.insert($0.url).inserted }
            key = page.nextPageKey
        } while key != nil && out.count < limit
        return Array(out.prefix(limit))
    }

    func load(using client: HisterClient?) async {
        guard let client else {
            phase = .failed(.unreachable)
            return
        }
        generation += 1
        let mine = generation
        if documents.isEmpty { phase = .loading }
        merge = nil
        if merges, let kura {
            await loadMerged(using: client, kura: kura, generation: mine)
            return
        }
        if loadsAll {
            await loadEverything(using: client, generation: mine)
            return
        }
        capped = false
        do {
            var page = try await search(client, query, sort: sort, options: options)
            guard mine == generation else { return }
            if page.total == 0, page.opened.isEmpty, let respelled = await respelled(using: client, generation: mine) {
                page = respelled
            }
            guard mine == generation else { return }
            documents = []
            seen = []
            append(page.documents)
            total = page.total
            nextPageKey = page.nextPageKey
            // Hister's suggestion is a past search of yours, often this one.
            suggestion = page.suggestion.flatMap { $0.caseInsensitiveCompare(baseQuery) == .orderedSame ? nil : $0 }
            opened = page.opened
            if page.facets != nil || !options.facets { facets = page.facets }
            phase = .loaded
        } catch .cancelled {
            // A newer load (or leaving the screen) superseded this one.
        } catch {
            guard mine == generation else { return }
            // Keep what is already on screen; only an empty list shows the error.
            if documents.isEmpty { phase = .failed(error) }
        }
    }

    /// The first page for a respelling of a typed search that found
    /// nothing, taken from the web's related searches; nil when there's
    /// none, or it finds nothing either. Switches the list to it.
    private func respelled(using client: HisterClient, generation mine: Int) async -> SearchPage? {
        guard respelledAs == nil, let respellable, let webSuggestions,
            let fixed = Respelling.corrected(respellable.text, suggestions: await webSuggestions(respellable.text)),
            mine == generation
        else { return nil }
        let wrapped = respellable.wrap(fixed)
        guard let page = try? await search(client, ([wrapped] + filters).joined(separator: " "), sort: sort, options: options),
            mine == generation, page.total > 0 || !page.opened.isEmpty
        else { return nil }
        baseQuery = wrapped
        respelledAs = fixed
        return page
    }

    /// Fetches the next page when `document` is near the end of the list.
    func loadMoreIfNeeded(after document: StoredPage, using client: HisterClient?, tries: Int = 0) async {
        if merge != nil {
            guard let client, let index = documents.lastIndex(where: { $0.url == document.url }), index >= documents.count - 5
            else { return }
            await loadMoreMerged(using: client)
            return
        }
        guard let client, let key = nextPageKey, !isLoadingMore, tries < 6,
            let index = documents.lastIndex(where: { $0.url == document.url }), index >= documents.count - 5
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let mine = generation
        guard let page = try? await search(client, query, sort: sort, pageKey: key, options: options),
            mine == generation
        else { return }
        let added = append(page.documents)
        nextPageKey = page.nextPageKey
        // Nothing new (all seen already): keep going.
        if added == 0, nextPageKey != nil, let last = documents.last {
            isLoadingMore = false
            await loadMoreIfNeeded(after: last, using: client, tries: tries + 1)
        }
    }
}
