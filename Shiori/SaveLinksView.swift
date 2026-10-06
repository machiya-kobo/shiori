import HisterKit
import SwiftUI

/// What Save This Note's Links works on: one note, or every note under a
/// folder of the default vault (Kura's `/api/note`, `/api/links`).
enum SaveLinksTarget: Identifiable, Hashable {
    /// A vault path, "Notes/Sample.md".
    case note(String)
    /// A folder, "Reading" (its subfolders too).
    case folder(String)

    var id: String {
        switch self {
        case .note(let path): "note:" + path
        case .folder(let folder): "folder:" + folder
        }
    }

    /// `shiori://save-links?path=<vault path>` (Kura's note view) or
    /// `?folder=<folder>`.
    init?(url: URL) {
        guard url.scheme == "shiori", url.host() == "save-links",
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        if let path = items.first(where: { $0.name == "path" })?.value, !path.isEmpty {
            self = .note(path)
        } else if let folder = items.first(where: { $0.name == "folder" })?.value, !folder.isEmpty, folder != "/" {
            self = .folder(folder)
        } else {
            return nil
        }
    }

    var title: String {
        switch self {
        case .note(let path): (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        case .folder(let folder): folder
        }
    }
}

/// The links of a note (or a folder's notes), what Hister holds of them,
/// and their saving, one at a time (`Saver.saveLink`).
@Observable
final class SaveLinksModel {
    enum Status: Equatable {
        case checking, inHister, notYet, saving, saved, queued
        /// A link to a file (a package, an image, a PDF): nothing to save.
        case file
        /// A gemini:// or gopher:// link with no small-web gateway set up.
        case needsGateway
        /// Handed to the small-web gateway, which saves it under this URL.
        case viaGateway(String)
        case skipped(String), rejected(String), failed(String)

        /// Can be ticked and saved.
        var isOpen: Bool {
            switch self {
            case .notYet, .failed: true
            default: false
            }
        }
    }

    struct Row: Identifiable {
        var link: LinkToSave
        var status: Status = .checking
        var selected = false
        var id: String { link.id }
    }

    enum Phase: Equatable { case loading, loaded, failed(String) }

    let target: SaveLinksTarget
    private(set) var rows: [Row] = []
    private(set) var phase: Phase = .loading
    /// The notes' tags that name an existing label.
    private(set) var candidates: [String] = []
    var label: String?
    private(set) var isSaving = false
    private(set) var savedCount = 0

    init(target: SaveLinksTarget) {
        self.target = target
    }

    var selectedCount: Int { rows.filter { $0.selected && $0.status.isOpen }.count }
    /// The notes in the order their links came, for grouping a folder's.
    var notes: [(path: String, title: String)] {
        var seen = Set<String>()
        return rows.compactMap { seen.insert($0.link.notePath).inserted ? ($0.link.notePath, $0.link.noteTitle) : nil }
    }

    func load(app: AppState) async {
        guard let kura = app.notesKura else {
            phase = .failed("Set Kura's address in Settings → Notes first.")
            return
        }
        do {
            let found: [LinkedNote]
            switch target {
            case .note(let path): found = [try await kura.noteLinks(path: path)]
            case .folder(let folder): found = try await kura.allFolderLinks(folder: folder)
            }
            rows = SaveLinks.links(in: found).map {
                Row(link: $0, status: SaveLinks.looksLikeFile($0.url) ? .file
                    : SaveLinks.isSmallWeb($0.url) && app.smallweb == nil ? .needsGateway : .checking)
            }
            candidates = SaveLinks.labelCandidates(tags: found.flatMap(\.tags), labels: app.rules.labels)
            phase = .loaded
        } catch let error as HisterError {
            phase = .failed(error == .server(status: 404, message: "") ? "Kura doesn't have that note." : "Kura didn't answer.")
            return
        } catch {
            phase = .failed("Kura didn't answer.")
            return
        }
        // What Hister holds, in a few searches (url:(a|a/|b|…)).
        guard let client = app.client else {
            for i in rows.indices { rows[i].status = .notYet }
            return
        }
        for start in stride(from: 0, to: rows.count, by: 30) {
            let batch = Array(rows[start..<min(start + 30, rows.count)])
            // A small-web link also under its conservative form (host
            // lowercased, default port gone), as the gateway saves it.
            let forms = batch.flatMap { row in
                SaveLinks.isSmallWeb(row.link.url) ? [row.link.url, SaveLinks.smallWebKey(row.link.url)] : [row.link.url]
            }
            let held = await client.savedLabels(for: forms)
            for row in batch where row.status == .checking {
                guard let i = rows.firstIndex(where: { $0.id == row.id }) else { continue }
                let inHister = held[row.link.url] != nil
                    || (SaveLinks.isSmallWeb(row.link.url) && held[SaveLinks.smallWebKey(row.link.url)] != nil)
                rows[i].status = inHister ? .inHister : .notYet
                rows[i].selected = !inHister
            }
        }
    }

