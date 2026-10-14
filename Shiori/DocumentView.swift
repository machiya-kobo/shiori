import HisterKit
import ShioriAI
import SwiftUI

/// One stored page: Hister's readable preview, styled in the theme, with
/// the page's actions in the toolbar.
struct DocumentView: View {
    let document: StoredPage

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.previewFocus) private var focus
    /// Absent in a sheet of its own: then nothing to keep across layouts.
    @Environment(SearchSession.self) private var session: SearchSession?
    @State private var preview: PagePreview?
    /// When the preview on screen was kept (`OfflineStore`), while Hister
    /// or Kura can't be reached; nil for a fresh one.
    @State private var offlineAsOf: Date?
    /// Another of the server's extractors, from Show As (nil: its default).
    @State private var extractor: String?
    /// Counts loads, so only the newest one's answer is shown (`load`).
    @State private var loadGeneration = 0
    @State private var extractors: [Extractor] = []
    @State private var versions: [PageVersion] = []
    @State private var showingVersions = false
    @State private var enlarged: EnlargedImage?
    @State private var error: HisterError?
    @State private var labelling = false
    @State private var failure: String?
    /// Show As couldn't load that view: said, and the page stays as it was.
    @State private var showAsFailure: String?
    @State private var rendered = false
    @State private var renderFailed = false
    /// Bumped by Try Again after a failed render: a fresh web view.
    @State private var renderAttempt = 0
    /// Summarize (Settings → AI): the card above the preview. Made on
    /// first use (it needs the app's engines).
    @State private var pageSummary: PageSummary?
    /// A code document's repo note in Kura (`Repos/<name>.git.md`), when it has one.
    @State private var repoNote: URL?
    /// The preview's page, built once per change of what goes in it: the
    /// body runs again on every summary step and render, and a long page's
    /// HTML (and its image links, a regex over the whole article) cost a
    /// stutter each time.
    @State private var previewPage = PreviewPageCache()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        // Once per render: the note's links and place (it was worked out five times).
        let note = app.noteLinks(for: document)
        content(note: note)
            // A vault note or a file by its name, not the host it is stored
            // under (a file's is Hister's "local").
            .navigationTitle(note == nil && !localFile ? document.domain : document.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar(note: note) }
            .task(id: document.code?.repoName) {
                repoNote = nil
                if let name = document.code?.repoName, !name.isEmpty { repoNote = await app.repoNoteURL(repoName: name) }
            }
            // Open full-screen (not in the pane): kept, so widening to the
            // three columns shows it there. Let go a moment after it
            // leaves, once a layout switch has read it.
            .onAppear { if focus == nil { session?.reading = document } }
            .onDisappear {
                let url = document.url
                Task { @MainActor in if session?.reading?.url == url { session?.reading = nil } }
            }
            .task(id: document.url) {
                summarizer().reset(for: document.url)
                await app.loadCardsIfNeeded()
                await load()
                if let preview { summarizer().showCached(url: document.url, updated: preview.updated) }
                await loadExtras()
            }
            // An offline copy: the server is asked again until it answers.
            .task(id: offlineAsOf) {
                while offlineAsOf != nil, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    await load()
                }
            }
            .onDisappear { pageSummary?.close() }
            .sheet(isPresented: $labelling) {
                LabelPicker(document: document) { failure = $0 }
            }
            .sheet(isPresented: $showingVersions) {
                VersionsView(title: document.displayTitle, versions: versions)
            }
            .sheet(item: $enlarged) { image in
                ImageViewer(url: image.url)
            }
            .alert(
                "Couldn't Update Hister",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
            .alert(
                "Couldn't Show the Page That Way",
                isPresented: Binding(get: { showAsFailure != nil }, set: { if !$0 { showAsFailure = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(showAsFailure ?? "")
            }
    }

    @ViewBuilder private func content(note: AppState.NoteLinks?) -> some View {
        if let preview {
            // A note's chip names its vault ("Work vault"), as in the lists.
            let label = app.label(of: document) == Notes.label
                ? Notes.vaultChip(of: document.url, vaults: app.kuraVaults).text : app.label(of: document)
            let images = app.searchPage.previewImages, kura = app.searchPage.niwaURL, css = palette.cssVariables
            PreviewWebView(
                html: previewPage.html(
                    for: PreviewPageCache.Key(
                        url: document.url, updated: preview.updated, size: preview.contentHTML.utf8.count, title: preview.title,
                        label: label, palette: css, place: note?.place, images: images, kura: kura, extractor: extractor)
                ) {
                    PreviewPage.html(
                        document: document, preview: preview, label: label, palette: palette,
                        place: note?.place, images: images, kura: kura)
                },
                baseURL: URL(string: document.url),
                openLink: { url in
                    if app.searchPage.previewImages, PreviewPage.isImage(url) { enlarged = EnlargedImage(url: url) } else { openURL(url) }
                },
                onFinish: { rendered = true },
                onFailure: { renderFailed = true }
            )
            .id(renderAttempt)
            .opacity(rendered && !renderFailed ? 1 : 0)
            // Above the page, not over it: the preview keeps its own scroll.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let offlineAsOf {
                        OfflineNote(asOf: offlineAsOf) { Task { await load() } }
                            .padding(.vertical, 6)
                    }
                    if summary != .none {
                        SummaryCard(state: summary, regenerate: { summarize(note: note != nil, fresh: true) }) {
                            pageSummary?.close()
                        }
                    }
                }
            }
            .overlay {
                if renderFailed {
                    FailureView(error: .previewUnavailable, hasServer: true) {
                        renderFailed = false
                        rendered = false
                        renderAttempt += 1
                    }
                } else if !rendered {
                    ProgressView()
                }
            }
            .background(palette.background)
            .ignoresSafeArea(edges: .bottom)
        } else if let error {
            FailureView(error: error, hasServer: app.client != nil) {
                Task { await load() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
        }
    }

    /// Where the page opens besides the browser, as the results page's
    /// chips: a note's Obsidian, Niwa and Konbini, and Hister for any page.
    private func places(note: AppState.NoteLinks?) -> [OpenPlace] {
        var places: [OpenPlace] = []
        if let note {
            if note.obsidian != nil {
                places.append(.init(name: "Obsidian", help: "Edit in Obsidian", symbol: "doc.text") { openURL.openNote(note) })
            }
            if let url = note.niwa {
                places.append(.init(name: "Kura", help: "View in Kura", symbol: "book") { openURL(url) })
            }
            if let url = note.konbini {
                places.append(.init(name: "Konbini", help: "View Card in Konbini", symbol: "rectangle.split.3x1") { openURL(url) })
            }
        }
        // A code document's repo note (Kura's), when there is one.
        if let repoNote {
            places.append(.init(name: "Repo Note", help: "The Repo's Note in Kura", symbol: "book") { openURL(repoNote) })
        }
        // Not a note: notes are Kura's (Hister may not hold one).
        if note == nil, !workNote, let url = app.client?.webPreviewURL(for: document.url) {
            places.append(.init(name: "Hister", help: "Open in Hister", symbol: "magnifyingglass") { openURL(url) })
        }
        return places
    }

    /// On the Mac `.primaryAction` means the toolbar's leading edge; the
    /// page's items are ordinary ones, pushed trailing by the spacer below.
    #if os(macOS)
    private static let pagePlacement: ToolbarItemPlacement = .automatic
    #else
    private static let pagePlacement: ToolbarItemPlacement = .primaryAction
    #endif

    /// A gap between the toolbar's groups (the original's Open and Share,
    /// the places, ⋯) on iOS 26, where they otherwise merge into one glass
    /// capsule.
    #if os(iOS)
    @ToolbarContentBuilder private var pageGroupGap: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: Self.pagePlacement)
        }
    }
    #endif

    @ToolbarContentBuilder private func toolbar(note: AppState.NoteLinks?) -> some ToolbarContent {
        #if os(macOS)
        // The Mac's one window toolbar puts the page's items right after the
        // sidebar button, over the results, whatever their placement; a
        // flexible spacer first pushes them to the trailing end, over the
        // page, beside the search field (macOS 26; before it they stay).
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        #endif
        if localFile {
            // Hister's copy: the file:// address is the server's, not ours.
            if let served = app.servedFile(document.url) {
                ToolbarItem(placement: Self.pagePlacement) {
                    Button("Open", systemImage: "doc") { openURL(served) }
                        .help("Open Hister's copy")
                }
            }
        } else if note == nil, let url = SafeHref.url(document.url) {
            ToolbarItem(placement: Self.pagePlacement) {
                Button("Open in Browser", systemImage: "safari") { openURL(url) }
                    .help("Open in browser")
            }
            ToolbarItem(placement: Self.pagePlacement) {
                ShareLink(item: url)
                    .help("Share")
            }
            #if os(iOS)
            pageGroupGap
            #endif
        }
        if case let places = places(note: note), !places.isEmpty {
            // One grouped control of plain symbols, the system's colours:
            // four coloured words in four capsules fought the glass (its
            // vibrancy adapts text to what's behind it) and gave the bar no
            // hierarchy. Colour stays in the content: the rows' chips and the
            // list's tabs. The iPhone too (it had a row of text pills).
            // Buttons, not Links: the Mac's toolbar clipped a Link's glass pill.
            ToolbarItem(placement: Self.pagePlacement) {
                ControlGroup {
                    ForEach(places) { place in
                        Button(place.help, systemImage: place.symbol, action: place.open)
                            .help(place.help)
                    }
                } label: {
                    Label("Open In", systemImage: "arrow.up.forward.app")
                }
                .controlGroupStyle(.navigation)
            }
        }
        if showsSummarizeButton(note: note) {
            ToolbarItem(placement: Self.pagePlacement) {
                Button("Summarize", systemImage: "sparkles") { summarize(note: note != nil) }
                    .help("Summarize this page")
                    .disabled(preview == nil || summary == .working)
            }
        }
        #if os(iOS)
        pageGroupGap
        #endif
        ToolbarItem(placement: Self.pagePlacement) {
            Menu {
                // First, and flat: what the toolbar left out.
                if note == nil, !localFile, !code {
                    Button("Edit Label…", systemImage: "tag") { labelling = true }
                }
                if canSummarize(note: note), !workNote, !localFile {
                    Button("Summarize", systemImage: "sparkles") { summarize(note: note != nil) }
                        .disabled(preview == nil || summary == .working)
                }
                // Save This Note's Links: the default vault's notes only
                // (Kura gives a work note none, and it's never offered), and
                // only with a Kura address: the links are Kura's, wherever notes come from.
                if note != nil, !workNote, app.notesKura != nil, let path = Notes.path(of: document.url, cards: app.konbiniCards) {
                    Button("Save Links to Hister…", systemImage: "link.badge.plus") {
                        app.saveLinksRequest = .note(path)
                    }
                    let folder = (path as NSString).deletingLastPathComponent
                    if !folder.isEmpty {
                        Button("Save Links in \(folder)…", systemImage: "folder.badge.plus") {
                            app.saveLinksRequest = .folder(folder)
                        }
                    }
                }
                if let focus {
                    Button(focus.isOn ? "Exit Full Screen" : "Full Screen",
                           systemImage: focus.isOn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        focus.toggle()
                    }
                }
                Divider()
                if let url = localFile ? app.servedFile(document.url) : URL(string: document.url) {
                    Button("Copy Link", systemImage: "link") { Pasteboard.copy(url) }
                }
                if extractors.count > 1 {
                    // Inline: the choices in the menu itself, not a submenu.
                    Section("Show As") {
                        Picker("Show As", selection: Binding(get: { extractor ?? "" }, set: { show(as: $0.isEmpty ? nil : $0) })) {
                            Text("Default").tag("")
                            ForEach(extractors) { Text($0.name).tag($0.name) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                if !versions.isEmpty {
                    Button("Earlier Versions (\(versions.count))…", systemImage: "clock.arrow.circlepath") {
                        showingVersions = true
                    }
                }
                // Gone at once, with Undo for a few seconds (no confirmation),
                // as everywhere else. Not for a work note (Hister never has
                // one) or a file (Hister watches its folder).
                if !workNote, !localFile, !code {
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        app.deletes.start(document)
                        dismiss()
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            // Just the three dots, no arrow beside them.
            .menuIndicator(.hidden)
            .help("More actions")
        }
    }

    /// A private vault's note: no AI, Hister link or delete is offered for
    /// it. (Every other vault's note is previewed from Kura, below.)
    private var workNote: Bool { app.isWorkNote(document.url) }

    /// A file from the folders Hister watches: opened from Hister's copy;
    /// never labelled, deleted, or given to a model.
    private var localFile: Bool { app.isLocalFile(document.url) }
    /// Your repos (code-import's): never labelled or deleted here,
    /// and summarized on the device only (`AIContent.code`).
    private var code: Bool { document.code != nil }

    /// Whether an engine may summarize this: code only on the device. From
    /// settings alone: no engine is built, no key read, as the view draws.
    private func canSummarize(note: AppState.NoteLinks?) -> Bool {
        app.ai.hasEngine(for: code ? .code : note != nil ? .note : .page)
    }

    private func load() async {
        // The newest load wins: Show As starts one while the page's own may
        // still be on its way, and an older answer landing last put the
        // other view back on screen.
        loadGeneration += 1
        let generation = loadGeneration
        let asked = extractor
        // A copy fetched before a sign-out is never kept after it.
        let epoch = OfflineStore.epoch
        func current() -> Bool { generation == loadGeneration }
        let isNote = app.noteLinks(for: document) != nil || Notes.otherVault(of: document.url) != nil
        if isNote, app.notesFrom == .hister, !Notes.histerNoteShown(document.url) {
            // Notes from Hister: the default vault's alone. Another vault's
            // (shared or private: without Kura they can't be told apart) is
            // never asked of Hister.
            error = .notFound
            return
        }
        if isNote, app.notesFrom == .kura {
            // Every note from Kura, its sanitized HTML (Hister may not hold
            // one). A private vault's is never kept (`OfflineStore.keepable`);
            // the default vault's may be, for reading offline. From Hister
            // (Settings → Notes → Notes From), the default vault's note is
            // Hister's readable copy, below.
            let vault = Notes.otherVault(of: document.url) ?? ""
            guard let kura = app.notesKura else {
                error = .unreachable
                return
            }
            // A Konbini card (/p/<slug>) by its vault path, from the cards.
            guard let path = Notes.path(of: document.url, cards: app.konbiniCards) else {
                error = .notFound
                return
            }
            do {
                let html = try await kura.noteHTML(path: path, vault: vault)
                guard current() else { return }
                loaded(PagePreview(
                    title: document.displayTitle, contentHTML: html, added: document.added, updated: document.updated,
                    label: Notes.label, visits: 0, author: nil, summary: nil), extractor: asked, epoch: epoch)
            } catch .cancelled {
            } catch let failure {
                if current() { failed(failure, extractor: asked) }
            }
            return
        }
        guard let client = app.client else {
            error = .unreachable
            return
        }
        do {
            let fresh = try await client.preview(of: document.url, extractor: asked)
            guard current() else { return }
            loaded(fresh, extractor: asked, epoch: epoch)
        } catch .cancelled {
        } catch let failure {
            if current() { failed(failure, extractor: asked) }
        }
    }

    /// Where offline copies come from: this server and Kura.
    private var offlineOrigin: String { OfflineStore.origin(server: app.serverURL, kura: app.searchPage.niwaURL) }

    /// A fresh preview, kept for reading offline (the server's own view
    /// only, not another Show As).
    private func loaded(_ fresh: PagePreview, extractor: String?, epoch: Int) {
        if preview != fresh { rendered = false }
        preview = fresh
        error = nil
        offlineAsOf = nil
        if extractor == nil { OfflineStore.savePreview(fresh, for: document, origin: offlineOrigin, epoch: epoch) }
    }

    /// Out of reach: the copy kept from the last time, if any; a copy
    /// already on screen stays.
    private func failed(_ failure: HisterError, extractor: String?) {
        if offlineAsOf != nil { return }
        if failure == .unreachable, extractor == nil, preview == nil,
           let copy = OfflineStore.preview(for: document, origin: offlineOrigin) {
            preview = copy.preview
            offlineAsOf = copy.savedAt
            error = nil
            return
        }
        error = failure
    }

    /// Versions and extractors, for the menu: quietly nothing on failure.
    private func loadExtras() async {
        guard !workNote, let client = app.client else { return }
        async let versions = try? client.versions(of: document.url)
        async let extractors = try? client.extractors(for: document.url)
        self.versions = await versions ?? []
        self.extractors = await extractors ?? []
    }

    // MARK: Summarize

    /// In the toolbar where there's room (the Mac, a regular-width iPad);
    /// the iPhone has it in the ⋯ menu.
    private func showsSummarizeButton(note: AppState.NoteLinks?) -> Bool {
        guard !workNote, !localFile, canSummarize(note: note) else { return false }
        #if os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    private var summary: SummaryState { pageSummary?.state ?? .none }

    private func summarizer() -> PageSummary {
        if let pageSummary { return pageSummary }
        let made = PageSummary(
            chain: { [app] in app.ai.chain },
            isPrivateNow: { [app] in await app.isWorkNoteNow($0) },
            store: .live)
        pageSummary = made
        return made
    }

    /// `fresh`: Regenerate, past the cache.
    private func summarize(note: Bool, fresh: Bool = false) {
        guard let preview else { return }
        summarizer().summarize(document: document, preview: preview, isNote: note, fresh: fresh)
    }

    /// Another of the server's views of the page. The page on screen stays
    /// until the new one arrives (`loaded` redraws only a changed page: an
    /// unchanged one never finished loading and left a blank page and a
    /// spinner); one that fails says so and keeps the view it had.
    private func show(as name: String?) {
        guard name != extractor else { return }
        let previous = extractor
        extractor = name
        renderFailed = false
        Task {
            await load()
            guard extractor == name, let failed = error, preview != nil else { return }
            error = nil
            extractor = previous
            showAsFailure = failed.userMessage
        }
    }

}

/// Somewhere a page opens besides the browser: a note's Obsidian, Niwa
/// and Konbini, and Hister for any page. Symbols in one toolbar group.
struct OpenPlace: Identifiable {
    var id: String { name }
    let name: String
    let help: String
    let symbol: String
    let open: () -> Void
}

/// One built preview page and what it was built from. A class, so the body
/// can keep it without a state change; the same string comes back while
/// nothing changed, which also makes the web view's "already loaded" check
/// a pointer compare.
final class PreviewPageCache {
    struct Key: Hashable {
        var url: String
        var updated: Date
        var size: Int
        var title: String
        var label: String
        var palette: String
        var place: String?
        var images: Bool
        var kura: String
        /// Show As: another view of the same page can be the same size.
        var extractor: String?
    }

    private var key: Key?
    private var built = ""

    func html(for key: Key, make: () -> String) -> String {
        if key != self.key {
            built = make()
            self.key = key
        }
        return built
    }
}
