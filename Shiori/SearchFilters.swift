import HisterKit
import SwiftUI
import UniformTypeIdentifiers

// Filters, the results you opened before, and Export/Feed for a results
// list. Filters are Hister query words (`domain:github.com`,
// `-domain:…`, `visits:2..4`, `updated:<7d`), so a filtered search is just
// a longer query: its feed and its export follow the filters too.

/// Above every list: Sort and Group, and the filters in use as chips.
/// In the toolbar, as plain icons: Filter (date, site, visits, and
/// language and type when there's a choice, with counts) and Share (the
/// list's feed, Subscribe in NewsBlur, Export).
extension View {
    /// Sort, Group and Filter above a list: plain secondary text, like the
    /// Safari page's "Anytime", so they don't compete with the coloured
    /// tabs above them. The accent while one is changing the list.
    func quietControl(active: Bool = false) -> some View {
        modifier(QuietControl(active: active))
    }
}

private struct QuietControl: ViewModifier {
    let active: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .textStyle(.subheadline, weight: .medium)
            .foregroundStyle(active ? palette.accent : palette.secondaryText)
            .tint(active ? palette.accent : palette.secondaryText)
            .padding(.vertical, 4)
            .contentShape(.rect)
    }
}

struct ListControls: View {
    let model: ResultsModel
    /// The name for its feed and export ("tech", "rust").
    let title: String
    /// Sort, Group and the filters; off for Search → All, whose sections
    /// mix pages, notes and the web (Feed and Export still apply).
    var ordering = true
    let reload: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var filteringSheet = false
    @State private var file: ExportFile?
    @State private var failure: String?

    static let dates: [(word: String, title: String, bucket: String)] = [
        ("updated:<24h", "Past 24 Hours", "last_24h"),
        ("updated:<7d", "Past Week", "last_7d"),
        ("updated:<30d", "Past Month", "last_30d"),
        ("updated:<365d", "Past Year", "last_year"),
        ("updated:>365d", "Older", "older"),
    ]

    /// Best Match means nothing for a browse (`*`, a label's pages).
    private var orders: [ResultsModel.Order] {
        AppState.remembers(model.baseQuery) && !model.baseQuery.hasPrefix("label:")
            ? ResultsModel.Order.allCases : ResultsModel.Order.allCases.filter { $0 != .bestMatch }
    }

    private var filtersOn: Bool { ordering && app.searchPage.searchFilters && model.filterable }
    private var filtering: Bool { !model.filters.isEmpty || model.dateRange != nil }

