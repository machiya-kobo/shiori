import HisterKit
import SwiftUI

/// Search → All: the top of your pages and of your notes, then the web, as
/// General is on Safari's results page. The counts are the same settings
/// (Your Pages / Your Notes → How Many), and Web Results switches the web
/// off here too. Each section's last row opens its own scope in full.
struct AllResults: View {
    let query: String
    let showScope: (SearchScope) -> Void
    let search: (String) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
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

    /// Your pages and your notes in All: the top five each, then a row to the
    /// full search ("How Many" is gone, here, on the search page and in the
    /// web app).
    static let count = 5

    /// Not for a search of Hister syntax alone (label:bsd, @retro).
    private var webOn: Bool { app.allSearch.webResults && app.searx != nil && !web.query.isEmpty }

    var body: some View {
        content
            .task(id: "\(query)|\(app.searchPage.niwaURL)") { await load() }
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                holding = false
            }
            .refreshable { await load() }
            .topBar {
                ListControls(model: pages, title: query, ordering: false) {}
            }
            .resultActions(query: query)
    }

    private func load() async {
        pages.semantic = app.semanticOn
        pages.webSuggestions = { [app] in await app.webSuggestions(for: $0) }
        notes.webSuggestions = { [app] in await app.webSuggestions(for: $0) }
        notes.kura = app.notesKura
        async let mine: Void = pages.load(using: app.client)
        async let vault: Void = notes.load(using: app.client)
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
                // No "You Opened" here: it only grows, and pushed the rest down
                // It's on Pages and Opened.
                if !mine.isEmpty {
                    Section {
                        let opened = Set(pages.opened.map(\.url))
                        ForEach(mine) { DocumentItem(document: $0, opened: opened.contains($0.url)) }
                    } header: {
                        // Hister's total has no notes: they come from Kura (`SearchText`).
                        let pageTotal = max(pages.total - hiddenOpened, mine.count)
                        header(pages.respelledAs.map { "Your Pages · for “\($0)”" } ?? "Your Pages",
                               count: pageTotal, tint: SearchScope.hister.tint,
                               more: pageTotal > mine.count ? { showScope(.hister) } : nil)
                    }
                }
                if !vault.isEmpty {
                    Section {
                        ForEach(vault) { DocumentItem(document: $0) }
                    } header: {
                        header(notes.respelledAs.map { "Your Notes · for “\($0)”" } ?? "Your Notes",
                               count: max(notes.total, vault.count), tint: SearchScope.notes.tint,
                               more: notes.total > vault.count ? { showScope(.notes) } : nil)
                    }
                }
                if webOn {
                    Section {
                        webSection(webResults)
                    } header: {
                        header("Web")
                    }
                }
            }
            .listStyle(.plain)
            .themedBackground()
        }
    }

    @ViewBuilder private func webSection(_ results: [WebResult]) -> some View {
        switch web.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowBackground(palette.background)
        case .failed:
            Text("The web search didn't answer.")
                .textStyle(.callout)
                .foregroundStyle(palette.secondaryText)
                .listRowBackground(palette.background)
        case .loaded:
            if results.isEmpty {
                Text("No web results.")
                    .textStyle(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .listRowBackground(palette.background)
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
            ForEach(results) { result in
                WebItem(result: result, query: web.query, saved: web.saved[result.url])
                    .task {
                        await web.loadMoreIfNeeded(after: result, searx: app.searx, hister: app.client)
                    }
            }
            if web.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(palette.background)
            }
        }
    }

    /// A section's heading. Your Pages and Your Notes wear their pill's
    /// colour, with the full count, as on the search page and in the web
    /// app (a faint tint, the text and an outline).
    /// `more`: the count is a link to the full search (Pages or Notes), in
    /// place of a "More in …" row under the five, which looked out of place
    /// there.
    @ViewBuilder
    private func header(_ title: String, count: Int? = nil, tint: Palette.Tint? = nil, more: (() -> Void)? = nil) -> some View {
        if let tint {
            let color = palette.tint(tint)
            HStack {
                Text(title)
                    .textStyle(.subheadline, weight: .semibold)
                Spacer()
                if let count {
                    let label = "\(count.formatted()) \(count == 1 ? "result" : "results")"
                    if let more {
                        Button(action: more) {
                            HStack(spacing: 3) {
                                Text(label)
                                Image(systemName: "chevron.forward").imageScale(.small)
                            }
                            .textStyle(.footnote, weight: .semibold)
                        }
                        .buttonStyle(.plain)
                        .help("Show all of them")
                    } else {
                        Text(label)
                            .textStyle(.footnote)
                    }
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color))
        } else {
            Text(title)
                .textStyle(.subheadline, weight: .semibold)
                .foregroundStyle(palette.secondaryText)
        }
    }
}
