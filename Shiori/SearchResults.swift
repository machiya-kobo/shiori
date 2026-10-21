import HisterKit
import SwiftUI
import os

/// Where a search looks: all of it (your pages, your notes, then the
/// web), everything Hister has, only the vault's notes, or only the web.
/// The one row of choices over every list, browsing or searching (it had
/// been two rows, All · Pages · Notes · Opened for the Library and All ·
/// Pages · Notes · Web for a search).
/// Browsing, All, Pages and Notes are the Library, Web asks for a search,
/// and Opened is what you opened; searching, each one narrows the search.
enum SearchScope: String, Hashable, CaseIterable, Identifiable {
    case all, hister, notes, web, images, videos, news, smallweb, files, code, media, opened

    var id: Self { self }

    /// Its key in the pills' setting (`PillOrder.keys`).
    var pillKey: String { self == .hister ? "pages" : rawValue }

    /// The Safari page's colours: All cyan, your pages blue, notes Kura's
    /// orange, the web Shiori's lens yellow (the Machiya rooms' colours:
    /// things wear their room's). `hister` is your pages, called Pages everywhere
    /// (the Library, the search page, the web app): Hister is the server.
    var tint: Palette.Tint {
        switch self {
        case .all: .cyan
        case .hister: .blue
        case .notes: .orange
        case .web: .yellow
        // The web's own tabs, in the search page's colours: Images green,
        // Videos red, News purple.
        case .images: .green
        case .videos: .red
        case .news: .purple
        // Gemini and Gopher: the web's neighbour, teal.
        case .smallweb: .teal
        // The folders Hister watches: green, a hue no room wears.
        case .files: .green
        // Your repos (code-import): red, the one hue left.
        case .code: .red
        // Your libraries and what you played: purple.
        case .media: .purple
        // What you opened: the rooms' slate, so it never looks like Media.
        case .opened: .slate
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .hister: "Pages"
        case .notes: "Notes"
        case .web: "Web"
        case .images: "Images"
        case .videos: "Videos"
        case .news: "News"
        case .smallweb: "Small Web"
        case .files: "Files"
        case .code: "Code"
        case .media: "Media"
        case .opened: "Opened"
        }
    }

    var prompt: String {
        switch self {
        case .all: "Search All"
        case .hister: "Search Your Pages"
        case .notes: "Search Notes"
        case .web: "Search the Web"
        case .images: "Search Images"
        case .videos: "Search Videos"
        case .news: "Search News"
        case .smallweb: "Search Gemini and Gopher"
        case .files: "Search Your Files"
        case .code: "Search Your Code"
        case .media: "Search Your Media"
        case .opened: "Search What You Opened"
        }
    }

    /// A tab that asks the web: a tap on its pill is a search on purpose (each one counts).
    var searchesWeb: Bool { [.web, .images, .videos, .news].contains(self) }

    /// SearXNG's category for the web's own tabs (nil for Web, its general search).
    var webCategory: String? {
        switch self {
        case .images, .videos, .news: rawValue
        default: nil
        }
    }
}

/// The search on screen: what's typed, what's been run, where it looks,
/// and (beside a preview pane) the selected page. Owned by `RootView` and
/// shared by both layouts, so an iPad crossing from three columns to the
/// tabs (Split View, Stage Manager) keeps it instead of starting over.
extension View {
    /// Runs `action` with the field's new text. A modifier of its own, not
    /// an `onChange(of: session.text)` in a screen's body: that made the
    /// whole screen (its lists with it) read the text, and redraw on every
    /// keystroke.
    func onSessionTextChange(_ action: @escaping (String) -> Void) -> some View {
        modifier(SessionTextChange(action: action))
    }
}

private struct SessionTextChange: ViewModifier {
    let action: (String) -> Void
    @Environment(SearchSession.self) private var session

    func body(content: Content) -> some View {
        content.onChange(of: session.text) { _, new in action(new) }
    }
}

