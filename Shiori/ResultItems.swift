import HisterKit
import SwiftUI

/// What a result row can ask for. The sheets, dialog and navigation behind
/// them live once per screen, in `ResultActionsHost`, so the same rows
/// work in any list: one query's results, or All's sections.
struct ResultActions {
    var label: @MainActor (StoredPage) -> Void = { _ in }
    var delete: @MainActor (StoredPage) -> Void = { _ in }
    var preview: @MainActor (StoredPage) -> Void = { _ in }
    var save: @MainActor (WebResult) -> Void = { _ in }
    /// A page was opened (previewed, or handed to Obsidian or the
    /// browser) from this list: Hister learns it, for the list's search.
    var opened: @MainActor (StoredPage) -> Void = { _ in }
    /// A label tag tapped: that label's pages.
    var showLabel: @MainActor (String) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Set by the Mac and iPad layout: a label opens as its sidebar row.
    /// Without it (the iPhone), the label's list is pushed.
    @Entry var openLabel: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    @Entry var resultActions = ResultActions()
}

extension View {
    /// Label, delete and preview for the Hister rows inside, and Save for
    /// the web rows. `query` is the search the rows came from, for
    /// Remember What You Open (none for browsing lists).
    func resultActions(query: String? = nil) -> some View {
        modifier(ResultActionsHost(query: query))
    }
}

private struct ResultActionsHost: ViewModifier {
    let query: String?
    @Environment(AppState.self) private var app
    @Environment(\.previewSelection) private var selection
    @Environment(\.openLabel) private var openLabel
    @State private var labelRoute: QueryRoute?
    @State private var labelling: StoredPage?
    @State private var previewing: PreviewRequest?
    @State private var saving: WebResult?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .environment(
                \.resultActions,
                ResultActions(
                    label: { labelling = $0 },
                    // Undo instead of a confirmation, as in the web app.
                    delete: { document in
                        if selection?.wrappedValue == document { selection?.wrappedValue = nil }
                        app.deleteWithUndo(document)
                    },
                    // Beside a preview pane, into the pane.
                    preview: { document in
                        if let selection { selection.wrappedValue = document } else { previewing = PreviewRequest(document: document) }
                    },
                    save: { saving = $0 },
                    opened: { document in
                        if let query { app.recordOpened(document, query: query) }
                    },
                    showLabel: { label in
                        if let openLabel { openLabel(label) } else { labelRoute = QueryRoute(title: label, query: "label:\(label)") }
                    }))
            .navigationDestination(item: $labelRoute) { ResultsScreen(route: $0) }
            .navigationDestination(item: $previewing) { DocumentView(document: $0.document) }
            .sheet(item: $labelling) { document in
                LabelPicker(document: document) { failure = $0 }
            }
            .sheet(item: $saving) { result in
                if let url = URL(string: result.url) {
                    SaveSheet(input: .init(url: url, title: result.title))
                }
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
}

/// A result row drawn as a card tinted in its pill's colour, with an outline
/// in it: blue for your pages, orange for notes (Kura's), purple for pages you opened,
/// as the search page's cards. The fill is
/// the most each theme allows with every text colour at 4.5:1 or better:
/// 14% on Tokyo Night's background, 8% on Tokyo Night Day's surface, and for
/// the rooms' other themes the web pages' `--tint-mix` over the surface
/// (`Palette.tintOpacity`, `tintBase`).
struct ResultBar: View {
    enum Kind {
        case page, note, opened, file, code
    }

    let kind: Kind
    var selected = false
    // Passed in, not read from the environment: a list row's background is
    // drawn outside the row's environment on the Mac, and asking it for
    // AppState trapped (a crash); the palette would fall back to
    // its default, not the theme.
    let palette: Palette
    let style: String

