import HisterKit
import SwiftUI

/// The Mac's and iPad's layout, like Mail: a sidebar to browse (Library,
/// your search, the server's collections and labels), the results,
/// and the preview of the selected page. Search is in the toolbar, with
/// its scopes. With Settings → Preview Pane off, it's two columns and a
/// page opens in place, as on iPhone.
struct LibraryView: View {
    enum Item: Hashable {
        /// A search, by its text: the current one and the last few, each a
        /// row under Library.
        case recent
        case search(String)
        case alias(String)
        case label(String)
        case suggestedLabels
        case settings
    }

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    /// The search and selection: RootView's, so they outlive this layout.
    @Environment(SearchSession.self) private var session
    @State private var item: Item? = .recent
    /// All three columns, or the preview alone (its Full Screen button).
    @State private var columns = NavigationSplitViewVisibility.all
    #if os(macOS)
    /// The Mac's own field (`MacSearchField`) reports and takes it.
    @State private var searchFocused = false
    @State private var fieldStore = MacSearchFieldStore()
    #else
    @FocusState private var searchFocused: Bool
    #endif
    private var request = SearchRequest.shared
    // The widths the user dragged the columns to. They're the columns'
    // ideal widths: SwiftUI snaps a column back to its ideal when its
    // contents change (starting a search reset them).
    // "…2": 0 until the user drags it, and then the golden ratio of the
    // results column (144 points beside 420 read as too narrow; the saved
    // one was often macOS's own restore).
    @AppStorage("sidebarWidth2") private var sidebarWidth = 0.0
    // "…2": the default doubled; a width saved before that
    // was often a squeezed one, so it starts fresh.
    @AppStorage("resultsWidth2") private var resultsWidth = 640.0
    // The live widths, saved only once they settle and only while the
    // preview still has room: a narrow window, Split View or Slide Over
    // squeezes the columns, and that isn't the user's choice.
    @State private var windowWidth = 0.0
    @State private var liveSidebar = 0.0
    @State private var liveResults = 0.0
    /// The sidebar row, kept across launches (a search isn't).
    @SceneStorage("libraryItem") private var savedItem = "recent"
    /// The sidebar's Collections and Labels fold away (there can be
    /// dozens), and stay as left.
    @AppStorage("sidebarCollectionsOpen") private var collectionsOpen = true
    @AppStorage("sidebarLabelsOpen") private var labelsOpen = true
    /// Set while a Shortcut's search changes the scope, so the scope
    /// change doesn't run the search a second time.
    @State private var scopeSetBySearch = false

