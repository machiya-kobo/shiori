import HisterKit
import SwiftUI

/// A list of stored pages for one query, with paging, the empty and
/// unreachable states, and the per-page actions (label, delete, share).
struct ResultsList<Empty: View>: View {
    let model: ResultsModel
    /// The name for its feed and export ("tech", "rust"); the query if nil.
    var title: String?
    @ViewBuilder var empty: () -> Empty

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    /// Folded runs that were opened (`SiteRuns.Item.id`).
    @State private var unfolded: Set<String> = []
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped after the banner's refresh, to scroll the list to its top.
    @State private var topRequests = 0

    /// How often an open list asks whether anything arrived (Hister and
    /// Kura only, never the web).
    static var pollInterval: Duration { .seconds(60) }

    var body: some View {
        content
            // Again when the Kura address changes, for a notes list.
            .task(id: "\(app.serverURL)|\(app.searchPage.niwaURL)|\(app.notesFrom.rawValue)|\(model.source == .notes ? app.notesVault : "")") { await load() }
            .pullToRefresh { await load() }
            // Every minute while the app is in front and the list is up:
            // anything new shows as a banner, never by redrawing the list
            // under you.
            .task(id: "\(app.serverURL)|\(model.query)") {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pollInterval)
                    guard !Task.isCancelled else { return }
                    if scenePhase == .active { await model.checkForNew(using: app.client) }
                }
            }
            .overlay(alignment: .top) {
                if let asOf = model.offlineAsOf, model.phase == .loaded {
                    // The Library's copy from the last time Hister answered;
                    // it's replaced once the list loads again.
                    OfflineNote(asOf: asOf) { Task { await load() } }
                        .padding(.top, 8)
                        .transition(.opacity)
                } else if model.newCount > 0, model.phase == .loaded {
                    NewItemsBanner(count: model.newCount) {
                        Task {
                            await load()
                            topRequests += 1
                        }
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: model.newCount)
            .topBar {
                ListControls(model: model, title: title ?? model.baseQuery) { Task { await load() } }
            }
            .resultActions(query: AppState.remembers(model.baseQuery) ? model.query : nil)
    }

    private func load() async {
        model.wantsFacets = app.searchPage.searchFilters
        model.semantic = app.semanticOn
        model.webSuggestions = { [app] in await app.webSuggestions(for: $0) }
        // Notes come from Kura or from Hister (Settings → Notes → Notes
        // From); from Kura, a notes list searches the vaults picked in its
        // filter, from Hister the default vault alone.
        model.kura = app.notesKuraInUse
        model.notesFromHister = app.notesFrom == .hister
        model.vaults = model.source == .notes && app.notesFrom == .kura ? app.notesVault : nil
        model.offlineOrigin = OfflineStore.origin(server: app.serverURL, kura: app.searchPage.niwaURL)
        await model.load(using: app.client)
    }

    private var visible: [StoredPage] {
        model.documents.filter { !app.deletes.hidden.contains($0.url) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            loadingView
        case .loading:
            // Documents while still loading are a first page being topped
            // up (Pages leaves the notes out): rows added to a list on
            // screen draw squashed on the Mac for a moment, so the list
            // waits for the rest (a reload keeps its list; it never
            // returns to .loading).
            loadingView
        case .failed(let error):
            FailureView(error: error, hasServer: app.client != nil) {
                Task { await load() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedBackground()
        default:
            if visible.isEmpty {
                empty()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
            } else {
                list
            }
        }
    }

    /// Grouped by site, a section is one site already: nothing to fold.
    private var folds: Bool { app.searchPage.foldRepeats && model.grouping != .site }

    @ViewBuilder private func rows(_ pages: [StoredPage]) -> some View {
        if folds {
            ForEach(SiteRuns.items(pages)) { item in
                switch item {
                case .page(let document):
                    row(document)
                case .folded(let site, let hidden):
                    if unfolded.contains(item.id) {
                        FoldedRow(site: site, count: hidden.count, open: true) { unfolded.remove(item.id) }
                        ForEach(hidden) { row($0) }
                    } else {
                        FoldedRow(site: site, count: hidden.count, open: false) { unfolded.insert(item.id) }
                            // Its pages are the list's last: keep paging.
                            .task { if let last = hidden.last { await more(after: last) } }
                    }
                }
            }
        } else {
            ForEach(pages) { row($0) }
        }
    }

    private func row(_ document: StoredPage) -> some View {
        DocumentItem(document: document)
            .task { await more(after: document) }
    }

    private func more(after document: StoredPage) async {
        await model.loadMoreIfNeeded(after: document, using: app.client)
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedBackground()
    }

    private var list: some View {
        ResultsListContainer(topRequests: topRequests, top: visible.first?.id) {
            if let respelled = model.respelledAs {
                Text("Showing results for “\(respelled)”")
                    .textStyle(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .listRowBackground(palette.background)
            } else if let suggestion = model.suggestion {
                Text("Did you mean “\(suggestion)”?")
                    .textStyle(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .listRowBackground(palette.background)
            }
            OpenedSection(model: model)
            let sections = model.sections(of: visible)
            if model.grouping == .none {
                rows(visible)
            } else {
                ForEach(sections) { section in
                    Section {
                        rows(section.pages)
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(section.pages.count.formatted())
                                .foregroundStyle(palette.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if model.capped {
                Text("Showing the first \(ResultsModel.allLimit.formatted()) of \(model.total.formatted()).")
                    .textStyle(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .listRowBackground(palette.background)
            }
            if model.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(palette.background)
            }
        }
        .listStyle(.plain)
        .themedBackground()
    }

}

/// The rest of a run of pages from one site (`SiteRuns`), folded into a
/// row: "a.example · 6 more", or Hide once open.
struct FoldedRow: View {
    let site: String
    let count: Int
    let open: Bool
    let toggle: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .imageScale(.small)
                Text(open ? "Hide \(count.formatted()) more from \(site)" : "\(count.formatted()) more from \(site)")
                Spacer(minLength: 0)
            }
            .textStyle(.subheadline, weight: .medium)
            .foregroundStyle(palette.accent)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: open)
        .listRowBackground(palette.background)
        .accessibilityLabel(open ? "Hide \(count) more pages from \(site)" : "\(count) more pages from \(site)")
        .accessibilityHint(open ? "" : "Shows them")
    }
}

/// Open, share and copy links for a page, shared by menus.
struct DocumentLinks: View {
    let document: StoredPage
    /// Leave out where a click opens it (`OpenOriginalButton`), when the
    /// menu already leads with it.
    var skipOriginal = false
    @Environment(AppState.self) private var app

    var body: some View {
        NoteLinksMenu(document: document, skipOriginal: skipOriginal)
        if LocalFiles.isLocalFile(document.url) {
            // Hister's copy: the file:// address means nothing here.
            if let served = app.servedFile(document.url) {
                if !skipOriginal {
                    Link(destination: served) { Label("Open", systemImage: "doc") }
                }
                Button("Copy Link", systemImage: "link") { Pasteboard.copy(served) }
            }
        } else if let url = SafeHref.url(document.url) {
            if !skipOriginal || app.noteLinks(for: document) != nil {
                Link(destination: url) {
                    Label("Open in Browser", systemImage: "safari")
                }
            }
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button("Copy Link", systemImage: "link") {
                Pasteboard.copy(url)
            }
            // A web page's copies and front ends (not a note, a file or code:
            // archives can't reach a private forge, and a note is Kura's).
            if app.noteLinks(for: document) == nil, document.code == nil {
                ElsewhereLinks(url: document.url)
            }
        }
        // Not a note: notes are Kura's (Hister may not hold one).
        if let client = app.client, app.noteLinks(for: document) == nil, !Notes.isPrivateNote(document.url) {
            Link(destination: client.webPreviewURL(for: document.url)) {
                Label("Open in Hister", systemImage: "magnifyingglass")
            }
        }
    }
}

/// A web page elsewhere: on Archive.org and Archive.is, and through the
/// build's privacy front ends that stand in for its site (`Elsewhere`).
/// Links only, opened in the browser.
struct ElsewhereLinks: View {
    let url: String

    /// The build's front ends (`SHIORI_FRONTENDS`), read once.
    static let instances = Elsewhere.instances(
        from: (Bundle.main.object(forInfoDictionaryKey: "ShioriFrontends") as? String) ?? "")

    var body: some View {
        // A page on one of the front ends (saved while browsing Redlib, say):
        // its own site too, and the archives of that address, which they can reach.
        let original = Elsewhere.original(of: url, instances: Self.instances)
        let page = original?.url.absoluteString ?? url
        if let original {
            Link(destination: original.url) { Label("Open Original on \(original.site)", systemImage: "arrow.uturn.backward") }
        }
        if let wayback = Elsewhere.wayback(page) {
            Link(destination: wayback) { Label("Open on Archive.org", systemImage: "building.columns") }
        }
        if let archive = Elsewhere.archiveToday(page) {
            Link(destination: archive) { Label("Open on Archive.is", systemImage: "archivebox") }
        }
        ForEach(Elsewhere.frontends(for: url, instances: Self.instances), id: \.url) { frontend in
            Link(destination: frontend.url) { Label("Open in \(frontend.name)", systemImage: "eye.slash") }
        }
    }
}

/// One result: favicon, title, where and when, the matching text, label.
extension EnvironmentValues {
    /// All's rows of your own among the web results: whose this one is
    /// (`.hister` "Your page", `.notes` "Your note"), said above its title.
    @Entry var mixedIn: SearchScope?
}

struct DocumentRow: View {
    let document: StoredPage
    let label: String
    /// For a vault note: where it sits in the vault, shown in place of
    /// the Niwa or Konbini host it's stored under.
    var notePlace: String?
    @Environment(\.palette) private var palette
    @Environment(\.resultActions) private var actions
    @Environment(AppState.self) private var app
    /// Absent outside the search layouts (a sheet's list): then a vault
    /// chip only filters Notes, without switching to it.
    @Environment(SearchSession.self) private var session: SearchSession?
    @Environment(\.mixedIn) private var mixedIn
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .headline) private var scaledIcon: CGFloat = 20
    @Environment(\.macTextScale) private var macScale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Group {
                if let code = document.code {
                    // What it is (repo, doc, issue, PR, release), in Code's red.
                    Image(systemName: code.symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(palette.tint(SearchScope.code.tint))
                        .frame(width: scaledIcon * macScale, height: scaledIcon * macScale)
                        .accessibilityLabel(code.kindName)
                } else if notePlace != nil || LocalFiles.isLocalFile(document.url) {
                    Image(systemName: "doc.text")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(palette.accent)
                        .frame(width: scaledIcon * macScale, height: scaledIcon * macScale)
                        .accessibilityHidden(true)
                } else {
                    FaviconView(key: document.faviconKey)
                }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 4) {
                if let mixedIn {
                    Text(mixedIn == .notes ? "Your note" : "Your page")
                        .textStyle(.caption, weight: .semibold)
                        .foregroundStyle(palette.tint(mixedIn.tint))
                }
                // The accent, as the search page and the web app draw titles.
                // A link: it always opens the original, whatever a click on
                // the rest of the row does (Click Opens).
                TitleLink(title: document.displayTitle, help: OpenOriginalButton.title(for: document, app: app)) {
                    actions.opened(document)
                    openURL.openPage(document, app: app)
                }
                HStack(spacing: 6) {
                    if let code = document.code {
                        // Which forge (most are Forgejo, and the rows looked alike),
                        // the repo, its state, a lock when private.
                        if !code.host.isEmpty {
                            Text(CodeDocs.hostName(code.host))
                                .textStyle(.caption2, weight: .semibold)
                                .padding(.horizontal, 5)
                                .overlay(Capsule().strokeBorder(palette.secondaryText.opacity(0.5)))
                        }
                        if code.isPrivate {
                            Image(systemName: "lock.fill")
                                .textStyle(.caption)
                                .accessibilityLabel("Private")
                        }
                        Text(code.repoName.isEmpty ? document.domain : code.repoName)
                            .textStyle(.caption, design: .monospaced)
                            .lineLimit(1)
                        if !code.state.isEmpty {
                            Text(code.state)
                                .textStyle(.caption, weight: .semibold)
                                .foregroundStyle(code.state == "open" ? palette.tint(.green) : palette.secondaryText)
                        }
                    } else if let notePlace {
                        Text(notePlace)
                            .textStyle(.caption)
                            .lineLimit(1)
                    } else if LocalFiles.isLocalFile(document.url) {
                        // Where it lives on the server, not "local".
                        Text(LocalFiles.path(of: document.url))
                            .textStyle(.caption, design: .monospaced)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(document.domain)
                            .textStyle(.caption, design: .monospaced)
                            .lineLimit(1)
                    }
                    // No date at all rather than "2,026 years ago" (an opened
                    // result from a Hister that sends none).
                    if document.updated > .distantPast {
                        Text("·")
                            .accessibilityHidden(true)
                        Text(document.updated, format: .relative(presentation: .named))
                            .textStyle(.caption)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(palette.secondaryText)
                let snippet = document.snippet
                if !snippet.isEmpty {
                    Text(attributed(snippet))
                        .textStyle(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(3)
                }
                if label == Notes.label {
                    // A note names its vault ("Work vault"), since Notes
                    // mix vaults. A tap shows Notes from that vault.
                    let chip = Notes.vaultChip(of: document.url, vaults: app.kuraVaults)
                    Button {
                        guard !chip.name.isEmpty else { return }
                        app.notesVault = chip.name
                        session?.scope = .notes
                    } label: { LabelChip(label: chip.text) }
                        .buttonStyle(.borderless)
                        .help(chip.name.isEmpty ? "A note" : "Notes in \(chip.text)")
                        .accessibilityHint("Shows the notes in this vault")
                        .padding(.top, 2)
                } else if !label.isEmpty {
                    // A tap shows every page with the label (the row's own tap
                    // still opens the page).
                    Button { actions.showLabel(label) } label: { LabelChip(label: label) }
                        .buttonStyle(.borderless)
                        .help("Pages labelled \(label)")
                        .accessibilityHint("Shows every page with this label")
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func attributed(_ snippet: Snippet) -> AttributedString {
        var out = AttributedString()
        for run in snippet.runs {
            var piece = AttributedString(run.text)
            if run.highlighted {
                piece.foregroundColor = palette.text
                piece.backgroundColor = palette.highlight
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            out += piece
        }
        return out
    }
}

/// A page's favicon from Hister, or a neutral globe.
struct FaviconView: View {
    let key: String
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .headline) private var scaledSize: CGFloat = 20
    @Environment(\.macTextScale) private var macScale
    private var size: CGFloat { scaledSize * macScale }
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(palette.secondaryText)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.2))
        .accessibilityHidden(true)
        .task(id: key) {
            image = await app.favicons.image(for: key, using: app.client)
        }
    }
}

/// Why a list is empty because something failed.
struct FailureView: View {
    let error: HisterError
    let hasServer: Bool
    let retry: () -> Void

    var body: some View {
        if !hasServer {
            ContentUnavailableView {
                Label("No Server Set", systemImage: "server.rack")
            } description: {
                Text("Add your Hister server's address in Settings.")
            }
        } else {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(error.userMessage)
            } actions: {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var title: String {
        switch error {
        case .unreachable: "Can't Reach Hister"
        case .untrusted: "Connection Not Trusted"
        case .plainHTTP: "Needs HTTPS"
        case .previewUnavailable: "Preview Not Shown"
        case .invalidQuery: "Query Not Understood"
        default: "Something Went Wrong"
        }
    }

    private var symbol: String {
        switch error {
        case .unreachable: "network.slash"
        case .untrusted: "lock.trianglebadge.exclamationmark"
        case .plainHTTP: "lock.open"
        case .previewUnavailable: "doc.text.magnifyingglass"
        case .invalidQuery: "questionmark.text.page"
        default: "exclamationmark.triangle"
        }
    }
}

enum Pasteboard {
    static func copy(_ url: URL) {
        #if canImport(UIKit)
        UIPasteboard.general.url = url
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        #endif
    }

    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// For a vault note: open it in Obsidian, on Niwa, or its Konbini card.
struct NoteLinksMenu: View {
    let document: StoredPage
    /// Leave out the note's original (Obsidian, else Kura): the menu leads with it.
    var skipOriginal = false
    @Environment(AppState.self) private var app

    var body: some View {
        if let links = app.noteLinks(for: document) {
            if let url = links.obsidian, !skipOriginal {
                Link(destination: url) { Label("Edit in Obsidian", systemImage: "doc.text") }
            }
            if let url = links.niwa, !(skipOriginal && links.obsidian == nil) {
                Link(destination: url) { Label("View in Kura", systemImage: "book") }
            }
            if let url = links.konbini {
                Link(destination: url) { Label("View Card in Konbini", systemImage: "rectangle.split.3x1") }
            }
            Divider()
        }
    }
}

/// "Offline · as of 3:42 PM": a copy kept on the device (`OfflineStore`)
/// is on screen. A tap tries the server again.
struct OfflineNote: View {
    let asOf: Date
    let retry: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: retry) {
            Label(asOf.offlineAsOf, systemImage: "wifi.slash")
                .textStyle(.subheadline, weight: .semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.secondaryText.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondaryText)
        .help("Try Again")
        .accessibilityHint("Tries your server again")
    }
}

/// "3 New Items" with a refresh icon: what arrived since the list loaded, over its top. A tap
/// reloads it and goes to the top; until then the list stays as it was.
struct NewItemsBanner: View {
    let count: Int
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Label(count == 1 ? "1 New Item" : "\(count.formatted()) New Items", systemImage: "arrow.clockwise")
                .textStyle(.subheadline, weight: .semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(palette.background)
                .background(palette.accent, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows them at the top of the list")
    }
}