    var body: some View {
        Group {
            // Export and the feed are occasional: File on the Mac,
            // Settings on iOS (`listActions`), not the list's own bar.
            if ordering || filtering {
                scrolling.endsTopBar()
            }
        }
        .listActions(listExport)
        .sheet(isPresented: $filteringSheet) {
            FilterSheet(model: model, dates: Self.dates, reload: reload)
        }
        .fileExporter(
            isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }),
            document: file, contentType: file?.contentType ?? .json, defaultFilename: file?.name
        ) { _ in
            file = nil
        }
        .alert(
            "Couldn't Export",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var scrolling: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if ordering {
                    sortMenu
                    groupMenu
                }
                // A notes list: which of Kura's vaults (All, or one).
                if model.source == .notes, app.kuraVaults.count > 1 {
                    vaultMenu
                }
                // Beside Sort and Group, and looking like them, everywhere:
                // the toolbar is the page's on the Mac and the gear's alone on
                // the iPhone.
                if filtersOn {
                    filterMenu
                        .labelStyle(.titleAndIcon)
                        .quietControl(active: filtering)
                }
                ForEach(model.filters, id: \.self) { word in
                    chip(Self.describe(word)) { change { model.toggleFilter(word) } }
                }
                if let range = model.dateRange {
                    chip(range.lowerBound.formatted(date: .abbreviated, time: .omitted) + " – "
                        + range.upperBound.formatted(date: .abbreviated, time: .omitted)) {
                        change { model.setDateRange(nil) }
                    }
                }
                if !model.filters.isEmpty || model.dateRange != nil {
                    Button("Clear") { change { model.clearFilters() } }
                        .buttonStyle(.borderless)
                        .textStyle(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .fadesOverflow()
    }

    /// The Notes lists' vault filter: every vault (work ones included) or
    /// one.
    private var vaultMenu: some View {
        let chosen = app.kuraVault(app.notesVault)?.title ?? "All Vaults"
        return Menu {
            Picker("Vault", selection: Binding(get: { app.notesVault }, set: { app.notesVault = $0 })) {
                Text("All Vaults").tag("all")
                ForEach(app.kuraVaults) { vault in
                    Text(vault.title).tag(vault.name)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(chosen, systemImage: "archivebox")
        }
        .quietControl(active: app.notesVault != "all")
        .accessibilityLabel("Vault: \(chosen)")
    }

    /// Date, Site, Visits (and Language, Type) as submenus of one icon.
    /// Filter opens a sheet (`FilterSheet`), as Mail's and Photos' filters
    /// do: no submenus, which iOS stacks as cards over the menu.
    private var filterMenu: some View {
        Button {
            filteringSheet = true
        } label: {
            Label(filtering ? "Filtered" : "Filter", systemImage: filtering
                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.borderless)
        .help("Filter")
        .accessibilityLabel(filtering ? "Filter, filters on" : "Filter")
    }

    private func change(_ edit: () -> Void) {
        edit()
        reload()
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: Binding(get: { model.order }, set: { order in change { model.setOrder(order) } })) {
                ForEach(orders) { Text($0.name).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(model.order.name, systemImage: "arrow.up.arrow.down")
        }
        .quietControl()
        .help("Sort")
        .accessibilityLabel("Sort: \(model.order.name)")
    }

    private var groupMenu: some View {
        Menu {
            Picker("Group", selection: Binding(get: { model.grouping }, set: { grouping in change { model.setGrouping(grouping) } })) {
                ForEach(ResultsModel.Grouping.allCases) { Text($0 == .none ? "No Groups" : $0.name).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(model.grouping == .none ? "Group" : model.grouping.name, systemImage: "rectangle.3.group")
        }
        .quietControl(active: model.grouping != .none)
        .help("Group")
        .accessibilityLabel("Group: \(model.grouping.name)")
    }

    private var listExport: ListExport {
        let (app, model, title) = (app, model, title)
        let canExport = app.client != nil
        return ListExport(
            title: title,
            feed: app.feedURL(query: model.query, title: title, source: model.source),
            export: canExport ? { format in Task { await export(format) } } : nil,
            makeFile: canExport ? { format async throws(HisterError) in
                try await Self.file(format, of: model, title: title, app: app)
            } : nil)
    }

    /// The whole query (not only what's loaded) as a file.
    static func file(
        _ format: Export.Format, of model: ResultsModel, title: String, app: AppState
    ) async throws(HisterError) -> ExportFile {
        guard let client = app.client else { throw .unreachable }
        let pages = try await model.allResults(using: client)
        let link = app.feedURL(query: model.query, title: title, source: model.source)
        return ExportFile(
            data: Export.data(pages, as: format, title: title, link: link),
            format: format, name: Export.fileName(title, format: format))
    }

    private func export(_ format: Export.Format) async {
        do {
            file = try await Self.file(format, of: model, title: title, app: app)
        } catch {
            failure = error.userMessage
        }
    }

    private func title(_ name: String, count: Int?) -> String {
        guard let count else { return name }
        return "\(name) (\(count))"
    }

    private func chip(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.accent.opacity(0.35))
        .foregroundStyle(palette.text)
        .accessibilityLabel("\(text), remove filter")
        .help("Remove this filter")
    }

    /// A filter word in words: "Site: github.com", "Not github.com", "Past Week".
    static func describe(_ word: String) -> String {
        if let date = dates.first(where: { $0.word == word }) { return date.title }
        // A collection: its name without the "@".
        if Rules.isCollectionKeyword(word) { return CollectionIcon.title(for: word) }
        let negated = word.hasPrefix("-")
        let body = negated ? String(word.dropFirst()) : word
        guard let colon = body.firstIndex(of: ":") else { return word }
        let field = body[..<colon]
        let value = String(body[body.index(after: colon)...])
        if negated { return "Not \(value)" }
        switch field {
        case "domain", "label": return value
        case "visits": return "Visits: \(value.replacingOccurrences(of: "..", with: "–"))"
        case "language": return "Language: \(value)"
        case "type": return "Type: \(value)"
        default: return word
        }
    }
}

/// Filter: every filter in one sheet, as Mail's and Photos' do, with no
/// submenus. Date (one at a time, or a custom range), then Site, Label,
/// Visits, Language and Type (when there's a choice), each with its count
/// where Hister gives one (not for labels: from the server's rules). A tap
/// applies or removes a filter at once and the list behind follows; Site
/// and Label rows also Hide (a swipe, or the context menu). The search
/// narrows sites and labels, the long lists. Done closes it.
private struct FilterSheet: View {
    let model: ResultsModel
    let dates: [(word: String, title: String, bucket: String)]
    let reload: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var search = ""
    @State private var customRange = false

    private var text: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private func matches(_ name: String) -> Bool { text.isEmpty || name.lowercased().contains(text) }
    private func terms(_ facet: String) -> [Facets.Term] { model.facets?.terms[facet]?.terms ?? [] }
    private var filtering: Bool { !model.filters.isEmpty || model.dateRange != nil }

    private func edit(_ change: () -> Void) {
        change()
        reload()
    }

    var body: some View {
        NavigationStack {
            List {
                #if os(macOS)
                // A plain field on the Mac, as the label picker's: a sheet's
                // .searchable joined the window's toolbar search.
                TextField("Find a Site or Label", text: $search, prompt: Text("Find a Site or Label"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                #endif
                if text.isEmpty { dateSection }
                termSection("Site", facet: "domains", field: "domain", hideable: true)
                labelSection
                if text.isEmpty {
                    termSection("Visits", facet: "visits", field: "visits")
                    if terms("languages").count > 1 { termSection("Language", facet: "languages", field: "language") }
                    if terms("types").count > 1 { termSection("Type", facet: "types", field: "type") }
                }
            }
            .themedBackground()
            .overlay {
                if nothingMatches { ContentUnavailableView.search(text: search) }
            }
            #if os(iOS)
            // No .searchSuggestions(.hidden, for: .content): on iOS 27 it
            // blanked a sheet (CLAUDE.md).
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a Site or Label")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Filter")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if filtering {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") { edit { model.clearFilters() } }
                    }
                }
            }
            .sheet(isPresented: $customRange) {
                DateRangeSheet(initial: model.dateRange) { range in edit { model.setDateRange(range) } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 520)
        #endif
        .presentationDetents([.medium, .large])
    }

    private var dateSection: some View {
        let chosen = model.filters.first { $0.hasPrefix("updated:") }
        return Section("Date") {
            row("Any Time", on: chosen == nil && model.dateRange == nil) {
                edit {
                    model.setFilter(nil, replacing: "updated:")
                    model.setDateRange(nil)
                }
            }
            ForEach(dates, id: \.word) { date in
                row(date.title, count: model.facets?.dates.first { $0.name == date.bucket }?.count, on: chosen == date.word) {
                    edit { model.setFilter(chosen == date.word ? nil : date.word, replacing: "updated:") }
                }
            }
            row(model.dateRange.map { $0.lowerBound.formatted(date: .abbreviated, time: .omitted) + " – " + $0.upperBound.formatted(date: .abbreviated, time: .omitted) } ?? "Custom Range…",
                on: model.dateRange != nil) { customRange = true }
        }
    }

    @ViewBuilder
    private func termSection(_ name: String, facet: String, field: String, hideable: Bool = false) -> some View {
        let shown = terms(facet).filter { matches($0.label ?? $0.term) }
        if shown.isEmpty, text.isEmpty, model.facets == nil, model.phase == .loading {
            // The counts come with the list's first page.
            Section(name) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(palette.secondaryText)
                }
            }
        } else if !shown.isEmpty {
            Section(name) {
                ForEach(shown, id: \.term) { term in
                    let word = "\(field):\(term.term)"
                    row(term.label ?? term.term, count: term.count, on: model.filters.contains(word), hidden: model.filters.contains("-" + word)) {
                        edit { model.toggleFilter(word) }
                    }
                    .modifier(HideAction(enabled: hideable) { edit { model.toggleFilter("-" + word) } })
                }
            }
        }
    }

    /// Collections (their `@` keyword, which Hister expands), then labels.
    /// Not for notes: Kura reads none of Hister's filters.
    @ViewBuilder private var labelSection: some View {
        if model.source != .notes {
            let collections = app.rules.collections.filter { matches(CollectionIcon.title(for: $0.name)) }
            let labels = app.rules.labels.filter(matches)
            if !collections.isEmpty || !labels.isEmpty {
                Section("Label") {
                    ForEach(collections, id: \.name) { collection in
                        row(on: model.filters.contains(collection.name)) {
                            edit { model.toggleFilter(collection.name) }
                        } label: {
                            CollectionLabel(name: collection.name)
                        }
                    }
                    ForEach(labels, id: \.self) { label in
                        let word = "label:\(label)"
                        row(on: model.filters.contains(word), hidden: model.filters.contains("-" + word)) {
                            edit { model.toggleFilter(word) }
                        } label: {
                            LabelChip(label: label)
                        }
                        .modifier(HideAction(enabled: true) { edit { model.toggleFilter("-" + word) } })
                    }
                }
            }
        }
    }

    /// A search that finds no site, and no label where labels are offered.
    private var nothingMatches: Bool {
        guard !text.isEmpty, terms("domains").filter({ matches($0.label ?? $0.term) }).isEmpty else { return false }
        return model.source == .notes
            || app.rules.labels.filter(matches).isEmpty && app.rules.collections.filter({ matches(CollectionIcon.title(for: $0.name)) }).isEmpty
    }

    private func row(_ title: String, count: Int? = nil, on: Bool, hidden: Bool = false, action: @escaping () -> Void) -> some View {
        row(on: on, hidden: hidden, action: action) {
            HStack {
                Text(title)
                Spacer()
                if let count {
                    Text(count.formatted())
                        .foregroundStyle(palette.secondaryText)
                        .monospacedDigit()
                }
            }
        }
    }

    /// A tap applies (or removes) it; a tick says it's on, a struck eye that it's hidden.
    private func row(on: Bool, hidden: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            HStack {
                label()
                if on {
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Applied")
                } else if hidden {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityLabel("Hidden")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Hide for a site or label row: a swipe on iOS, the context menu everywhere.
private struct HideAction: ViewModifier {
    let enabled: Bool
    let hide: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .swipeActions(edge: .trailing) {
                    Button("Hide", systemImage: "eye.slash", action: hide)
                }
                .contextMenu {
                    Button("Hide These Pages", systemImage: "eye.slash", action: hide)
                }
        } else {
            content
        }
    }
}

/// From and to, for a custom date filter.
private struct DateRangeSheet: View {
    let initial: ClosedRange<Date>?
    let apply: (ClosedRange<Date>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var to: Date

    init(initial: ClosedRange<Date>?, apply: @escaping (ClosedRange<Date>) -> Void) {
        self.initial = initial
        self.apply = apply
        let now = Date()
        _from = State(initialValue: initial?.lowerBound ?? Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now)
        _to = State(initialValue: initial?.upperBound ?? now)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
            }
            .navigationTitle("Date Range")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        // Through the end of the "to" day.
                        let start = Calendar.current.startOfDay(for: from)
                        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
                        apply(start...end)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 200)
        #endif
        .presentationDetents([.medium])
    }
}

/// Results you opened before for this search, which Hister ranks first.
struct OpenedSection: View {
    let model: ResultsModel
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.previewSelection) private var selection
    @Environment(\.openURL) private var openURL
    @Environment(\.resultActions) private var actions

    var body: some View {
        if app.searchPage.showOpened, !model.opened.isEmpty {
            Section {
                ForEach(model.opened) { opened in
                    row(opened)
                }
            } header: {
                Text("You Opened")
            }
        }
    }

    /// An opened result as a page; a note by its address, since Hister
    /// sends opened results without their label.
    private func page(_ opened: OpenedResult) -> StoredPage {
        var page = StoredPage(opened: opened)
        if app.isNotePage(page.url) { page.label = Notes.label }
        return page
    }

    @ViewBuilder private func row(_ opened: OpenedResult) -> some View {
        let page = page(opened)
        let note = app.noteLinks(for: page)
        let original = app.searchPage.clickOpensOriginal(pane: selection != nil)
        let label = DocumentRow(document: page, label: app.label(of: page), notePlace: note?.place)
        Group {
            if original {
                // A click opens the original (Click Opens).
                Button {
                    actions.opened(page)
                    openURL.openPage(page, app: app)
                } label: {
                    label.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .tag(page)
            } else if selection != nil {
                label.tag(page)
            } else {
                NavigationLink(value: page) { label }
            }
        }
        .preference(key: ListOrderKey.self, value: selection != nil ? [page] : [])
        .listRowBackground(ResultBar(kind: note != nil ? .note : .opened, selected: selection?.wrappedValue == page,
                                     palette: palette, style: app.searchPage.resultStyle))
        .resultSeparator(app.searchPage.resultStyle)
        .contextMenu {
            OpenChoices(document: page)
            Divider()
            Button("Forget for This Search", systemImage: "eye.slash") { forget(opened) }
            Divider()
            DocumentLinks(document: page, skipOriginal: true)
        }
        .swipeActions(edge: .trailing) {
            Button("Forget", systemImage: "eye.slash") { forget(opened) }
        }
        .accessibilityHint(opened.count > 1 ? "Opened \(opened.count) times for this search" : "Opened before for this search")
    }

    private func forget(_ opened: OpenedResult) {
        let query = model.query
        model.removeOpened(opened.url)
        Task { try? await app.forgetOpened(opened.url, query: query) }
    }
}

extension StoredPage {
    /// An opened result as a page to preview (its text comes with the preview).
    init(opened: OpenedResult) {
        self.init(
            url: opened.url, title: opened.title, domain: opened.domain ?? URL(string: opened.url)?.host() ?? "",
            label: "", added: opened.added ?? .distantPast, updated: opened.updated ?? opened.added ?? .distantPast,
            faviconKey: "", snippetHTML: "")
    }
}

/// Copy a query's feed, or open NewsBlur's subscribe page for it.
struct FeedButtons: View {
    let feed: URL?
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let feed {
            Button("Copy Feed Link", systemImage: "dot.radiowaves.up.forward") { Pasteboard.copy(feed) }
            if let subscribe = Export.newsBlurSubscribeURL(newsBlur: app.searchPage.newsBlurURL, feed: feed) {
                Button("Subscribe in NewsBlur", systemImage: "plus.square.on.square") { openURL(subscribe) }
            }
        }
    }
}

extension AppState {
    /// A list's feed: a notes list's is Kura's own
    /// (`feed.xml`), the Library's All Hister's (`*`, pages and notes),
    /// and every other one the server's feed service without the
    /// notes (`exclude_label=vault`).
    func feedURL(query: String, title: String, source: ResultsModel.Source = .pages) -> URL? {
        if source == .notes { return KuraClient.feedURL(serverURL: searchPage.niwaURL, text: query) }
        guard let client else { return nil }
        if source == .all, query.trimmingCharacters(in: .whitespaces) == "*" { return client.newPagesFeedURL }
        return Export.feedURL(base: client.baseURL, query: query, title: title, excludeLabel: Notes.label)
    }
}

/// An export, for `.fileExporter`.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText, ExportFile.rssType]
    static let rssType = UTType(filenameExtension: "rss") ?? .xml

    var data: Data
    var format: Export.Format
    var name: String

    var contentType: UTType {
        switch format {
        case .json: .json
        case .csv: .commaSeparatedText
        case .rss: Self.rssType
        }
    }

    init(data: Data, format: Export.Format, name: String) {
        self.data = data
        self.format = format
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        format = .json
        name = configuration.file.filename ?? "export.json"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
