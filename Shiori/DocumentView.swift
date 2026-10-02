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
    @State private var preview: PagePreview?
    /// Another of the server's extractors, from Show As (nil: its default).
    @State private var extractor: String?
    @State private var extractors: [Extractor] = []
    @State private var versions: [PageVersion] = []
    @State private var showingVersions = false
    @State private var enlarged: EnlargedImage?
    @State private var error: HisterError?
    @State private var labelling = false
    @State private var failure: String?
    @State private var rendered = false
    @State private var renderFailed = false
    /// Bumped by Try Again after a failed render: a fresh web view.
    @State private var renderAttempt = 0
    /// Summarize (Settings → AI): the card above the preview.
    @State private var summary: SummaryState = .none
    @State private var summarizing: Task<Void, Never>?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        // Once per render: the note's links and place (it was worked out five times).
        let note = app.noteLinks(for: document)
        content(note: note)
            // A vault note by its name, not the Niwa or Konbini host it is stored under.
            .navigationTitle(note == nil ? document.domain : document.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar(note: note) }
            .task(id: document.url) {
                summarizing?.cancel()
                summary = .none
                await app.loadCardsIfNeeded()
                await load()
                showCachedSummary()
                await loadExtras()
            }
            .onDisappear { summarizing?.cancel() }
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
    }

    @ViewBuilder private func content(note: AppState.NoteLinks?) -> some View {
        if let preview {
            PreviewWebView(
                html: PreviewPage.html(
                    document: document, preview: preview,
                    // A note's chip names its vault ("Work vault"), as in the lists.
                    label: app.label(of: document) == Notes.label
                        ? Notes.vaultChip(of: document.url, vaults: app.kuraVaults).text : app.label(of: document),
                    palette: palette,
                    place: note?.place, images: app.searchPage.previewImages, kura: app.searchPage.niwaURL),
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
                if summary != .none {
                    SummaryCard(state: summary, regenerate: { summarize(note: note != nil, fresh: true) }, close: closeSummary)
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
        // Not a work note: Hister never has one.
        if !workNote, let url = app.client?.webPreviewURL(for: document.url) {
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
        if note == nil, let url = URL(string: document.url) {
            ToolbarItem(placement: Self.pagePlacement) {
                Button("Open in Browser", systemImage: "safari") { openURL(url) }
                    .help("Open in browser")
            }
            ToolbarItem(placement: Self.pagePlacement) {
                ShareLink(item: url)
                    .help("Share")
            }
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
        ToolbarItem(placement: Self.pagePlacement) {
            Menu {
                // First, and flat: what the toolbar left out.
                if note == nil {
                    Button("Edit Label…", systemImage: "tag") { labelling = true }
                }
                if app.ai.hasEngine(note: note != nil), !workNote {
                    Button("Summarize", systemImage: "sparkles") { summarize(note: note != nil) }
                        .disabled(preview == nil || summary == .working)
                }
                // Save This Note's Links: the default vault's notes only
                // (Kura gives a work note none, and it's never offered).
                if note != nil, !workNote, let path = Notes.path(of: document.url, cards: app.konbiniCards) {
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
                if let url = URL(string: document.url) {
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
                // as everywhere else. Not for a work note: Hister never has one.
                if !workNote {
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        app.deleteWithUndo(document)
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

    private func load() async {
        if let vault = Notes.otherVault(of: document.url) {
            // Kura's sanitized HTML, for any vault but the default: Hister
            // never has a private one's. Shown, never cached.
            guard let kura = app.notesKura, let path = Notes.path(of: document.url, cards: []) else {
                error = .unreachable
                return
            }
            do {
                let html = try await kura.noteHTML(path: path, vault: vault)
                preview = PagePreview(
                    title: document.displayTitle, contentHTML: html, added: document.added, updated: document.updated,
                    label: Notes.label, visits: 0, author: nil, summary: nil)
                error = nil
            } catch .cancelled {
            } catch let failure {
                error = failure
            }
            return
        }
        guard let client = app.client else {
            error = .unreachable
            return
        }
        do {
            preview = try await client.preview(of: document.url, extractor: extractor)
            error = nil
        } catch .cancelled {
        } catch let failure {
            error = failure
        }
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
        guard !workNote, app.ai.hasEngine(note: note != nil) else { return false }
        #if os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    /// A summary made before, for this version of the page: shown again.
    private func showCachedSummary() {
        guard let preview, let cached = SummaryCache.read(url: document.url, updated: preview.updated) else { return }
        summary = .done(cached)
    }

    /// `fresh`: Regenerate, past the cache. A note is summarized only by an
    /// engine it may use (never a cloud one: `EngineChain` decides).
    private func summarize(note: Bool, fresh: Bool = false) {
        guard let preview else { return }
        if !fresh, let cached = SummaryCache.read(url: document.url, updated: preview.updated) {
            summary = .done(cached)
            return
        }
        let isNote = note || document.label == Notes.label
        // A work note reaches no model at all (EngineChain refuses
        // `.workNote`), even if a button slipped through.
        let content: AIContent = workNote ? .workNote : isNote ? .note : .page
        let chain = app.ai.chain
        let title = preview.title.isEmpty ? document.displayTitle : preview.title
        let url = document.url
        summarizing?.cancel()
        summary = .working
        summarizing = Task {
            do {
                let made = try await Summarizer(chain: chain).summarize(
                    title: title, url: url, html: preview.contentHTML, content: content)
                SummaryCache.write(made, url: url, updated: preview.updated)
                guard !Task.isCancelled, url == document.url else { return }
                summary = .done(made)
            } catch is CancellationError {
            } catch AIError.noEngine where isNote {
                guard !Task.isCancelled else { return }
                summary = .failed("Notes are summarized only on this device or your own server, never by an AI provider, and neither is available.")
            } catch {
                guard !Task.isCancelled, url == document.url else { return }
                summary = .failed(error.localizedDescription)
            }
        }
    }

    private func closeSummary() {
        summarizing?.cancel()
        summary = .none
    }

    private func show(as name: String?) {
        guard name != extractor else { return }
        extractor = name
        rendered = false
        renderFailed = false
        Task { await load() }
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