    private var color: Color {
        switch kind {
        case .page: palette.tint(SearchScope.hister.tint)
        case .note: palette.tint(SearchScope.notes.tint)
        case .opened: palette.tint(SearchScope.opened.tint)
        case .file: palette.tint(SearchScope.files.tint)
        case .code: palette.tint(SearchScope.code.tint)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let selection = selected ? palette.accent.opacity(0.22) : Color.clear
        // Settings → Search → Result Style: the tinted card, a plain card
        // (Solid), a bar down the leading edge, or plain.
        switch style {
        case "solid":
            solidCard(shape)
        case "bar":
            palette.background.overlay(selection).overlay(alignment: .leading) { color.frame(width: 3) }
        case "none":
            palette.background.overlay(selection)
        default:
            card(shape)
        }
    }

    /// A card in the theme's card colour with a grey hairline, the same for
    /// pages and notes: Tokyo Night's raised
    /// colour, Day's surface, as the web pages' `--card`.
    private func solidCard(_ shape: RoundedRectangle) -> some View {
        ZStack {
            palette.background
            shape
                .fill(palette.isDark ? palette.raised : palette.surface)
                .overlay(shape.fill(selected ? palette.accent.opacity(0.22) : .clear))
                .overlay(shape.strokeBorder(palette.secondaryText.opacity(0.25)))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
    }

    private func card(_ shape: RoundedRectangle) -> some View {
        ZStack {
            palette.background
            shape
                .fill(palette.tintBase)
                .overlay(shape.fill(color.opacity(palette.tintOpacity)))
                .overlay(shape.fill(selected ? palette.accent.opacity(0.22) : .clear))
                .overlay(shape.strokeBorder(color.opacity(0.55)))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
    }
}

extension View {
    /// No separator lines between cards (Tint, Solid): each card's own edge
    /// parts it from the next. Plain rows
    /// (Left Bar, None) keep them.
    func resultSeparator(_ style: String) -> some View {
        listRowSeparator(style == "tint" || style == "solid" || style.isEmpty ? .hidden : .automatic)
    }
}

/// One page from Hister, with its swipes and menu. A vault note opens
/// straight in Obsidian (Niwa if Obsidian can't open it), with Shiori's
/// preview in its menu; anything else opens Shiori's preview. Beside a
/// preview pane (`previewSelection`), a row selects instead, and the list
/// carries the menu.
struct DocumentItem: View {
    let document: StoredPage
    /// One of the pages you opened for this search (All's Your Pages lifts
    /// them to the top): the Opened pill's purple.
    var opened = false
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.resultActions) private var actions
    @Environment(\.previewSelection) private var selection

    private func kind(_ note: AppState.NoteLinks?) -> ResultBar.Kind {
        LocalFiles.isLocalFile(document.url) ? .file : document.code != nil ? .code : note != nil ? .note : opened ? .opened : .page
    }

    var body: some View {
        let note = app.noteLinks(for: document)
        if let selection {
            DocumentRow(document: document, label: app.label(of: document), notePlace: note?.place)
                .tag(document)
                // Its place in the list, for j and k.
                .preference(key: ListOrderKey.self, value: [document])
                // The theme's background, and a tint for the selected page.
                .listRowBackground(ResultBar(kind: kind(note), selected: selection.wrappedValue == document,
                                             palette: palette, style: app.searchPage.resultStyle))
                .resultSeparator(app.searchPage.resultStyle)
                .modifier(Swipes(document: document, note: note))
        } else {
            row(note: note)
                .listRowBackground(ResultBar(kind: kind(note), palette: palette, style: app.searchPage.resultStyle))
                .resultSeparator(app.searchPage.resultStyle)
                .modifier(Swipes(document: document, note: note))
                .contextMenu { DocumentMenu(document: document, previewable: note?.obsidian != nil) }
        }
    }

    private struct Swipes: ViewModifier {
        let document: StoredPage
        let note: AppState.NoteLinks?
        @Environment(\.palette) private var palette
        @Environment(\.openURL) private var openURL
        @Environment(\.resultActions) private var actions

        @Environment(AppState.self) private var app

        func body(content: Content) -> some View {
            content
                .swipeActions(edge: .leading) {
                    // The first is the full swipe. A note's label is "vault"
                    // (it's what makes it a note); its tags are Obsidian's.
                    // A file opens from Hister's copy, and is never labelled.
                    if LocalFiles.isLocalFile(document.url) {
                        if let served = app.servedFile(document.url) {
                            Button("Open", systemImage: "doc") { openURL(served) }
                                .tint(palette.tint(SearchScope.files.tint))
                        }
                    } else if note == nil {
                        // A code document is code-import's: never labelled here.
                        if document.code == nil {
                            Button("Label", systemImage: "tag") { actions.label(document) }
                                .tint(palette.accent)
                        }
                        if let url = URL(string: document.url) {
                            Button("Open in Browser", systemImage: "safari") {
                                actions.opened(document)
                                openURL(url)
                            }
                            .tint(palette.tint(.cyan))
                        }
                    } else {
                        if let niwa = note?.niwa {
                            Button("Kura", systemImage: "book") { openURL(niwa) }
                                .tint(palette.tint(.orange))
                        }
                        // A note's tap opens Obsidian; Shiori's preview is here.
                        Button("Preview", systemImage: "doc.text.magnifyingglass") {
                            actions.opened(document)
                            actions.preview(document)
                        }
                        .tint(palette.accent)
                    }
                    if !LocalFiles.isLocalFile(document.url), let url = URL(string: document.url) {
                        Button("Copy Link", systemImage: "link") { Pasteboard.copy(url) }
                            .tint(palette.tint(.purple))
                    }
                }
                .swipeActions(edge: .trailing) {
                    // The theme's red: without it the app's accent tint (blue)
                    // wins over the destructive role. Not for a work note
                    // (Hister never has one) or a file (Hister watches its folder).
                    if !Notes.isPrivateNote(document.url), !LocalFiles.isLocalFile(document.url), document.code == nil {
                        Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(document) }
                            .tint(palette.danger)
                    }
                }
        }
    }

    @ViewBuilder
    private func row(note: AppState.NoteLinks?) -> some View {
        if let note, note.obsidian != nil {
            Button {
                actions.opened(document)
                openURL.openNote(note)
            } label: {
                DocumentRow(document: document, label: app.label(of: document), notePlace: note.place)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Edit in Obsidian")
            .accessibilityHint("Opens in Obsidian")
        } else {
            // A button, not a NavigationLink: on iOS 27 a gesture added beside
            // a link (to record the open) swallowed its tap, so nothing opened.
            // The screen's ResultActionsHost pushes the page.
            Button {
                actions.opened(document)
                actions.preview(document)
            } label: {
                HStack(spacing: 8) {
                    DocumentRow(document: document, label: app.label(of: document))
                    Image(systemName: "chevron.right")
                        .textStyle(.footnote, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One web result. It opens in Safari, so the Shiori extension captures the
/// page as usual (an in-app browser wouldn't run extensions).
struct WebItem: View {
    let result: WebResult
    let query: String
    /// Hister's label for it ("" = visited), or nil if Hister hasn't it.
    let saved: String?
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.resultActions) private var actions

    var body: some View {
        Button {
            if let url = URL(string: result.url) { openURL(url) }
        } label: {
            WebRow(result: result, query: query, saved: saved)
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.background)
        .swipeActions(edge: .leading) {
            Button("Save", systemImage: "bookmark") { actions.save(result) }
                .tint(palette.accent)
        }
        .contextMenu {
            Button("Save to Hister…", systemImage: "bookmark") { actions.save(result) }
            Divider()
            if let url = URL(string: result.url) {
                Link(destination: url) { Label("Open in Safari", systemImage: "safari") }
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
                Button("Copy Link", systemImage: "link") { Pasteboard.copy(url) }
            }
        }
    }
}

/// A page's menu: label and delete (the swipe actions, first, as the HIG
/// asks), Shiori's preview for a note, then open, share and copy.
struct DocumentMenu: View {
    let document: StoredPage
    var previewable = false
    @Environment(\.resultActions) private var actions
    @Environment(AppState.self) private var app

    var body: some View {
        // Not for a note: its label must stay "vault" (see Swipes). Neither
        // for a file: Hister watches its folder, and the file stays as it is.
        // Nor for code: code-import owns those documents (it re-reads the forge).
        let file = LocalFiles.isLocalFile(document.url) || document.code != nil
        if app.noteLinks(for: document) == nil, !file {
            Button("Edit Label…", systemImage: "tag") { actions.label(document) }
        }
        if !Notes.isPrivateNote(document.url), !file {
            Button("Delete…", systemImage: "trash", role: .destructive) { actions.delete(document) }
        }
        Divider()
        if previewable {
            Button("Preview", systemImage: "doc.richtext") { actions.preview(document) }
        }
        // Save This Note's Links: the default vault's notes only, shared vaults
        // included in that "not": Kura's /api/note is asked by path alone,
        // which it reads in the default vault.
        if app.noteLinks(for: document) != nil, Notes.otherVault(of: document.url) == nil,
            let path = Notes.path(of: document.url, cards: app.konbiniCards)
        {
            Button("Save Links to Hister…", systemImage: "link.badge.plus") { app.saveLinksRequest = .note(path) }
            let folder = (path as NSString).deletingLastPathComponent
            if !folder.isEmpty {
                Button("Save Links in \(folder)…", systemImage: "folder.badge.plus") { app.saveLinksRequest = .folder(folder) }
            }
            Divider()
        }
        DocumentLinks(document: document)
    }
}

extension OpenURLAction {
    /// Opens a note in Obsidian, or on Niwa when Obsidian can't take it
    /// (`openURL`'s completion says whether it was accepted). On macOS
    /// that completion arrives on LaunchServices' own queue, not the main
    /// thread, so the closure can't be main-actor code: it hops back
    /// (it crashed on every note opened from the Mac).
    func openNote(_ note: AppState.NoteLinks) {
        guard let obsidian = note.obsidian else {
            if let niwa = note.niwa { self(niwa) }
            return
        }
        let niwa = note.niwa
        self(obsidian) { @Sendable accepted in
            guard !accepted, let niwa else { return }
            Task { @MainActor in self(niwa) }
        }
    }
}

/// A note's "Preview" (its tap opens Obsidian): its own type, so the stack
/// has one destination for StoredPage (withDestinations) and this one.
struct PreviewRequest: Hashable, Identifiable {
    let document: StoredPage
    var id: String { document.url }
}
