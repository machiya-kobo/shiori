import HisterKit
import SwiftUI

/// Library → Opened: results you opened from a search, newest first, with
/// the search each came from (what Remember What You Open tells Hister).
@Observable
final class OpenedModel {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(HisterError)
    }

    private(set) var entries: [OpenedEntry] = []
    private(set) var phase = Phase.idle
    private(set) var isLoadingMore = false
    private var next: OpenedPage.Cursor?
    var byDay = true
    /// A search's text: only what you opened that matches (Hister's filter).
    let filter: String

    init(filter: String = "") {
        self.filter = filter
    }

    func load(using client: HisterClient?) async {
        guard let client else {
            phase = .failed(.unreachable)
            return
        }
        if entries.isEmpty { phase = .loading }
        do {
            let page = try await client.openedHistory(filter: filter)
            entries = page.entries
            next = page.next
            phase = .loaded
        } catch .cancelled {
        } catch {
            if entries.isEmpty { phase = .failed(error) }
        }
    }

    func loadMoreIfNeeded(after entry: OpenedEntry, using client: HisterClient?) async {
        guard let client, let cursor = next, !isLoadingMore, entry.id == entries.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await client.openedHistory(filter: filter, after: cursor) else { return }
        let known = Set(entries.map(\.id))
        entries += page.entries.filter { !known.contains($0.id) }
        next = page.next
    }

    func remove(_ entry: OpenedEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    /// By day of opening, newest first.
    func sections(calendar: Calendar = .current) -> [(id: Date, title: String, entries: [OpenedEntry])] {
        var out: [(id: Date, title: String, entries: [OpenedEntry])] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.added)
            if let i = out.firstIndex(where: { $0.id == day }) {
                out[i].entries.append(entry)
            } else {
                out.append((id: day, title: ResultsModel.title(for: day, byDay: true, calendar: calendar), entries: [entry]))
            }
        }
        return out
    }
}

struct OpenedListView: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.previewSelection) private var selection
    @Environment(\.openURL) private var openURL
    @State private var model: OpenedModel

    init(filter: String = "") {
        _model = State(initialValue: OpenedModel(filter: filter))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
            case .failed(let error):
                FailureView(error: error, hasServer: app.client != nil) {
                    Task { await model.load(using: app.client) }
                }
                .themedBackground()
            case .loaded:
                if model.entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing Opened Yet", systemImage: "eye",
                        description: Text("Results you open from a search show up here (Settings → Results → Remember What You Open)."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .themedBackground()
                } else {
                    list
                }
            }
        }
        .topBar {
            HStack {
                Menu {
                    Picker("Group", selection: $model.byDay) {
                        Text("No Groups").tag(false)
                        Text("By Day").tag(true)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(model.byDay ? "By Day" : "Group", systemImage: "rectangle.3.group")
                }
                .quietControl(active: model.byDay)
                .help("Group")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .endsTopBar()
        }
        // Hister's own feed of what you opened: File on the Mac, Settings on iOS.
        .listActions(ListExport(title: "Opened", feed: app.client?.openedFeedURL))
        .task(id: app.serverURL) { await model.load(using: app.client) }
        .pullToRefresh { await model.load(using: app.client) }
        .resultActions()
    }

    private var list: some View {
        ResultsListContainer {
            if model.byDay {
                ForEach(model.sections(), id: \.id) { section in
                    Section {
                        ForEach(section.entries) { row($0) }
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(section.entries.count.formatted())
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            } else {
                ForEach(model.entries) { row($0) }
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

    @ViewBuilder private func row(_ entry: OpenedEntry) -> some View {
        let page = StoredPage(opened: OpenedResult(url: entry.url, title: entry.title))
        let original = app.rowStyle.clickOpensOriginal(pane: selection != nil)
        let row = VStack(alignment: .leading, spacing: 3) {
            // A link: the title always opens the original.
            Button { openURL.openPage(page, app: app) } label: {
                Text(page.displayTitle)
                    .textStyle(.headline)
                    .foregroundStyle(palette.accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .titleLinkHover()
            }
            .buttonStyle(.borderless)
            .help(OpenOriginalButton.title(for: page, app: app))
            Text("For “\(entry.typedQuery)” · \(entry.added.formatted(date: model.byDay ? .omitted : .abbreviated, time: .shortened))")
                .textStyle(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        Group {
            if original {
                // A click opens the original (Click Opens).
                Button { openURL.openPage(page, app: app) } label: { row.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .tag(page)
            } else if selection != nil {
                row.tag(page)
            } else {
                NavigationLink(value: page) { row }
            }
        }
        .listRowBackground(ResultBar(kind: app.isNotePage(page.url) ? .note : .opened, selected: selection?.wrappedValue == page,
                                     palette: palette, style: app.rowStyle.resultStyle))
        .resultSeparator(app.rowStyle.resultStyle)
        .task { await model.loadMoreIfNeeded(after: entry, using: app.client) }
        .contextMenu {
            OpenChoices(document: page)
            Divider()
            Button("Forget for This Search", systemImage: "eye.slash") { forget(entry) }
            Divider()
            DocumentLinks(document: page, skipOriginal: true)
        }
        .swipeActions(edge: .trailing) {
            Button("Forget", systemImage: "eye.slash") { forget(entry) }
        }
    }

    private func forget(_ entry: OpenedEntry) {
        model.remove(entry)
        Task { try? await app.forgetOpened(entry.url, query: entry.query) }
    }
}
