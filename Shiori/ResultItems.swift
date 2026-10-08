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
                        app.deletes.start(document)
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
        case page, note, opened, file, code, smallweb
    }

    let kind: Kind
    var selected = false
    // Passed in, not read from the environment: a list row's background is
    // drawn outside the row's environment on the Mac, and asking it for
    // AppState trapped (a crash); the palette would fall back to
    // its default, not the theme.
    let palette: Palette
    let style: String

    private var tint: Palette.Tint {
        switch kind {
        case .page: SearchScope.hister.tint
        case .note: SearchScope.notes.tint
        case .opened: SearchScope.opened.tint
        case .file: SearchScope.files.tint
        case .code: SearchScope.code.tint
        case .smallweb: SearchScope.smallweb.tint
        }
    }

    private var color: Color { palette.tint(tint) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let selection = selected ? palette.accent.opacity(0.22) : Color.clear
        // Settings → Results → Result Style: the tinted card, a plain card
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

/// One page from Hister, with its swipes and menu. A click (a tap) on it
/// opens the original (`openPage`: a page in the browser, a note in
/// Obsidian, a file from Hister's copy) or Shiori's preview, as Settings →
/// Click Opens says (`clickOpensOriginal`); the other is the first swipe and
/// leads its menu. Its title always opens the original. Beside a preview
/// pane (`previewSelection`), previewing is selecting, and the list carries
/// the menu.
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
        let original = app.rowStyle.clickOpensOriginal(pane: selection != nil)
        if let selection {
            Group {
                // Selecting previews; a row that opens the original is a
                // button, which takes the click before the list selects.
                if original {
                    row(note: note, original: true)
                } else {
                    DocumentRow(document: document, label: app.label(of: document), notePlace: note?.place)
                }
            }
            .tag(document)
            // Its place in the list, for j and k.
            .preference(key: ListOrderKey.self, value: [document])
            // The theme's background, and a tint for the selected page.
            .listRowBackground(ResultBar(kind: kind(note), selected: selection.wrappedValue == document,
                                         palette: palette, style: app.rowStyle.resultStyle))
            .resultSeparator(app.rowStyle.resultStyle)
            .modifier(Swipes(document: document, note: note, original: original))
        } else {
            row(note: note, original: original)
                .listRowBackground(ResultBar(kind: kind(note), palette: palette, style: app.rowStyle.resultStyle))
                .resultSeparator(app.rowStyle.resultStyle)
                .modifier(Swipes(document: document, note: note, original: original))
                .contextMenu { DocumentMenu(document: document) }
        }
    }

    private struct Swipes: ViewModifier {
        let document: StoredPage
        let note: AppState.NoteLinks?
        /// A click opens the original, so the swipe previews (else the
        /// other way round).
        let original: Bool
        @Environment(\.palette) private var palette
        @Environment(\.openURL) private var openURL
        @Environment(\.resultActions) private var actions

        func body(content: Content) -> some View {
            content
                .swipeActions(edge: .leading) {
                    // The first is the full swipe. A note's label is "vault"
                    // (it's what makes it a note); its tags are Obsidian's.
                    // A file is never labelled.
                    if LocalFiles.isLocalFile(document.url) {
                        other.tint(palette.tint(SearchScope.files.tint))
                    } else if note == nil {
                        // A code document is code-import's: never labelled here.
                        if document.code == nil {
                            Button("Label", systemImage: "tag") { actions.label(document) }
                                .tint(palette.accent)
                        }
                        other.tint(palette.tint(.cyan))
                    } else {
                        if let niwa = note?.niwa {
                            Button("Kura", systemImage: "book") { openURL(niwa) }
                                .tint(palette.tint(.orange))
                        }
                        other.tint(palette.accent)
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

        /// What a click doesn't do.
        @ViewBuilder private var other: some View {
            if original {
                PreviewButton(document: document)
            } else {
                OpenOriginalButton(document: document, short: true)
            }
        }
    }

    /// The whole row as one button: the original (`openPage`) or Shiori's
    /// preview. A button, not a NavigationLink: on iOS 27 a gesture added
    /// beside a link (to record the open) swallowed its tap.
    private func row(note: AppState.NoteLinks?, original: Bool) -> some View {
        Button {
            actions.opened(document)
            if original { openURL.openPage(document, app: app) } else { actions.preview(document) }
        } label: {
            DocumentRow(document: document, label: app.label(of: document), notePlace: note?.place)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(original ? OpenOriginalButton.title(for: document, app: app) : "Preview")
        .accessibilityHint(original ? OpenOriginalButton.hint(for: document, app: app) : "Shows Shiori's preview")
    }
}

/// Opens a result's original (`openPage`), named for where it goes: a
/// page's browser, a note's Obsidian (or Kura), a file's copy.
/// A result's title, the link to the original: underlined under the pointer,
/// with the link cursor on the Mac, as the web pages draw a hovered link. A
/// click beside it does what Click Opens says, so the link must read apart
/// from the card around it. A plain button, drawn by SwiftUI: a borderless
/// one is AppKit's on the Mac and takes the pointer, so its label never
/// hears the hover.
struct TitleLink: View {
    let title: String
    let help: String
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(.headline)
                .foregroundStyle(palette.accent)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        .help(help)
    }
}

/// A hover highlight for things that select (the sidebar's rows, the pills
/// over a list), as the web pages draw theirs: a light fill of the thing's
/// own colour under the pointer, never on the one already chosen. Drawn
/// behind the content, past its edges, so nothing moves.
struct HoverFill<S: Shape>: ViewModifier {
    let shape: S
    let color: Color
    var active = true
    var outset = EdgeInsets()
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(color.opacity(hovering && active ? 0.14 : 0)).padding(outset))
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverFill<S: Shape>(_ shape: S, color: Color, active: Bool = true, outset: EdgeInsets = EdgeInsets()) -> some View {
        modifier(HoverFill(shape: shape, color: color, active: active, outset: outset))
    }
}

struct OpenOriginalButton: View {
    let document: StoredPage
    /// "Open", for a swipe's narrow button.
    var short = false
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.resultActions) private var actions

    var body: some View {
        Button(short ? "Open" : Self.title(for: document, app: app), systemImage: Self.symbol(for: document, app: app)) {
            actions.opened(document)
            openURL.openPage(document, app: app)
        }
    }

    static func title(for document: StoredPage, app: AppState) -> String {
        if let note = app.noteLinks(for: document) { return note.obsidian != nil ? "Edit in Obsidian" : "View in Kura" }
        return LocalFiles.isLocalFile(document.url) ? "Open" : "Open in Browser"
    }

    static func hint(for document: StoredPage, app: AppState) -> String {
        if let note = app.noteLinks(for: document) { return note.obsidian != nil ? "Opens in Obsidian" : "Opens in Kura" }
        return LocalFiles.isLocalFile(document.url) ? "Opens Hister's copy" : "Opens the page"
    }

    static func symbol(for document: StoredPage, app: AppState) -> String {
        if let note = app.noteLinks(for: document) { return note.obsidian != nil ? "doc.text" : "book" }
        return LocalFiles.isLocalFile(document.url) ? "doc" : "safari"
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
            if let url = SafeHref.url(result.url) { openURL(url) }
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
            if let url = SafeHref.url(result.url) {
                Link(destination: url) { Label("Open in Safari", systemImage: "safari") }
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
                Button("Copy Link", systemImage: "link") { Pasteboard.copy(url) }
                ElsewhereLinks(url: result.url)
            }
        }
    }
}