    func toggle(_ row: Row) {
        guard let i = rows.firstIndex(where: { $0.id == row.id }), rows[i].status.isOpen else { return }
        rows[i].selected.toggle()
    }

    func selectAll(_ on: Bool) {
        for i in rows.indices where rows[i].status.isOpen { rows[i].selected = on }
    }

    /// Saves the ticked links, one at a time. Skip rules hold: a 406 waits
    /// for Save Anyway.
    func save(app: AppState) async {
        guard let client = app.client, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        for row in rows where row.selected && row.status.isOpen {
            await save(row, anyway: false, client: client, app: app)
        }
        app.refreshWaiting()
        // The gateway saves without a label: the batch's goes on once each
        // page has arrived in Hister.
        guard let label else { return }
        for row in rows {
            guard case .viaGateway(let url) = row.status else { continue }
            if await Saver.labelWhenSaved(url, label: label, client: client),
               let i = rows.firstIndex(where: { $0.id == row.id }) {
                rows[i].status = .saved
            }
        }
    }

    /// Save Anyway, for one link a skip rule held back.
    func saveAnyway(_ row: Row, app: AppState) async {
        guard let client = app.client else { return }
        await save(row, anyway: true, client: client, app: app)
        app.refreshWaiting()
    }

    private func save(_ row: Row, anyway: Bool, client: HisterClient, app: AppState) async {
        guard let i = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[i].status = .saving
        let outcome = await Saver.saveLink(
            row.link, label: label, anyway: anyway, client: client, outbox: app.saveOutbox, smallweb: app.smallweb)
        guard let j = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[j].selected = false
        switch outcome {
        case .saved: rows[j].status = .saved; savedCount += 1
        case .queued: rows[j].status = .queued; savedCount += 1
        case .alreadyInHister: rows[j].status = .inHister
        case .skipped(let reason): rows[j].status = .skipped(reason)
        case .rejected(let reason): rows[j].status = .rejected(reason)
        case .failed(let reason): rows[j].status = .failed(reason)
        case .cancelled: rows[j].status = .notYet
        case .viaGateway(let url): rows[j].status = .viaGateway(url); savedCount += 1
        }
    }
}

/// Save This Note's Links: a note's (or
/// a folder's) outside links, what Hister holds of them, and the rest saved
/// on request, with a label for the batch if chosen.
struct SaveLinksView: View {
    let target: SaveLinksTarget
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var model: SaveLinksModel