    var body: some View {
        @Bindable var session = session
        Group {
            if app.searchPage.previewPane {
                NavigationSplitView(columnVisibility: $columns) {
                    sidebar
                } content: {
                    searchField(content)
                        .environment(\.previewSelection, $session.selected)
                        // A label tag opens the label as its sidebar row.
                        .environment(\.openLabel, { item = .label($0) })
                        #if os(macOS)
                        // A floor the split view can't restore past: macOS
                        // brings back its remembered divider (it came back
                        // at 200 points) without the column's minimum.
                        .frame(minWidth: 420)
                        #endif
                        .navigationSplitViewColumnWidth(min: 420, ideal: resultsWidth, max: 960)
                        .onGeometryChange(for: Double.self) { $0.size.width } action: { liveResults = $0 }
                } detail: {
                    preview
                        .environment(\.previewFocus, PreviewFocus(isOn: columns == .detailOnly) {
                            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
                        })
                }
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    searchField(NavigationStack {
                        content
                            .withDestinations()
                            .environment(\.openLabel, { item = .label($0) })
                    })
                    // Another sidebar row starts a fresh stack, not one
                    // still showing the last row's page.
                    .id(item)
                }
            }
        }
        // Balanced: the list keeps its width, rather than the preview
        // taking the room (it was squeezed to ~170 points).
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        // The search field on the split view, not the results column: the
        // column's view changes (Library → a search), and SwiftUI rebuilt
        // a toolbar item hung on it, so the field lost the keyboard as the
        // first results came in. Its place is still the
        // leading end, over the results.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                MacSearchField(
                    text: session.within == nil ? $session.text : $session.withinText,
                    prompt: session.within.map { "Search in \($0.title)" } ?? session.scope.prompt, focused: $searchFocused,
                    width: searchWidth, store: fieldStore, typeAhead: session.within == nil) {
                    // Within a collection the list searches by itself, after a pause.
                    if session.within == nil { run() }
                    app.resultsFocusRequests += 1
                }
            }
        }
        // No title beside the field: the sidebar's row says what's shown,
        // and the toolbar's background goes, so the columns run up under
        // it.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .onGeometryChange(for: Double.self) { $0.size.width } action: { windowWidth = $0 }
        .task(id: liveSidebar) { await saveWidths() }
        .task(id: liveResults) { await saveWidths() }
        // Live: results follow the typing (Return still keeps it in Recent).
        .task(id: session.text) {
            guard session.liveQuery != nil else { return }
            try? await Task.sleep(for: SearchSession.liveDelay)
            guard !Task.isCancelled else { return }
            run(recording: false)
        }
        .onChange(of: session.scope) { _, scope in
            // A tap on the Web pill asks the web: that's on purpose.
            if scope == .web { session.webAllowed = session.text.trimmingCharacters(in: .whitespaces) }
            if scopeSetBySearch {
                scopeSetBySearch = false
            } else if case .search = item {
                run(recording: false)
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { app.reloadRecentSearches() }
        }
        .onChange(of: app.searchFocusRequests) { _, _ in searchFocused = true }
        #if os(iOS)
        // shiori://settings: the iPad's Settings is a sidebar row.
        .onChange(of: app.settingsRequests) { _, _ in item = .settings }
        // Cleared (the field's X, ⌘A and delete, Escape): back to the
        // Library's newest, the search's rows and its sidebar row let go.
        // Not while the field searches within a collection or label.
        .onChange(of: session.text) { _, new in
            guard new.trimmingCharacters(in: .whitespaces).isEmpty, session.within == nil else { return }
            session.submitted = nil
            if case .search = item { item = .recent }
        }
        #endif
        .onChange(of: item) { _, new in
            session.selected = nil
            if let new, let raw = new.storedValue { savedItem = raw }
            // An earlier search picked from the sidebar: search it again
            // (no reordering of Recent: it's being revisited, not typed).
            if case .search(let query) = new, query != session.submitted {
                session.text = query
                session.submitted = query
                session.webAllowed = query
            }
        }
        .onAppear {
            // The sidebar lists them, not only the field's suggestions.
            app.reloadRecentSearches()
            if let restored = Item(storedValue: savedItem) { item = restored }
            // Back from the tabs (an iPad widened again) with a search up.
            if let submitted = session.submitted { item = .search(submitted) }
        }
        .onChange(of: request.pending, initial: true) { _, query in
            guard let query else { return }
            request.pending = nil
            session.text = query
            // The shortcut is "Search Hister": Hister's scope, one search.
            if session.scope != .hister {
                scopeSetBySearch = true
                session.scope = .hister
            }
            run()
        }
        .task { await app.loadCardsIfNeeded() }
    }

    private func saveWidths() async {
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, windowWidth > 0 else { return }
        let columns = liveSidebar + (app.searchPage.previewPane ? liveResults : 0)
        guard windowWidth - columns >= Self.previewRoom else { return }
        // Only a width dragged to: the golden default keeps following the
        // results column until then.
        if liveSidebar > 0, abs(liveSidebar - sidebarIdeal) > 1 { sidebarWidth = liveSidebar }
        if liveResults > 0, app.searchPage.previewPane { resultsWidth = liveResults }
    }

    /// The sidebar's width: the one dragged to, else the results column's
    /// divided by the golden ratio (about 260 beside 420), within bounds.
    private var sidebarIdeal: Double {
        if sidebarWidth > 0 { return sidebarWidth }
        let results = app.searchPage.previewPane ? resultsWidth : 420
        return min(320, max(220, (results / 1.618).rounded()))
    }

    /// What the preview keeps, or the widths aren't the user's to save.
    private static let previewRoom = 360.0

    /// `recording`: into Recent (Return, a recent), not a live search.
    private func run(recording: Bool = true) {
        let query = session.text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        if recording {
            app.recordSearch(query)
            session.webAllowed = query
        }
        session.submitted = query
        item = .search(query)
        session.selected = nil
    }

    /// The search field. The iPad draws the system's on the results column,
    /// under its title, above the pills; the Mac has its own in the toolbar
    /// over the results (`MacSearchField`, set on the split view). No
    /// suggestions under it: recent searches
    /// are in the sidebar. The scopes sit on the results as pills, not in a
    /// bar that appears with the field: that stacked on the Library's own
    /// switch and pushed the column down (Mac).
    private func searchField(_ column: some View) -> some View {
        #if os(macOS)
        return column
        #else
        @Bindable var session = session
        return column
            .searchable(
                text: session.within == nil ? $session.text : $session.withinText, placement: .toolbar,
                prompt: Text(session.within.map { "Search in \($0.title)" } ?? session.scope.prompt))
            // Query words are case-sensitive (label:books), and Hister
            // remembers what you opened by the exact query.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .searchFocused($searchFocused)
            .onSubmit(of: .search) {
                if session.within == nil { run() }
                app.resultsFocusRequests += 1
            }
        #endif
    }

    #if os(macOS)
    /// The field spans the results column with even margins (it starts 8
    /// points in); the two-column layout (Preview Pane off) has no results
    /// column to span.
    private var searchWidth: CGFloat {
        let column = app.searchPage.previewPane && liveResults > 0 ? liveResults : 420
        return max(220, column - 16)
    }
    #endif

    // MARK: Sidebar

    /// Recent's, five at most, led by the current search only when it
    /// isn't one of them (a live search, not yet kept). A recent one keeps
    /// its place when picked: lifting it to the top left the pointer on
    /// the search just left.
    private var sidebarSearches: [String] {
        let recent = app.recentSearches
        var out: [String] = []
        if let current = session.submitted, !recent.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            out.append(current)
        }
        for query in recent where !out.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
            out.append(query)
        }
        return Array(out.prefix(5))
    }

    private var sidebar: some View {
        List(selection: $item) {
            Section {
                // The Library has the All / Pages / Notes filter.
                Label { Text("Library") } icon: { RowIcon(symbol: "books.vertical") }
                    .tag(Item.recent)
                // The search on screen, then the last few (up to five in
                // all), so going back to one is a click.
                ForEach(sidebarSearches, id: \.self) { query in
                    Label { Text(query) } icon: { RowIcon(symbol: "magnifyingglass") }
                        .lineLimit(1)
                        .tag(Item.search(query))
                }
            }
            if app.rules.aliases.isEmpty, app.rules.labels.isEmpty {
                // As the iPhone's Labels tab says it: why there are none.
                Section {
                    if app.client == nil {
                        Text("Add your Hister server in Settings.")
                            .foregroundStyle(palette.secondaryText)
                    } else {
                        Text("No labels from Hister yet.")
                            .foregroundStyle(palette.secondaryText)
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            Task { await app.reloadRules() }
                        }
                    }
                } header: {
                    SidebarDivider(title: "Labels")
                }
            }
            if app.ai.enabled && (app.ai.autoLabel || app.ai.autoCollections) || !app.labeller.state.pending.isEmpty
                || !app.labeller.state.collectionProposals.isEmpty
            {
                Section {
                    SuggestedLabelsRow().tag(Item.suggestedLabels)
                } header: {
                    SidebarDivider()
                }
            }
            if !app.rules.aliases.isEmpty {
                Section(isExpanded: $collectionsOpen) {
                    ForEach(app.rules.aliases.keys.sorted(), id: \.self) { alias in
                        CollectionLabel(name: alias).tag(Item.alias(alias))
                            .contextMenu { FeedButtons(feed: app.feedURL(query: alias, title: CollectionIcon.title(for: alias))) }
                    }
                } header: {
                    // Folded, it says how many are inside. Larger and in the
                    // text colour: the sidebar's small grey headings were
                    // hard to see.
                    SidebarDivider(title: collectionsOpen ? "Collections" : "Collections (\(app.rules.aliases.count))")
                }
            }
            if !app.rules.labels.isEmpty {
                Section(isExpanded: $labelsOpen) {
                    ForEach(app.rules.labels, id: \.self) { label in
                        Label {
                            Text(label)
                        } icon: {
                            RowDot(color: palette.chipColor(for: label))
                        }
                        .tag(Item.label(label))
                        .contextMenu { FeedButtons(feed: app.feedURL(query: "label:\(label)", title: label)) }
                    }
                } header: {
                    SidebarDivider(title: labelsOpen ? "Labels" : "Labels (\(app.rules.labels.count))")
                }
            }
            #if os(iOS)
            // The Mac has its own Settings window (⌘,).
            Section {
                Label { Text("Settings") } icon: { RowIcon(symbol: "gearshape") }
                    .tag(Item.settings)
            } header: {
                SidebarDivider()
            }
            #endif
        }
        .navigationTitle("Shiori")
        #if os(macOS)
        // A floor macOS can't restore past, as the results column has: it
        // restores its own remembered divider over the ideal width (144
        // points), which neither a new identity nor clearing
        // the split view's saved frames changed.
        .frame(minWidth: 220)
        #endif
        .navigationSplitViewColumnWidth(min: 220, ideal: sidebarIdeal, max: 360)
        #if os(iOS)
        // The iPad's Add Page (the iPhone has its + tab, the Mac File →
        // Add Page…): on the sidebar, not the list, whose bar has none.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Page…", systemImage: "plus") { app.addPageRequests += 1 }
                    .help("Save a page in Hister by its address")
            }
        }
        #endif
        .onGeometryChange(for: Double.self) { $0.size.width } action: { liveSidebar = $0 }
        .refreshable { await app.reloadRules() }
    }

    // MARK: Results

    @ViewBuilder private var content: some View {
        @Bindable var session = session
        switch item ?? .recent {
        case .recent:
            // The sidebar's selected row already says Library.
            RecentScreen(titled: false)
        case .search:
            if let submitted = session.submitted {
                SearchResultsView(query: submitted, scope: session.scope) { session.scope = $0 } search: { suggestion in
                    session.text = suggestion
                    run()
                }
                .id("\(session.scope.rawValue):\(submitted)")
                .topChoices("Search in", selection: $session.scope, choices: app.searchScopes, title: \.title, tint: \.tint,
                            count: { session.count(for: $0) })
                .navigationTitle(submitted)
            }
        case .alias(let alias):
            ResultsScreen(route: QueryRoute(title: CollectionIcon.title(for: alias), query: alias), windowField: true)
                .id(alias)
        case .label(let label):
            ResultsScreen(route: QueryRoute(title: label, query: "label:\(label)"), windowField: true)
                .id(label)
        case .suggestedLabels:
            SuggestedLabelsView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: Preview

    #if os(macOS)
    private static let previewHint = "Select a page to preview it. Double-click to open it."
    #else
    private static let previewHint = "Select a page to preview it."
    #endif

    @ViewBuilder private var preview: some View {
        if let selected = session.selected, !app.deletedURLs.contains(selected.url) {
            NavigationStack {
                DocumentView(document: selected)
            }
            .id(selected.url)
        } else {
            ContentUnavailableView(
                "No Page Selected", systemImage: "doc.text.magnifyingglass",
                description: Text(Self.previewHint))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
        }
    }
}

extension LibraryView.Item {
    /// For @SceneStorage: the rows worth coming back to (not a search).
    var storedValue: String? {
        switch self {
        case .recent: "recent"
        case .alias(let alias): "alias:" + alias
        case .label(let label): "label:" + label
        case .search, .settings, .suggestedLabels: nil
        }
    }

    init?(storedValue: String) {
        if storedValue == "recent" {
            self = .recent
        } else if storedValue.hasPrefix("alias:") {
            self = .alias(String(storedValue.dropFirst(6)))
        } else if storedValue.hasPrefix("label:") {
            self = .label(String(storedValue.dropFirst(6)))
        } else {
            return nil
        }
    }
}

/// What the search field's suggestions load for: the text, while the
/// field has the keyboard.
private struct SuggestionsKey: Equatable {
    let text: String
    let focused: Bool
}

/// A line between the sidebar's sections, over the section's heading if it
/// has one: the sections ran together and read as one ragged list. The
/// web app's `#sidebar h2` draws the same line.
private struct SidebarDivider: View {
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let title {
                Text(title).sidebarHeading()
            }
        }
        .padding(.top, 4)
    }
}

private extension View {
    /// The sidebar's section titles: the rows' size and colour, semibold,
    /// so they read clearly without outweighing the rows (the system's
    /// small grey ones were hard to see; headline size in the theme's
    /// lavender clashed with the rows' white).
    func sidebarHeading() -> some View {
        self
            .textStyle(.body, weight: .semibold)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}