/// Shiori's preview of a page, for a menu: a view of its own, so it reads
/// the screen's `resultActions` from inside its host.
struct PreviewButton: View {
    let document: StoredPage
    @Environment(\.resultActions) private var actions

    var body: some View {
        Button("Preview", systemImage: "doc.richtext") {
            actions.opened(document)
            actions.preview(document)
        }
    }
}

/// Both ways to open a result, for the top of its menu whatever a click
/// does (Click Opens): Shiori's preview, then the original.
struct OpenChoices: View {
    let document: StoredPage

    var body: some View {
        PreviewButton(document: document)
        OpenOriginalButton(document: document)
    }
}

/// A page's menu: Preview and the original (`OpenChoices`), then label and
/// delete (the swipe actions, as the HIG asks), then share and copy.
struct DocumentMenu: View {
    let document: StoredPage
    @Environment(\.resultActions) private var actions
    @Environment(AppState.self) private var app

    var body: some View {
        OpenChoices(document: document)
        Divider()
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
        // Save This Note's Links: the default vault's notes only, shared vaults
        // included in that "not": Kura's /api/note is asked by path alone,
        // which it reads in the default vault. Only with a Kura address: the
        // links are Kura's, wherever notes come from.
        if app.noteLinks(for: document) != nil, Notes.otherVault(of: document.url) == nil, app.notesKura != nil,
            let path = Notes.path(of: document.url, cards: app.konbiniCards)
        {
            Button("Save Links to Hister…", systemImage: "link.badge.plus") { app.saveLinksRequest = .note(path) }
            let folder = (path as NSString).deletingLastPathComponent
            if !folder.isEmpty {
                Button("Save Links in \(folder)…", systemImage: "folder.badge.plus") { app.saveLinksRequest = .folder(folder) }
            }
            Divider()
        }
        // The original is already at the top.
        DocumentLinks(document: document, skipOriginal: true)
    }
}

extension OpenURLAction {
    /// Opens a result in its own app: a note in Obsidian (Kura when it
    /// can't), a file from Hister's copy, anything else in the browser.
    func openPage(_ document: StoredPage, app: AppState) {
        if let note = app.noteLinks(for: document) {
            openNote(note)
        } else if LocalFiles.isLocalFile(document.url) {
            if let served = app.servedFile(document.url) { self(served) }
        } else if let url = SafeHref.url(document.url) {
            self(url)
        }
    }

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
