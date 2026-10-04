import HisterKit
import SwiftUI

/// Search → All, as on Shiori's search page and in the web app: the web's
/// results with a page of your pages and notes among them (taking turns,
/// spread evenly over the web's first page: `MixedResults`), each row saying
/// whose it is; their totals go on the Pages and Notes pills
/// (`SearchSession.counts`). Web is the pill for the web alone.
/// Web Results switches the web off here too: then the list is yours.
struct AllResults: View {
    let query: String
    let showScope: (SearchScope) -> Void
    let search: (String) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(SearchSession.self) private var session: SearchSession?
    @State private var pages: ResultsModel
    @State private var notes: ResultsModel
    @State private var web: WebResultsModel
    /// While your pages or notes are still coming, All keeps its spinner
    /// (600 ms at most): rows added to a list already on screen drew at a
    /// guessed height on the Mac, squashed titles for a third of a second,
    /// when a search from the sidebar brought its notes before its pages.
    /// Hister answers both in about 50 ms, so the list
    /// appears once, laid out. The web comes later, in its own section.
    @State private var holding = true
    /// How many code documents match, for the Code pill's count (never
    /// listed here: code shows only on its own pill).
    @State private var codeTotal = 0

    init(query: String, showScope: @escaping (SearchScope) -> Void, search: @escaping (String) -> Void) {
        self.query = query
        self.showScope = showScope
        self.search = search
        // Notes are under Your Notes, as on the search page and in the web app.
        // Pages from Hister (never the notes), notes from Kura.
        _pages = State(initialValue: ResultsModel(query: query, respellable: (query, { $0 })))
        _notes = State(initialValue: ResultsModel(query: query, source: .notes, respellable: (query, { $0 })))
        // The web gets the words, not Hister's syntax (label:bsd).
        _web = State(initialValue: WebResultsModel(query: SearxClient.webQuery(query)))
    }

    /// Your pages and your notes in All: a page of each (as the web pages'
    /// 20), among the web's results (the rest on the Pages and Notes pills).
    static let count = 20

    /// Not for a search of Hister syntax alone (label:bsd, @retro), and
    /// only for a search run on purpose (`SearchSession.webAllowed`): while
    /// typing, yours alone.
    private var webOn: Bool {
        app.allSearch.webResults && app.searx != nil && !web.query.isEmpty && (session == nil || session?.webAllowed == query)
    }

    var body: some View {
        content
            .task(id: "\(query)|\(app.searchPage.niwaURL)") { await load() }
            // Return after typing: the web joins what's already shown.
            .task(id: webOn) {
                if webOn, web.phase == .idle { await web.load(searx: app.searx, hister: app.client) }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                holding = false
            }
            .refreshable { await load() }
            .topBar {
                ListControls(model: pages, title: query, ordering: false) {}
            }
            .resultActions(query: query)
            // Their totals on the Pages and Notes pills ("Pages 31").
            .onChange(of: totals, initial: true) { _, totals in
                session?.setCounts([.hister: totals[0], .notes: totals[1], .code: totals[2]], for: query)
            }
    }

    /// Hister's total has no notes (they're Kura's), and leaves out the pages
    /// you opened while Show Opened is off.
    private var totals: [Int] {
        [max(pages.total - hiddenOpened, yourPages().count), max(notes.total, shown(notes, count: Self.count).count), codeTotal]
    }

    private func load() async {
        pages.semantic = app.semanticOn
        pages.webSuggestions = { [app] in await app.webSuggestions(for: $0) }
        notes.webSuggestions = { [app] in await app.webSuggestions(for: $0) }
        notes.kura = app.notesKura
        async let mine: Void = pages.load(using: app.client)
        async let vault: Void = notes.load(using: app.client)
        // The Code pill's count: Hister's own index, nothing spent.
        if app.hasCodeDocs, let client = app.client, let page = try? await client.search(CodeDocs.query(query), limit: 1) {
            codeTotal = page.total
        }
        if webOn { await web.load(searx: app.searx, hister: app.client) }
        _ = await (mine, vault)
    }

    private func shown(_ model: ResultsModel, count: Int) -> [StoredPage] {
        Array(model.documents.filter { !app.deletedURLs.contains($0.url) }.prefix(count))
    }

    /// Any part that failed: with nothing to show, that's the answer, not
    /// "no results" (pages first, then notes, then the web).
    private var failure: HisterError? {
        var phases = [pages.phase, notes.phase]
        if webOn { phases.append(web.phase) }
        for phase in phases {
            if case .failed(let error) = phase { return error }
        }
        return nil
    }

    private var mineLoading: Bool {
        [pages.phase, notes.phase].contains { $0 == .idle || $0 == .loading }
    }

