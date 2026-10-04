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
    case all, hister, notes, web, smallweb, files, code, opened

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
        // Gemini and Gopher: the web's neighbour, teal.
        case .smallweb: .teal
        // The folders Hister watches: green, a hue no room wears.
        case .files: .green
        // The owner's repos (code-import): red, the one hue left.
        case .code: .red
        case .opened: .purple
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .hister: "Pages"
        case .notes: "Notes"
        case .web: "Web"
        case .smallweb: "Small Web"
        case .files: "Files"
        case .code: "Code"
        case .opened: "Opened"
        }
    }

    var prompt: String {
        switch self {
        case .all: "Search All"
        case .hister: "Search Your Pages"
        case .notes: "Search Notes"
        case .web: "Search the Web"
        case .smallweb: "Search Gemini and Gopher"
        case .files: "Search Your Files"
        case .code: "Search Your Code"
        case .opened: "Search What You Opened"
        }
    }
}

/// The search on screen: what's typed, what's been run, where it looks,
/// and (beside a preview pane) the selected page. Owned by `RootView` and
/// shared by both layouts, so an iPad crossing from three columns to the
/// tabs (Split View, Stage Manager) keeps it instead of starting over.
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
    var selected: StoredPage?
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
    /// How long typing pauses before the search runs by itself.
    static let liveDelay = Duration.milliseconds(350)

    /// What typing alone should search, after the pause: two characters
    /// or more, and not what's already on screen. Nil otherwise.
    var liveQuery: String? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        // Small Web searches only on Return: its engines are volunteers'
        // (the gateway's contract: no search while typing).
        guard typed.count >= 2, typed != submitted, scope != .smallweb else { return nil }
        return typed
    }
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
        case .smallweb: _smallWebModel = State(initialValue: SmallWebModel(query: SearxClient.webQuery(query)))
        // The folders Hister watches (`type:local`), here and nowhere else.
        case .files:
            _model = State(initialValue: ResultsModel(query: LocalFiles.query(query)))
        // The owner's repos (`metadata.source:code`): CodeResults, with its filters.
        case .code: break
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
            } else if let webModel {
                if session == nil || session?.webAllowed == query {
                    WebResultsList(model: webModel, search: search)
                } else {
                    ContentUnavailableView(
                        "Search the Web", systemImage: "globe",
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
    private let keys: [(String, String)] = [
        ("j  k", "Next, previous result"),
        ("h  l", "Previous, next choice (All · Pages · Notes · Web · Opened)"),
        ("Return  o", "Open (a note in Obsidian)"),
        ("p", "Preview"),
        ("g g  G", "Top, bottom"),
        ("/", "Search"),
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
                        .frame(width: 110, alignment: .leading)
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
    @ViewBuilder var content: () -> Content
    @Environment(\.previewSelection) private var selection
    @Environment(\.openURL) private var openURL
    @Environment(\.resultActions) private var actions
    @Environment(AppState.self) private var app

    @Environment(SearchSession.self) private var session
    @Environment(\.palette) private var palette
    /// The rows in order, as they report themselves (`ListOrderKey`).
    @State private var order: [StoredPage] = []
    /// The first of a two-key command (gg, dd) and when it was pressed.
    @State private var pending: (key: Character, at: Date)?
    @State private var showingKeys = false
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
                .onPreferenceChange(ListOrderKey.self) { order = $0 }
                .onKeyPress(phases: .down) { press in viKey(press, selection: selection) }
                .onChange(of: selection.wrappedValue) { _, new in
                    // Previewing a page beside the list is opening it.
                    if let new {
                        actions.opened(new)
                        withAnimation { proxy.scrollTo(new.id) }
                    }
                }
                .onChange(of: app.resultsFocusRequests) { _, _ in focused = true }
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
            // app; the iPad also drew its keyboard-focus ring round it.
            .focusEffectDisabled()
            #endif
        } else {
            List {
                content()
            }
        }
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

    /// A note in Obsidian (Niwa if Obsidian can't); anything else in the browser.
    private func open(_ document: StoredPage) {
        actions.opened(document)
        if let note = app.noteLinks(for: document), note.obsidian != nil {
            openURL.openNote(note)
        } else if let url = URL(string: document.url) {
            openURL(url)
        }
    }
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
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: ends.leading ? width : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: ends.trailing ? width : 0)
                }
                .animation(.easeOut(duration: 0.15), value: ends)
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
    @State private var rowBelow = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ControlsRowKey.self) { rowBelow = $0 }
            .topBar {
                VStack(spacing: 0) {
                    // Scrolls sideways when the pills don't fit (a phone
                    // with Small Web on, the largest text sizes), rather
                    // than truncating; the chosen one is kept in view.
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(choices) { pill($0).id($0.id) }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                        .fadesOverflow()
                        .onAppear { proxy.scrollTo(selection.wrappedValue.id) }
                        .onChange(of: selection.wrappedValue) { _, chosen in
                            withAnimation(.snappy) { proxy.scrollTo(chosen.id) }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(label)
                    if !rowBelow { Divider() }
                }
                // The theme's background before iOS 26; there, the scroll
                // edge effect under the navigation bar (`topBar`).
                .topBarBackground()
            }
    }

    private func pill(_ choice: Choice) -> some View {
        let on = selection.wrappedValue == choice
        let color = palette.tint(tint(choice))
        return Button {
            selection.wrappedValue = choice
        } label: {
            pillText(choice)
                .textStyle(.subheadline, weight: .semibold)
                .foregroundStyle(on ? palette.background : color)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(on ? color : .clear))
                .overlay(Capsule().strokeBorder(color, lineWidth: 1.5))
                .contentShape(Capsule())
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