@Observable final class SearchSession {
    var text = ""
    /// The search being shown, if any.
    var submitted: String?
    /// The search run on purpose (Return, a recent search, the Web pill),
    /// the only one the web is asked for: each web search counts (a paid
    /// search API would charge it), so typing alone searches your pages and
    /// notes. Frugal, as AI is.
    var webAllowed: String?
    var scope = SearchScope.all
    /// Images', Videos' and News' order and filters, kept per tab for the session (`WebChoices`).
    var webChoices: [SearchScope: WebChoices.Choices] = [:]
    var selected: StoredPage?
    /// The page open full-screen in a stack (the tabs, the two columns), so
    /// widening to the three columns shows it in the pane.
    var reading: StoredPage?
    /// A collection's or label's list on screen in the three columns (Mac,
    /// iPad): the window's one field then searches within it ("Search in
    /// <collection>"), with its own words, instead of a second field in the
    /// list. Nil elsewhere.
    var within: QueryRoute?
    var withinText = ""
    /// All's totals for the search on screen (Pages', Notes'), for their pills.
    private(set) var counts: [SearchScope: Int] = [:]
    private var countsQuery: String?

    func setCounts(_ counts: [SearchScope: Int], for query: String) {
        self.counts = counts
        countsQuery = query
    }

    /// A pill's count, only while it belongs to the search shown.
    func count(for scope: SearchScope) -> Int? {
        guard countsQuery == submitted, let n = counts[scope], n > 0 else { return nil }
        return n
    }
    /// The words searched within a collection or label (Mac, iPad: the
    /// window's field), set on Return: `ResultsScreen` searches them.
    var withinSubmitted = ""
}

/// One search's results in one scope. Give it an `.id` of the query and
/// scope: its models are made once, for those.
struct SearchResultsView: View {
    let query: String
    let scope: SearchScope
    let showScope: (SearchScope) -> Void
    let search: (String) -> Void

    @Environment(SearchSession.self) private var session: SearchSession?
    @State private var model: ResultsModel?
    @State private var webModel: WebResultsModel?
    @State private var smallWebModel: SmallWebModel?

    init(query: String, scope: SearchScope, showScope: @escaping (SearchScope) -> Void, search: @escaping (String) -> Void) {
        self.query = query
        self.scope = scope
        self.showScope = showScope
        self.search = search
        switch scope {
        case .all: break
        // Pages is your web pages; the notes are under Notes.
        case .hister:
            _model = State(initialValue: ResultsModel(query: query, filterable: true, respellable: (query, { $0 })))
        case .notes:
            _model = State(initialValue: ResultsModel(query: query, source: .notes, filterable: true, respellable: (query, { $0 })))
        case .web: _webModel = State(initialValue: WebResultsModel(query: SearxClient.webQuery(query)))
        // The web's own tabs: SearXNG's category, the same words.
        case .images, .videos, .news:
            _webModel = State(initialValue: WebResultsModel(query: SearxClient.webQuery(query), category: scope.webCategory))
        case .smallweb: _smallWebModel = State(initialValue: SmallWebModel(query: SearxClient.webQuery(query)))
        // The folders Hister watches (`type:local`), here and nowhere else.
        case .files:
            _model = State(initialValue: ResultsModel(query: LocalFiles.query(query)))
        // Your repos (`metadata.source:code`): CodeResults, with its filters.
        case .code: break
        case .media: break
        case .opened: break
        }
    }