    private var stillLoading: Bool {
        mineLoading || (webOn && (web.phase == .idle || web.phase == .loading))
    }

    /// Your Pages' five: the pages you opened for this search first (Hister
    /// ranks them first, and counts them in the total), then the rest.
    /// Without them, "6 results" showed one page once the "You Opened"
    /// section left All.
    private func yourPages() -> [StoredPage] {
        let opened = app.searchPage.showOpened
            ? pages.opened.map { StoredPage(opened: $0) }.filter { !app.isNotePage($0.url) } : []
        var seen = Set<String>()
        return Array((opened + pages.documents)
            .filter { !app.deletedURLs.contains($0.url) && seen.insert($0.url).inserted }
            .prefix(Self.count))
    }

    /// Pages you opened, left out while Show Opened is off: Hister counts
    /// them in its total, so the count drops them too.
    private var hiddenOpened: Int {
        app.searchPage.showOpened ? 0 : pages.opened.filter { !app.isNotePage($0.url) }.count
    }

    @ViewBuilder private var content: some View {
        let mine = yourPages()
        let vault = shown(notes, count: Self.count)
        let webResults = webOn ? web.results : []
        if (mine.isEmpty && vault.isEmpty && webResults.isEmpty) || (holding && mineLoading) {
            Group {
                if stillLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = failure {
                    FailureView(error: error, hasServer: app.client != nil) {
                        Task { await load() }
                    }
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            .themedBackground()
        } else {
            ResultsListContainer {
                // On request only: collapsed until opened.
                if webOn, AIAnswerSection.offered(in: app, results: webResults) {
                    AIAnswerSection(query: web.query, results: webResults)
                }
                // No headings: the web's results, yours among them. No "You
                // Opened" here either: it only grew, and pushed the rest down.
                let opened = Set(pages.opened.map(\.url))
                let yours = Self.alternate(mine, vault)
                if webOn {
                    webSection(webResults, yours: yours, opened: opened)
                } else {
                    ForEach(yours, id: \.page.url) { mixed($0, opened: opened) }
                }
            }
            .listStyle(.plain)
            .themedBackground()
        }
    }

    /// Yours, in the order they go among the web's: a page, then a note, and
    /// so on (whichever runs out, the other carries on).
    struct Yours {
        let page: StoredPage
        let kind: SearchScope
    }

    static func alternate(_ pages: [StoredPage], _ notes: [StoredPage]) -> [Yours] {
        MixedResults.alternate(pages.map { Yours(page: $0, kind: .hister) }, notes.map { Yours(page: $0, kind: .notes) })
    }

    private func mixed(_ item: Yours, opened: Set<String>) -> some View {
        DocumentItem(document: item.page, opened: opened.contains(item.page.url))
            .environment(\.mixedIn, item.kind)
    }

    @ViewBuilder private func webSection(_ results: [WebResult], yours: [Yours], opened: Set<String>) -> some View {
        switch web.phase {
        case .idle, .loading:
            // Yours first, while the web is on its way.
            ForEach(yours, id: \.page.url) { mixed($0, opened: opened) }
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowBackground(palette.background)
        case .failed:
            Text("The web search didn't answer.")
                .textStyle(.callout)
                .foregroundStyle(palette.secondaryText)
                .listRowBackground(palette.background)
            ForEach(yours, id: \.page.url) { mixed($0, opened: opened) }
        case .loaded:
            if results.isEmpty {
                if yours.isEmpty {
                    Text("No web results.")
                        .textStyle(.callout)
                        .foregroundStyle(palette.secondaryText)
                        .listRowBackground(palette.background)
                }
                ForEach(yours, id: \.page.url) { mixed($0, opened: opened) }
            }
            if !web.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(web.suggestions.prefix(6), id: \.self) { suggestion in
                            Button(suggestion) { search(suggestion) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .fadesOverflow()
                .listRowBackground(palette.background)
            }
            // Yours spread evenly over the web's first page (later pages
            // arriving don't move what's been seen).
            let slots = MixedResults.counts(web: min(results.count, web.firstPageCount), mine: yours.count)
            let starts = slots.reduce(into: [0]) { $0.append($0.last! + $1) }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                WebItem(result: result, query: web.query, saved: web.saved[result.url])
                    .task {
                        await web.loadMoreIfNeeded(after: result, searx: app.searx, hister: app.client)
                    }
                if index < slots.count {
                    ForEach(yours[starts[index]..<starts[index + 1]], id: \.page.url) { mixed($0, opened: opened) }
                }
            }
            if slots.isEmpty, !results.isEmpty {
                ForEach(yours, id: \.page.url) { mixed($0, opened: opened) }
            }
            if web.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(palette.background)
            }
        }
    }
}