    init(target: SaveLinksTarget) {
        self.target = target
        _model = State(initialValue: SaveLinksModel(target: target))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.savedCount > 0 ? "Done" : "Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.selectedCount == 1 ? "Save 1 Link" : "Save \(model.selectedCount) Links") {
                            Task { await model.save(app: app) }
                        }
                        .disabled(model.selectedCount == 0 || model.isSaving)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 620)
        #endif
        .task { await model.load(app: app) }
    }

    private var navigationTitle: String {
        switch target {
        case .note: "Save Links from \(target.title)"
        case .folder: "Save Links in \(target.title)"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Finding the links…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("No Links", systemImage: "link", description: Text(message))
        case .loaded where model.rows.isEmpty:
            ContentUnavailableView("No Links", systemImage: "link",
                                   description: Text("No links to other sites in \(target.title)."))
        case .loaded:
            List {
                Section {
                    labelRow
                } footer: {
                    Text("Pages are saved one at a time. Ones Hister already holds are never sent again, and sites Hister skips wait for Save Anyway.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                // One note: its links alone. A folder: a section per note.
                if model.notes.count > 1 {
                    ForEach(model.notes, id: \.path) { note in
                        Section(note.title) {
                            ForEach(model.rows.filter { $0.link.notePath == note.path }) { row in
                                LinkRow(row: row, model: model)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(model.rows) { row in LinkRow(row: row, model: model) }
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
    }

    /// One label for the batch: none, a note's tag that names a label, or
    /// any label from the picker.
    private var labelRow: some View {
        HStack(spacing: 8) {
            Text("Label").textStyle(.body)
            Spacer()
            ForEach(model.candidates, id: \.self) { candidate in
                Button {
                    model.label = model.label == candidate ? nil : candidate
                } label: {
                    LabelChip(label: candidate)
                        .opacity(model.label == nil || model.label == candidate ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .help(model.label == candidate ? "Don't label them" : "Label them \(candidate)")
            }
            Menu {
                Button("None") { model.label = nil }
                ForEach(app.rules.collections, id: \.name) { collection in
                    Section(CollectionIcon.title(for: collection.name)) {
                        ForEach(collection.labels, id: \.self) { name in
                            Button(name) { model.label = name }
                        }
                    }
                }
                let grouped = Set(app.rules.collections.flatMap(\.labels))
                Section("Other Labels") {
                    ForEach(app.rules.labels.filter { !grouped.contains($0) }, id: \.self) { name in
                        Button(name) { model.label = name }
                    }
                }
            } label: {
                Text(model.label.map { model.candidates.contains($0) ? "Other…" : $0 } ?? "None")
            }
            .fixedSize()
        }
    }
}

private struct LinkRow: View {
    let row: SaveLinksModel.Row
    let model: SaveLinksModel
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                model.toggle(row)
            } label: {
                Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.status.isOpen ? palette.accent : palette.secondaryText.opacity(0.4))
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .disabled(!row.status.isOpen)
            .accessibilityLabel(row.selected ? "Selected" : "Not selected")
            VStack(alignment: .leading, spacing: 2) {
                Text(row.link.text.isEmpty || row.link.text == row.link.url ? host : row.link.text)
                    .textStyle(.body)
                    .lineLimit(2)
                Text(row.link.url)
                    .textStyle(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .skipped(let reason) = row.status {
                    HStack {
                        Text(reason).textStyle(.caption).foregroundStyle(palette.secondaryText)
                        Button("Save Anyway") { Task { await model.saveAnyway(row, app: app) } }
                            .buttonStyle(.borderless)
                            .textStyle(.caption, weight: .semibold)
                    }
                } else if case .rejected(let reason) = row.status {
                    Text(reason).textStyle(.caption).foregroundStyle(palette.secondaryText)
                } else if case .failed(let reason) = row.status {
                    Text(reason).textStyle(.caption).foregroundStyle(palette.danger)
                }
            }
            Spacer(minLength: 8)
            status
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(row) }
    }

    private var host: String { URL(string: row.link.url)?.host() ?? row.link.url }

    @ViewBuilder private var status: some View {
        switch row.status {
        case .checking, .saving:
            ProgressView().controlSize(.small)
        case .inHister:
            Label("In Hister", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .textStyle(.caption, weight: .medium)
                .foregroundStyle(palette.secondaryText)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle")
                .textStyle(.caption, weight: .medium)
                .foregroundStyle(palette.accent)
        case .queued:
            Label("Waiting", systemImage: "clock")
                .textStyle(.caption, weight: .medium)
                .foregroundStyle(palette.secondaryText)
                .help("Hister is out of reach: it's sent when Hister is back.")
        case .needsGateway:
            Text("Needs the small-web gateway")
                .textStyle(.caption, weight: .medium)
                .foregroundStyle(palette.secondaryText)
                .help("Set the small-web gateway in Settings → Search.")
        case .viaGateway:
            Label("Sent to the gateway", systemImage: "arrow.up.circle")
                .textStyle(.caption, weight: .medium)
                .foregroundStyle(palette.accent)
                .help("The gateway saves it to Hister in a moment.")
        case .file:
            Text("A file, not a web page")
                .textStyle(.caption, weight: .medium)
                .foregroundStyle(palette.secondaryText)
                .help("Not a web page: nothing for Hister to read.")
        case .notYet, .failed, .skipped, .rejected:
            EmptyView()
        }
    }
}