    var body: some View {
        Group {
            if scope == .all {
                AllResults(query: query, showScope: showScope, search: search)
            } else if scope == .opened {
                OpenedListView(filter: query)
            } else if scope == .code {
                CodeResults(query: query)
            } else if scope == .media {
                MediaResults(query: query)
            } else if let webModel {
                if session == nil || session?.webAllowed == query {
                    WebResultsList(model: webModel, search: search)
                } else {
                    ContentUnavailableView(
                        scope.prompt, systemImage: "globe",
                        description: Text("Press Return to search the web for this."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .themedBackground()
                }
            } else if let smallWebModel {
                SmallWebResultsList(model: smallWebModel)
            } else if let model {
                ResultsList(model: model, title: query) {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        // Under the pills, above Sort and Group, as in the web app.
        .topBar {
            if scope != .opened {
                DidYouMeanBar(query: query, search: search)
            }
        }
    }
}

/// "Did you mean …?": a respelling from SearXNG's autocomplete
/// (`Respelling.didYouMean`), even when the search found something:
/// "george orewell" finds pages, and the web engines quietly fix it. The
/// search page and the web app show the same line.
struct DidYouMeanBar: View {
    let query: String
    let search: (String) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var fix: String?

    var body: some View {
        // A zero-height anchor first: an empty Group is no view at all, and
        // its `.task`, which finds the respelling, never ran.
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if let fix {
                Button {
                    search(fix)
                } label: {
                    (Text("Did you mean ").foregroundStyle(palette.secondaryText)
                        + Text(fix).foregroundStyle(palette.accent)
                        + Text("?").foregroundStyle(palette.secondaryText))
                        .textStyle(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Did you mean \(fix)?")
                .topBarBackground()
            }
        }
        .task(id: query) {
            fix = nil
            let words = SearxClient.webQuery(query)
            guard app.allSearch.webResults, let searx = app.searx, !words.isEmpty else { return }
            let suggestions = await searx.autocomplete(words)
            guard !Task.isCancelled else { return }
            fix = Respelling.didYouMean(words, suggestions: suggestions)
        }
    }
}

/// The rows of a selecting list, in order, for its j and k.
struct ListOrderKey: PreferenceKey {
    static let defaultValue: [StoredPage] = []
    static func reduce(value: inout [StoredPage], nextValue: () -> [StoredPage]) {
        value.append(contentsOf: nextValue())
    }
}

/// ? on a results list: the keys it answers.
struct KeyboardHelp: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    /// The keys' column grows with the text size (the Mac's too).
    @ScaledMetric(relativeTo: .body) private var keyWidth: CGFloat = 110
    @Environment(\.macTextScale) private var macScale
    private let keys: [(String, String)] = [
        ("j  k", "Next, previous result"),
        ("h  l", "Previous, next choice (All · Pages · Notes · Web · Opened)"),
        ("Return  o", "Open (a note in Obsidian)"),
        ("p", "Preview"),
        ("g g  G", "Top, bottom"),
        ("/  ⌘K", "Search"),
        ("Esc", "Clear the selection"),
        ("y", "Copy the link"),
        ("e", "Edit the label"),
        ("d d", "Delete (with Undo)"),
        ("?", "These keys"),
    ]

    var body: some View {
        NavigationStack {
            List(keys, id: \.0) { key in
                HStack {
                    Text(key.0)
                        .textStyle(.body, design: .monospaced)
                        .foregroundStyle(palette.accent)
                        .frame(width: keyWidth * macScale, alignment: .leading)
                    Text(key.1)
                        .foregroundStyle(palette.text)
                }
                .listRowBackground(palette.surface)
            }
            .themedBackground()
            .navigationTitle("Keyboard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}

extension EnvironmentValues {
    /// Set by the Mac and iPad layout while its preview pane is showing:
    /// result lists then select (and the pane previews) instead of
    /// navigating.
    @Entry var previewSelection: Binding<StoredPage?>? = nil
}

/// A results list: plain, or selecting into the preview pane, where a
/// double-click (or Return) opens the page and the menu covers the page.
struct ResultsListContainer<Content: View>: View {
    /// Bumped to scroll to `top` (a list refreshed from its "N New Items"
    /// banner); 0 never scrolls.
    var topRequests = 0
    var top: StoredPage.ID?
    /// The rows in order, from the list's data, for j and k; nil: as the
    /// rows report themselves (`ListOrderKey`).
    var rows: [StoredPage]?
    @ViewBuilder var content: () -> Content
    @Environment(\.previewSelection) private var selection
    @Environment(\.openURL) private var openURL
    @Environment(\.resultActions) private var actions
    @Environment(AppState.self) private var app

    @Environment(SearchSession.self) private var session
    @Environment(\.palette) private var palette
    /// The rows in order, as they report themselves (`ListOrderKey`),
    /// when the list doesn't say (`rows`).
    @State private var reported: [StoredPage] = []
    private var order: [StoredPage] { rows ?? reported }
    /// The first of a two-key command (gg, dd) and when it was pressed.
    @State private var pending: (key: Character, at: Date)?
    @State private var showingKeys = false
    /// A page opened on purpose (Return, double-click), so the selection's
    /// own count doesn't record it a second time.
    @State private var openedOnPurpose: String?
    @FocusState private var focused: Bool
    /// Shown once the Mac's list has laid its rows out: its first pass
    /// guesses their heights, and new results drew squashed (titles only,
    /// stacked) for a frame or two before snapping to size.
    @State private var laidOut = false

    var body: some View {
        if let selection {
            ScrollViewReader { proxy in
                List(selection: selection) {
                    content()
                }
                .focused($focused)
                .onPreferenceChange(ListOrderKey.self) { if rows == nil { reported = $0 } }
                .onKeyPress(phases: .down) { press in viKey(press, selection: selection) }
                .onChange(of: selection.wrappedValue) { _, new in
                    if let new { withAnimation { proxy.scrollTo(new.id) } }
                }
                // Previewing a page beside the list counts as opening it once
                // it has stayed selected a while: moving through the list
                // (j/k, arrows, clicks) told Hister every row passed over.
                .task(id: selection.wrappedValue?.url) {
                    guard let page = selection.wrappedValue else { return }
                    try? await Task.sleep(for: Self.dwell)
                    guard !Task.isCancelled, selection.wrappedValue?.url == page.url, openedOnPurpose != page.url else { return }
                    actions.opened(page)
                }
                .onChange(of: app.resultsFocusRequests) { _, _ in focused = true }
                .onChange(of: topRequests) { _, _ in scrollToTop(proxy) }
                .sheet(isPresented: $showingKeys) { KeyboardHelp() }
            }
            #if os(macOS)
            .opacity(laidOut ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                laidOut = true
            }
            #endif
            #if os(macOS)
            // Double-click (or Return) opens; on iOS the primary action
            // would fire on a single tap, which should preview instead.
            .contextMenu(forSelectionType: StoredPage.self) { documents in
                if let document = documents.first { DocumentMenu(document: document) }
            } primaryAction: { documents in
                if let document = documents.first { open(document) }
            }
            #else
            .contextMenu(forSelectionType: StoredPage.self) { documents in
                if let document = documents.first { DocumentMenu(document: document) }
            }
            // The selected row's tint marks it, as on the Mac and the web
            // app; the iPad also drew its keyboard-focus ring round it. The
            // controls inside a row (its title, label and vault chips) turn
            // their focus ring back on (`keepsFocusRing`), so the keyboard
            // still shows where it is among them.
            .focusEffectDisabled()
            #endif
        } else {
            ScrollViewReader { proxy in
                List {
                    content()
                }
                .onChange(of: topRequests) { _, _ in scrollToTop(proxy) }
            }
        }
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let top else { return }
        withAnimation { proxy.scrollTo(top, anchor: .top) }
    }

    // MARK: vi keys (the web app and the search page have the same)

    /// j/k next and previous, h/l the pills, Return or o open, p preview,
    /// gg/G top and bottom, / the search field, Esc clear, y copy, e label,
    /// dd delete (with Undo), ? the list of keys. While the list has the
    /// keyboard; a search field takes its own keys.
    private func viKey(_ press: KeyPress, selection: Binding<StoredPage?>) -> KeyPress.Result {
        guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        let current = selection.wrappedValue
        if press.key == .escape {
            guard current != nil else { return .ignored }
            selection.wrappedValue = nil
            return .handled
        }
        if press.key == .return, let current {
            open(current)
            return .handled
        }
        guard var key = press.characters.first, press.characters.count == 1 else { return .ignored }
        // The iPad can report the unshifted character with Shift held
        // (⇧/ as "/"), so ? and G come from Shift here.
        if press.modifiers.contains(.shift) {
            if key == "/" { key = "?" } else if key.isLowercase { key = Character(key.uppercased()) }
        }
        let twice = pending.map { $0.key == key && Date.now.timeIntervalSince($0.at) < 0.6 } ?? false
        pending = nil
        switch key {
        case "j": step(1, selection)
        case "k": step(-1, selection)
        case "h": scope(-1)
        case "l": scope(1)
        case "o":
            if let current { open(current) }
        case "p":
            if current == nil { selection.wrappedValue = order.first }
        case "g":
            if twice { selection.wrappedValue = order.first } else { pending = (key, .now) }
        case "G": selection.wrappedValue = order.last
        case "/": app.searchFocusRequests += 1
        case "y":
            if let current, let url = URL(string: current.url) { Pasteboard.copy(url) }
        case "e":
            if let current, app.noteLinks(for: current) == nil { actions.label(current) }
        case "d":
            if twice, let current {
                step(1, selection)
                if selection.wrappedValue == current { step(-1, selection) }
                if selection.wrappedValue == current { selection.wrappedValue = nil }
                actions.delete(current)
            } else {
                pending = (key, .now)
            }
        case "?": showingKeys.toggle()
        default: return .ignored
        }
        return .handled
    }

    private func step(_ by: Int, _ selection: Binding<StoredPage?>) {
        guard !order.isEmpty else { return }
        guard let current = selection.wrappedValue, let i = order.firstIndex(of: current) else {
            selection.wrappedValue = by > 0 ? order.first : order.last
            return
        }
        selection.wrappedValue = order[min(max(i + by, 0), order.count - 1)]
    }

    /// The pill to the left or right: All · Pages · Notes · Web · Opened.
    private func scope(_ by: Int) {
        let all = app.searchScopes
        guard let i = all.firstIndex(of: session.scope), all.indices.contains(i + by) else { return }
        session.scope = all[i + by]
    }

    /// In its own app (`openPage`): a note in Obsidian, a file from
    /// Hister's copy, anything else in the browser.
    private func open(_ document: StoredPage) {
        openedOnPurpose = document.url
        actions.opened(document)
        openURL.openPage(document, app: app)
    }

    /// How long a page stays selected beside the pane before it counts as
    /// opened (Remember What You Open). An open on purpose counts at once.
    static var dwell: Duration { .seconds(2) }
}

extension View {
    /// A small set of choices across the top of a list: the Library's All /
    /// Pages / Notes / Opened, the search scopes. Coloured pills, as the
    /// Safari results page draws its categories: the chosen one filled.
    /// Sort, Group and Filter below them are plain text, so the two rows
    /// don't read as one; a line under the bar parts it from the results.
    /// `count`: a total shown after a pill's name ("Pages 31": All's search
    /// finds Pages' and Notes'), in a lighter weight.
    func topChoices<Choice: Hashable & Identifiable>(
        _ label: String, selection: Binding<Choice>, choices: [Choice],
        title: @escaping (Choice) -> String, tint: @escaping (Choice) -> Palette.Tint,
        count: @escaping (Choice) -> Int? = { _ in nil }
    ) -> some View {
        modifier(TopChoices(label: label, selection: selection, choices: choices, title: title, tint: tint, count: count))
    }
}

extension Palette {
    /// The theme's background as a view, for places without the palette
    /// at hand.
    struct Background: View {
        @Environment(\.palette) private var palette
        var body: some View { palette.background }
    }
}

extension View {
    /// A bar across the top of a list, under the navigation bar: the pills,
    /// Sort · Group · Filter, "Did you mean", a list's own search field.
    /// On iOS 26 it's a safe-area bar, so the navigation bar's scroll edge
    /// effect runs on under it and title, search field and pills read as one
    /// band; the list's edge is `.hard` (Apple's advice for pinned accessory
    /// rows), so rows scrolling beneath stay out of the way. A solid slab
    /// under the Liquid Glass search field looked out of place and floating.
    /// On the Mac (macOS 26) it's a safe-area bar
    /// too, with the system's own frosted edge: an inset there let the
    /// cards show through under the toolbar's search field, where Suggested
    /// Labels (no bar) was frosted. Earlier systems
    /// keep the theme's background.
    @ViewBuilder
    func topBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            // The system's soft edge, as on the Mac: one frosted look on
            // every device (it was `.hard`).
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: bar)
        }
        #else
        if #available(macOS 26, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: bar)
        }
        #endif
    }

    /// `topBar`, only when `shown` (a list that has the window's field
    /// instead of its own).
    @ViewBuilder
    func topBar<Bar: View>(if shown: Bool, @ViewBuilder _ bar: () -> Bar) -> some View {
        if shown { topBar(bar) } else { self }
    }

    /// A top bar's own background: the theme's, except where `topBar` lets
    /// the scroll edge effect show through (iOS 26, macOS 26). A view, not a
    /// colour fill: a fill reaches up behind the large title and painted over it.
    @ViewBuilder
    func topBarBackground() -> some View {
        #if os(iOS)
        if #available(iOS 26, *) { self } else { background(Palette.Background()) }
        #else
        if #available(macOS 26, *) { self } else { background(Palette.Background()) }
        #endif
    }
}

extension View {
    /// A sideways-scrolling row fades out at an end with more to scroll to,
    /// as the web pages' pills do (`S.edgeFade`): a pill cut off at the
    /// edge looked like a mistake.
    func fadesOverflow() -> some View { modifier(OverflowFade()) }
}

private struct OverflowFade: ViewModifier {
    struct Ends: Equatable {
        var leading = false
        var trailing = false
    }

    @State private var ends = Ends()
    private let width: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Ends.self) { geometry in
                // In the content's own coordinates; 2 points of slack for
                // a row scrolled to within a fraction of its end.
                let seen = geometry.visibleRect
                return Ends(leading: seen.minX > 2, trailing: seen.maxX < geometry.contentSize.width - 2)
            } action: { _, now in
                ends = now
            }
            // One gradient across the whole row: three views side by side left
            // a hairline seam between them, a dark line through a pill there.
            .mask {
                GeometryReader { geometry in
                    let fade = min(width / max(geometry.size.width, 1), 0.5)
                    LinearGradient(
                        stops: [
                            .init(color: ends.leading ? .clear : .black, location: 0),
                            .init(color: .black, location: ends.leading ? fade : 0),
                            .init(color: .black, location: ends.trailing ? 1 - fade : 1),
                            .init(color: ends.trailing ? .clear : .black, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                }
            }
    }
}

/// Set by a row of list controls (Sort, Group) that draws the bar's line
/// itself, below the pills; without one, the pills draw it.
struct ControlsRowKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// The line under the top bar, and word to `topChoices` that it's drawn.
    func endsTopBar() -> some View {
        VStack(spacing: 0) {
            self
            Divider()
        }
        .topBarBackground()
        .preference(key: ControlsRowKey.self, value: true)
    }
}

private struct TopChoices<Choice: Hashable & Identifiable>: ViewModifier {
    let label: String
    let selection: Binding<Choice>
    let choices: [Choice]
    let title: (Choice) -> String
    let tint: (Choice) -> Palette.Tint
    let count: (Choice) -> Int?
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var app
    @State private var rowBelow = false
    @State private var position: ScrollPosition

    init(label: String, selection: Binding<Choice>, choices: [Choice], title: @escaping (Choice) -> String,
         tint: @escaping (Choice) -> Palette.Tint, count: @escaping (Choice) -> Int?) {
        self.label = label
        self.selection = selection
        self.choices = choices
        self.title = title
        self.tint = tint
        self.count = count
        _position = State(initialValue: ScrollPosition(x: PillRowMemory.offsets[label] ?? 0))
    }

    /// Pills that don't fit wrap to another row, every one in sight (one row
    /// again once there's room), unless Settings → Search → Pill Row says One
    /// Row: then they scroll sideways. Automatic scrolls too on a short
    /// screen (an iPhone on its side), where wrapped rows, the field and Sort
    /// took nearly half of it.
    private var wraps: Bool {
        guard app.searchPage.pillRow != "scroll" else { return false }
        #if os(iOS)
        return verticalSizeClass != .compact
        #else
        return true
        #endif
    }
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ControlsRowKey.self) { rowBelow = $0 }
            .topBar {
                VStack(spacing: 0) {
                    if wraps {
                        PillFlow(spacing: 6) {
                            ForEach(choices) { pill($0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        #if os(macOS)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                        #else
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        #endif
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(label)
                    } else {
                    // Scrolls sideways when the pills don't fit (a phone
                    // with Small Web on, the largest text sizes), rather
                    // than truncating; the chosen one is kept in view. The
                    // row is rebuilt with each list under it: it starts where
                    // the last one was left (it jumped back to All, then
                    // across to the chosen pill), and scrolls only when the
                    // chosen pill is out of sight.
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(choices) { pill($0).id($0.id) }
                            }
                            .padding(.horizontal)
                            #if os(macOS)
                            // The Mac's sidebar row (Library, 32 points) is
                            // level with the pills (24): 4 points less above
                            // and 4 more below puts their centers together
                            // and leaves the bar as tall as before.
                            .padding(.top, 4)
                            .padding(.bottom, 10)
                            #else
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                            #endif
                        }
                        .scrollPosition($position)
                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                            PillRowMemory.offsets[label] = x
                        }
                        .fadesOverflow()
                        .onAppear { proxy.scrollTo(selection.wrappedValue.id) }
                        .onChange(of: selection.wrappedValue) { _, chosen in
                            withAnimation(.snappy) { proxy.scrollTo(chosen.id) }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(label)
                    }
                    if !rowBelow { Divider() }
                }
                // The theme's background before iOS 26; there, the scroll
                // edge effect under the navigation bar (`topBar`).
                .topBarBackground()
            }
    }

    private func pill(_ choice: Choice) -> some View {
        let on = selection.wrappedValue == choice
        return Button {
            selection.wrappedValue = choice
        } label: {
            PillFace(text: pillText(choice), tint: tint(choice), on: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(.snappy(duration: 0.2), value: on)
    }

    /// The name, and a count after it in a lighter weight.
    private func pillText(_ choice: Choice) -> Text {
        guard let n = count(choice) else { return Text(title(choice)) }
        return Text(title(choice)) + Text(" \(n.formatted())").fontWeight(.regular)
    }
}

/// Where each pill row was scrolled to, by its label, for the next one drawn
/// in its place (a row is rebuilt with every list under it).
@MainActor
enum PillRowMemory {
    static var offsets: [String: CGFloat] = [:]
}

/// Pills in rows: as many as fit on each, the rest on the next (6 points
/// apart both ways), each row starting at the leading edge.
struct PillFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: proposal.width ?? .infinity, subviews)
        let width = rows.map { row in row.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        let height = rows.map { $0.map(\.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var index = 0
        for row in rows(for: bounds.width, subviews) {
            var x = bounds.minX
            let height = row.map(\.height).max() ?? 0
            for size in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += height + spacing
        }
    }

    private func rows(for width: CGFloat, _ subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].isEmpty, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        return rows
    }
}

/// A pill over a list: outlined in its colour, filled when chosen. Under the
/// pointer one that isn't chosen lifts onto its hover fill (24% of its
/// colour over the raised shade) with a small shadow, its text moved to the
/// shade that reads at 4.5:1 there (`pillHover`), as the web pages draw it.
private struct PillFace: View {
    let text: Text
    let tint: Palette.Tint
    let on: Bool
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        let color = palette.tint(tint)
        let lifted = hovering && !on
        let hover = palette.pillHover(tint)
        let ink = lifted ? hover.ink : color
        // At least as wide as Web, the next shortest: All was hard to tap (the web pages' min-width, in the pill's type).
        ZStack {
            Text(verbatim: "Web").hidden().accessibilityHidden(true)
            text
        }
            .textStyle(.subheadline, weight: .semibold)
            .foregroundStyle(on ? palette.background : ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Capsule().fill(on ? color : lifted ? hover.fill : .clear))
            .overlay(Capsule().strokeBorder(on ? color : ink, lineWidth: 1.5))
            .shadow(color: .black.opacity(lifted ? (palette.isDark ? 0.35 : 0.12) : 0), radius: 1, y: 1)
            // A 44-point target round a 28-point pill.
            .tapArea(vertical: 8, horizontal: 2)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}
