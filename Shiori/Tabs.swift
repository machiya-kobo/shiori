import HisterKit
import SwiftUI

/// A search to show as its own list: an alias, a label, or a query.
struct QueryRoute: Hashable {
    let title: String
    let query: String
}

/// The app's tabs: a tab bar on iPhone, a sidebar on iPad and Mac.
struct RootView: View {
    /// `add` is an action, not a place: choosing it opens Add Page and
    /// stays on the tab you were on.
    enum Tab: String, Hashable { case recent, labels, add, settings }

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    /// The tab, kept across launches.
    @SceneStorage("tab") private var selection: Tab = .recent
    /// Held here, above the layout choice, so a layout switch keeps it.
    @State private var session = SearchSession()
    @State private var addingPage = false
    /// Save This Note's Links on screen; `app.saveLinksRequest` waits until
    /// no other sheet is open (one can't open over another from here).
    @State private var savingLinks: SaveLinksTarget?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    #endif
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        layout
            .environment(session)
            .focusedSceneValue(\.searchSession, session)
            .overlay(alignment: .bottom) {
                if let pending = app.deletes.pending {
                    UndoToast(title: pending.document.displayTitle) { app.deletes.undo() }
                        .id(pending.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: app.deletes.pending)
            .alert(
                "Couldn't Delete",
                isPresented: Binding(get: { app.deletes.failure != nil }, set: { if !$0 { app.deletes.failure = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(app.deletes.failure ?? "")
            }
            .sheet(isPresented: $addingPage) { AddPageSheet() }
            .sheet(item: $savingLinks) { target in
                SaveLinksView(target: target)
            }
            .onChange(of: app.saveLinksRequest, initial: true) { _, target in
                if target != nil { Task { await presentSaveLinks() } }
            }
            .onChange(of: app.addPageRequests) { _, _ in addingPage = true }
            // The chosen pill gone (Show Opened off, or hidden in Settings →
            // Search → Pills): back to All.
            .onChange(of: app.searchScopes) { _, scopes in
                if !scopes.contains(session.scope) { session.scope = .all }
            }
            .onChange(of: app.settingsRequests) { _, _ in
                #if os(macOS)
                openSettings()
                #else
                // The three columns open their Settings row themselves; the
                // tabs have a Settings tab.
                if !(UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular) { selection = .settings }
                #endif
            }
            .task(id: app.serverURL) {
                // Labels for the lists, and Konbini's cards so every note shows its place.
                await app.loadRulesIfNeeded()
                await app.loadCardsIfNeeded()
            }
            #if os(iOS)
            // The app switcher's snapshot shows nothing of your pages or searches.
            .overlay {
                if scenePhase != .active {
                    palette.background.ignoresSafeArea()
                }
            }
            #endif
    }

    /// A save-links request (a note's menu, or a `shiori://save-links`
    /// link that arrived while Add Page, Settings or a picker was open):
    /// shown once nothing else is, rather than dropped.
    private func presentSaveLinks() async {
        while addingPage || savingLinks != nil || Self.sheetIsOpen {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        guard let target = app.saveLinksRequest else { return }
        app.saveLinksRequest = nil
        savingLinks = target
    }

    /// A sheet open anywhere in the app's windows in front.
    private static var sheetIsOpen: Bool {
        #if os(macOS)
        NSApp.windows.contains { $0.attachedSheet != nil }
        #else
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
        #endif
    }

    /// The Mac, and an iPad with the room, get the three columns; the
    /// iPhone, and an iPad in Slide Over or a narrow Split View, the tabs
    /// (by width, not by device).
    @ViewBuilder private var layout: some View {
        #if os(macOS)
        LibraryView()
        #else
        if UIDevice.current.userInterfaceIdiom == .pad, sizeClass == .regular {
            LibraryView()
        } else {
            tabs
        }
        #endif
    }

    /// The iPhone: Library (with the search field at its top), Labels, +
    /// to add a page, and Settings. The tabs' own screens have no title
    /// row: the search field is the top of the Library.
    private var tabs: some View {
        TabView(selection: Binding(get: { selection }, set: { tab in
            if tab == .add { addingPage = true } else { selection = tab }
        })) {
            SwiftUI.Tab("Library", systemImage: "books.vertical", value: Tab.recent) {
                NavigationStack {
                    SearchScreen()
                        .withDestinations()
                        .tabRoot()
                }
            }
            SwiftUI.Tab("Labels", systemImage: "tag", value: Tab.labels) {
                NavigationStack {
                    LabelsScreen()
                        .withDestinations()
                        .tabRoot()
                }
            }
            SwiftUI.Tab("Add Page", systemImage: "plus", value: Tab.add) {
                Color.clear
            }
            // Theme, appearance, text size and the rest: one tap away.
            SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                NavigationStack {
                    SettingsView()
                        #if os(iOS)
                        // A small title, not a large heading: it names the
                        // pages for Back.
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .minimizingTabBarOnScroll()
        .onChange(of: SearchRequest.shared.pending, initial: true) { _, query in
            // The Search Hister shortcut: to the Library, whose field runs it.
            if query != nil { selection = .recent }
        }
    }
}

extension View {
    /// A tab's own screen on the iPhone: no navigation bar, so no title
    /// row; its search field (`TabSearchField`) is the top. The title still
    /// names it for a pushed list's Back. Settings is a tab of its own; the
    /// Mac has its Settings window, the iPad a sidebar row.
    func tabRoot() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Where stored pages and query lists open, for every stack.
    func withDestinations() -> some View {
        navigationDestination(for: StoredPage.self) { DocumentView(document: $0) }
            .navigationDestination(for: QueryRoute.self) { ResultsScreen(route: $0) }
    }

    /// Reading app: let the tab bar recede while scrolling down (iOS 26+).
    @ViewBuilder func minimizingTabBarOnScroll() -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// The Library: what Hister has, by when it was last seen (a reload
/// counts, so a tab Safari restores moves up), scrolling back to the
/// start. All, your web pages only (Pages), or your notes.
struct RecentScreen: View {
    @Environment(AppState.self) private var app
    @Environment(SearchSession.self) private var session
    // One list per choice, so switching back doesn't start over.
    // All: your pages and notes, newest first; Pages from Hister, Notes
    // from Kura.
    // Each keeps its first page for offline reading (`OfflineStore`).
    @State private var all = ResultsModel(query: "*", sort: .newest, source: .all, offlineName: "all")
    @State private var pages = ResultsModel(query: "*", sort: .newest, offlineName: "pages")
    @State private var notes = ResultsModel(query: "*", sort: .newest, source: .notes, offlineName: "notes")
    /// The folders Hister watches, newest first.
    @State private var files = ResultsModel(query: LocalFiles.query(""), sort: .newest)
    /// False beside the sidebar, whose selected row already says Library:
    /// the column's title repeated it.
    var titled = true

    var body: some View {
        @Bindable var session = session
        Group {
            switch session.scope {
            case .all: list(all, title: "Library")
            case .hister: list(pages, title: "Pages")
            case .notes: list(notes, title: "Notes")
            case .web:
                ContentUnavailableView(
                    "Search the Web", systemImage: "globe",
                    description: Text("Type in the search field to search the web."))
                    // The whole column, as the other empty states: sized to
                    // itself, the Mac's column shrank around it and the pills
                    // floated mid-window.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
            case .smallweb:
                ContentUnavailableView(
                    "Search the Small Web", systemImage: "leaf",
                    description: Text("Type in the search field and press Return to search Gemini and Gopher."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
            // Your repos, newest first, with the Code pill's filters.
            case .code:
                CodeResults(query: "", sort: .newest)
            case .files:
                ResultsList(model: files, title: "Files") {
                    ContentUnavailableView(
                        "No Files", systemImage: "folder",
                        description: Text("Files appear here once your Hister server watches a folder."))
                }
                .id(ObjectIdentifier(files))
            case .opened: OpenedListView()
            }
        }
        // The same row as a search's, and the same choice: typing searches
        // whichever is picked.
        .topChoices("Show", selection: $session.scope, choices: app.searchScopes, title: \.title, tint: \.tint)
        .navigationTitle("Library")
        #if os(iOS)
        // The Mac removes every title at the split view: a change here
        // changed the toolbar's makeup, and SwiftUI rebuilt its search
        // field mid-typing.
        .toolbar(removing: titled ? nil : .title)
        #endif
        // Add Page: the + tab on the iPhone, File → Add Page… (⇧⌘A) on the
        // Mac, a + atop the sidebar on the iPad.
    }

    private func list(_ model: ResultsModel, title: String) -> some View {
        ResultsList(model: model, title: title) {
            ContentUnavailableView(
                "Nothing Yet", systemImage: "clock",
                description: Text("Pages you visit in Safari appear here once Shiori sends them."))
        }
        .id(ObjectIdentifier(model))
    }
}

/// The results for one alias, label or query.
struct ResultsScreen: View {
    let route: QueryRoute
    /// Shown in the three columns (Mac, iPad), where the window's own
    /// field searches within this list (`SearchSession.within`): then the
    /// list has no field of its own.
    var windowField = false
    @Environment(\.palette) private var palette
    @Environment(SearchSession.self) private var session
    @State private var model: ResultsModel
    /// Words to search within this list ("Search in bsd"), and the ones
    /// last searched (after a pause in typing).
    @State private var text = ""
    @State private var searched = ""
    @FocusState private var searching: Bool

    init(route: QueryRoute, windowField: Bool = false) {
        self.route = route
        self.windowField = windowField
        _model = State(initialValue: ResultsModel(query: route.query, sort: .newest, filterable: true))
    }

    /// The words typed: the window's field, or this list's own.
    private var typed: String { windowField ? session.withinText : text }

    var body: some View {
        ResultsList(model: model, title: route.title) {
            ContentUnavailableView(
                searched.isEmpty ? "No Pages" : "Nothing Matches", systemImage: "tray",
                description: Text(searched.isEmpty ? route.query : "Nothing in \(route.title) matches “\(searched)”."))
        }
        // A fresh list (and load) for each search's model.
        .id(ObjectIdentifier(model))
        // Search within the list: its own field
        // on the iPhone; in the three columns the window's field does it.
        .topBar(if: !windowField) {
            TabSearchField(prompt: "Search in \(route.title)", text: $text, focus: $searching) {
                searched = text.trimmingCharacters(in: .whitespaces)
            }
        }
        .onAppear {
            guard windowField else { return }
            session.within = route
            session.withinText = ""
            session.withinSubmitted = ""
        }
        .onDisappear {
            if windowField, session.within == route { session.within = nil; session.withinText = "" }
        }
        // On Return (the window's field, or this list's own), never while
        // typing; clearing the field shows the whole list at once.
        .onChange(of: typed) { _, now in
            if now.trimmingCharacters(in: .whitespaces).isEmpty { searched = "" }
        }
        .onChange(of: session.withinSubmitted) { _, words in
            guard windowField, session.within == route else { return }
            searched = words.trimmingCharacters(in: .whitespaces)
        }
        .onChange(of: searched) { _, words in
            // Best match while searching, the newest first while browsing.
            model = ResultsModel(
                query: words.isEmpty ? route.query : "\(route.query) \(words)",
                sort: words.isEmpty ? .newest : .relevance, filterable: true)
        }
        .navigationTitle(route.title)
    }
}

/// Browse by the server's aliases and topic labels.
struct LabelsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    /// Narrows the lists by name as you type (the Library's pinned field,
    /// here for labels: there can be many).
    @State private var find = ""
    @FocusState private var finding: Bool

    private func matches(_ name: String) -> Bool {
        let typed = find.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty || name.localizedCaseInsensitiveContains(typed)
    }

    private var collections: [String] {
        app.rules.aliases.keys.sorted().filter { matches(CollectionIcon.title(for: $0)) }
    }

    private var labels: [String] { app.rules.labels.filter(matches) }

    var body: some View {
        List {
            if find.isEmpty,
               app.ai.enabled && (app.ai.autoLabel || app.ai.autoCollections) || !app.labeller.state.pending.isEmpty
                || !app.labeller.state.collectionProposals.isEmpty
            {
                Section {
                    NavigationLink {
                        SuggestedLabelsView()
                    } label: {
                        SuggestedLabelsRow()
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.surface)
                }
            }
            if !collections.isEmpty {
                Section("Collections") {
                    ForEach(collections, id: \.self) { alias in
                        NavigationLink(value: QueryRoute(title: CollectionIcon.title(for: alias), query: alias)) {
                            CollectionLabel(name: alias)
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.surface)
                        .contextMenu { FeedButtons(feed: app.feedURL(query: alias, title: CollectionIcon.title(for: alias))) }
                    }
                }
            }
            if !labels.isEmpty {
            Section("Labels") {
                ForEach(labels, id: \.self) { label in
                    NavigationLink(value: QueryRoute(title: label, query: "label:\(label)")) {
                        // A dot and the name, as the Mac's and the web app's sidebars
                        // list them; tags are for labels on pages.
                        Label {
                            Text(label)
                                .foregroundStyle(palette.text)
                        } icon: {
                            RowDot(color: palette.chipColor(for: label))
                        }
                    }
                    .listRowBackground(palette.surface)
                    .contextMenu { FeedButtons(feed: app.feedURL(query: "label:\(label)", title: label)) }
                }
            }
            }
        }
        .themedBackground()
        .topBar { TabSearchField(prompt: "Find a Label", text: $find, focus: $finding) }
        .overlay {
            if !app.rules.labels.isEmpty, collections.isEmpty, labels.isEmpty {
                ContentUnavailableView.search(text: find)
            } else if app.rules.labels.isEmpty {
                if app.client == nil {
                    FailureView(error: .unreachable, hasServer: false) {}
                } else {
                    ContentUnavailableView {
                        Label("No Labels Yet", systemImage: "tag")
                    } description: {
                        Text("Labels come from your Hister server's aliases.")
                    } actions: {
                        Button("Try Again") { Task { await app.reloadRules() } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .pullToRefresh { await app.reloadRules() }
        .navigationTitle("Labels")
    }
}

/// The iPhone's Library tab: the Library, with a search field at the top
/// that shows a search's results in its place (clearing the field brings
/// the Library back). Hister's query syntax; runs on Return. The Mac and
/// iPad search from `LibraryView`.
struct SearchScreen: View {
    @Environment(AppState.self) private var app
    @Environment(SearchSession.self) private var session
    @FocusState private var searchFocused: Bool
    private var request = SearchRequest.shared

    var body: some View {
        @Bindable var session = session
        Group {
            if let submitted = session.submitted {
                SearchResultsView(query: submitted, scope: session.scope) { session.scope = $0 } search: { suggestion in
                    session.text = suggestion
                    run()
                }
                .id("\(session.scope.rawValue):\(submitted)")
                // Always visible, not just while the field is active (as
                // .searchScopes would be).
                .topChoices("Search in", selection: $session.scope, choices: app.searchScopes, title: \.title, tint: \.tint,
                            count: { session.count(for: $0) })
                .navigationTitle("Search")
            } else {
                RecentScreen()
            }
        }
        // Above the pills. Query words are case-sensitive (label:books),
        // and Hister remembers what you opened by the exact query, so the
        // field neither capitalises nor corrects.
        .topBar {
            TabSearchField(prompt: session.scope.prompt, text: $session.text, focus: $searchFocused) { run() }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { app.reloadRecentSearches() }
        }
        .onChange(of: session.scope) { _, scope in
            // A tap on the Web pill asks the web: that's on purpose.
            if scope == .web { session.webAllowed = session.text.trimmingCharacters(in: .whitespaces) }
            run(recording: false)
        }
        .task { await app.loadCardsIfNeeded() }
        .onChange(of: session.text) { _, new in
            if new.isEmpty { session.submitted = nil }
        }
        // No search while typing (the user's call): Return or the field's
        // magnifier runs it, and the field keeps the keyboard meanwhile.
        .onChange(of: request.pending, initial: true) { _, query in
            guard let query else { return }
            request.pending = nil
            session.text = query
            // The shortcut is "Search Hister", so it searches Hister.
            if session.scope == .hister { run() } else { session.scope = .hister }
        }
    }
}

extension SearchScreen {
    /// `recording`: into Recent (Return, a recent, a tip), not a live search.
    private func run(recording: Bool = true) {
        let query = session.text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            session.submitted = nil
            return
        }
        if recording {
            app.recordSearch(query)
            session.webAllowed = query
        }
        session.submitted = query
    }
}

/// The iPhone's search fields: the tabs' (at the very top: the tabs have
/// no title row) and a pushed list's. A field of the app's own:
/// `.searchable` lives in the navigation bar's drawer, which kept an empty
/// title row above it, and a search-role tab draws inline in iOS 27's tab
/// bar. As the rooms' and Kagi's: an X once there's text, and a magnifier
/// at the end that submits, as Return does (`submit`; without one it
/// puts the keyboard away). No capitalisation or correction (Hister
/// matches the exact words); a tap into it selects what's there, as every
/// search field does.
struct TabSearchField: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var submit: () -> Void = {}
    @Environment(\.palette) private var palette
    @State private var selection: TextSelection?
    /// The system's search field height (iOS 26's glass field), growing
    /// with the text size.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 48

    var body: some View {
        HStack(spacing: 4) {
            TextField(prompt, text: $text, selection: $selection)
                .textFieldStyle(.plain)
                .focused(focus)
                .submitLabel(.search)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(go)
            if !text.isEmpty {
                fieldButton("Clear", systemImage: "xmark") { text = "" }
            }
            fieldButton("Search", systemImage: "magnifyingglass", action: go)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: height)
        .modifier(SearchFieldShape())
        .padding(.horizontal)
        .padding(.top, 6)
        // Room before the pills, as Apple's apps leave under a search field.
        .padding(.bottom, 6)
        .topBarBackground()
        .onChange(of: focus.wrappedValue) { _, focused in
            guard focused, !text.isEmpty else { return }
            // After the tap has placed its caret, or it would undo this.
            Task { selection = TextSelection(range: text.startIndex..<text.endIndex) }
        }
    }

    /// Return or the magnifier: the field's own submit, and the keyboard away.
    private func go() {
        submit()
        focus.wrappedValue = false
    }

    /// A thin glyph in the secondary colour, 32 points with 44 to tap.
    private func fieldButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .textStyle(.body)
            .foregroundStyle(palette.secondaryText)
            .frame(width: 32, height: 32)
            .contentShape(.rect.inset(by: -6))
    }
}

/// The field's capsule: Liquid Glass on iOS 26 and later, as the system's
/// search field is (chrome, not content), else the theme's surface.
private struct SearchFieldShape: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(palette.surface, in: .capsule)
        }
        #else
        content.background(palette.surface, in: .capsule)
        #endif
    }
}

/// What the empty search screen teaches: the query syntax. Each tip runs.
struct SearchTips: View {
    let run: (String) -> Void
    @Environment(\.palette) private var palette

    private let tips: [(String, String)] = [
        ("@crafts", "A collection: all the labels it names"),
        ("label:books", "Pages with one label (exact, case-sensitive)"),
        ("domain:www.example.com", "One site; the whole host"),
        ("added:>2026-01-01", "Added after a date"),
        ("rust -crate", "Leave out pages with a word"),
    ]

    var body: some View {
        List {
            Section("Try") {
                ForEach(tips, id: \.0) { tip in
                    Button {
                        run(tip.0)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.0)
                                .textStyle(.body, design: .monospaced)
                                .foregroundStyle(palette.accent)
                            Text(tip.1)
                                .textStyle(.subheadline)
                                .foregroundStyle(palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Runs this search")
                    .listRowBackground(palette.surface)
                }
            }
        }
    }
}

/// "Deleted “…”" with Undo, for the few seconds before the delete goes to
/// Hister (`AppState.deletes`).
struct UndoToast: View {
    let title: String
    let undo: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash")
                .foregroundStyle(palette.danger)
            Text("Deleted “\(title)”")
                .textStyle(.subheadline)
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Button("Undo", action: undo)
                .textStyle(.subheadline, weight: .semibold)
                .foregroundStyle(palette.accent)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.raised, in: .capsule)
        .overlay(Capsule().strokeBorder(palette.secondaryText.opacity(0.25)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(.horizontal, 20)
        #if os(iOS)
        // Clear of the iPhone's tab bar.
        .padding(.bottom, 90)
        #else
        .padding(.bottom, 20)
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", undo)
    }
}
