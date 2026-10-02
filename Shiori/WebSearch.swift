import HisterKit
import Observation
import SwiftUI

/// SearXNG results for the app's Search → Web, a page at a time.
@Observable
final class WebResultsModel {
    let query: String
    private(set) var results: [WebResult] = []
    private(set) var suggestions: [String] = []
    private(set) var phase: ResultsModel.Phase = .idle
    private(set) var isLoadingMore = false
    /// What Hister has of these results: URL → label ("" = visited).
    private(set) var saved: [String: String] = [:]
    private var page = 1
    /// Every result URL so far, kept as pages arrive.
    private var known = Set<String>()
    private var exhausted = false

    init(query: String) {
        self.query = query
    }

    func load(searx: SearxClient?, hister: HisterClient?) async {
        guard let searx else {
            phase = .failed(.unreachable)
            return
        }
        if results.isEmpty { phase = .loading }
        do {
            let first = try await searx.search(query, page: 1)
            results = await wikipediaFirst(first.results, searx: searx)
            known = Set(results.map(\.url))
            suggestions = first.suggestions.filter { $0 != query }
            page = 1
            exhausted = first.results.isEmpty
            phase = .loaded
            await mark(first.results, hister: hister)
        } catch .cancelled {
        } catch {
            if results.isEmpty { phase = .failed(error) }
        }
    }

    /// "wiki" as a word in the search: Wikipedia's article first, as on
    /// the web pages (`WikipediaFirst`). The article is the first in the
    /// results in the reader's language, else from the search without
    /// "wiki". Only through SearXNG: the app never calls Wikipedia.
    private func wikipediaFirst(_ results: [WebResult], searx: SearxClient) async -> [WebResult] {
        guard let words = WikipediaFirst.query(query) else { return results }
        let languages = Locale.preferredLanguages
        var article = WikipediaFirst.article(in: results, languages: languages)
        var found: WebResult?
        if article.map({ !WikipediaFirst.inReadersLanguage($0, languages: languages) }) ?? true,
            let other = try? await searx.search(words, page: 1),
            let better = WikipediaFirst.article(in: other.results, languages: languages),
            article == nil || WikipediaFirst.inReadersLanguage(better, languages: languages)
        {
            article = better
            found = other.results[better.index]
        }
        return WikipediaFirst.ordered(results, article: article, found: found)
    }

    func loadMoreIfNeeded(after result: WebResult, searx: SearxClient?, hister: HisterClient?) async {
        guard let searx, !exhausted, !isLoadingMore,
            let index = results.lastIndex(where: { $0.url == result.url }), index >= results.count - 5
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let next = try? await searx.search(query, page: page + 1) else { return }
        page += 1
        let fresh = next.results.filter { known.insert($0.url).inserted }
        exhausted = fresh.isEmpty
        results += fresh
        await mark(fresh, hister: hister)
    }

    private func mark(_ batch: [WebResult], hister: HisterClient?) async {
        guard let hister else { return }
        let labels = await hister.savedLabels(for: batch.map(\.url))
        saved.merge(labels) { _, new in new }
    }
}

/// Web results, a page at a time (rows: `WebItem`).
struct WebResultsList: View {
    let model: WebResultsModel
    let search: (String) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        content
            .task(id: model.query) {
                await model.load(searx: app.searx, hister: app.client)
            }
            .refreshable {
                await model.load(searx: app.searx, hister: app.client)
            }
            .resultActions()
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
        case .failed(let error):
            if app.searx == nil {
                ContentUnavailableView {
                    Label("No Web Search Set", systemImage: "globe")
                } description: {
                    Text("Add your SearXNG server's address in Settings → Search.")
                }
                .themedBackground()
            } else {
                FailureView(error: error, hasServer: true) {
                    Task { await model.load(searx: app.searx, hister: app.client) }
                }
                .themedBackground()
            }
        case .loaded:
            if model.results.isEmpty {
                ContentUnavailableView.search(text: model.query)
                    .themedBackground()
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            // On request only: collapsed until opened.
            if AIAnswerSection.offered(in: app, results: model.results) {
                AIAnswerSection(query: model.query, results: model.results)
            }
            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.suggestions.prefix(6), id: \.self) { suggestion in
                            Button(suggestion) { search(suggestion) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .fadesOverflow()
                .listRowBackground(palette.background)
            }
            ForEach(model.results) { result in
                WebItem(result: result, query: model.query, saved: model.saved[result.url])
                    .task {
                        await model.loadMoreIfNeeded(after: result, searx: app.searx, hister: app.client)
                    }
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

/// One web result: title, where, the snippet with the query's words in
/// bold, a proxied thumbnail, the engines, and whether Hister has it.
struct WebRow: View {
    let result: WebResult
    let query: String
    let saved: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .headline) private var scaledThumb: CGFloat = 64
    @Environment(\.macTextScale) private var macScale
    private var thumb: CGFloat { scaledThumb * macScale }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.host)
                        .textStyle(.caption, design: .monospaced)
                        .lineLimit(1)
                    if let published = result.published {
                        Text("·").accessibilityHidden(true)
                        Text(published, format: .dateTime.year().month(.abbreviated).day())
                            .textStyle(.caption)
                    }
                }
                .foregroundStyle(palette.secondaryText)
                Text(result.title)
                    .textStyle(.headline)
                    .foregroundStyle(palette.accent)
                    .lineLimit(2)
                if !result.content.isEmpty {
                    Text(bolded(result.content))
                        .textStyle(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    if let saved {
                        LabelChip(label: saved.isEmpty ? "visited" : saved)
                    }
                    Text(result.engines.joined(separator: " · "))
                        .textStyle(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let thumbnail = result.thumbnail {
                AsyncImage(url: thumbnail) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        palette.raised
                    }
                }
                .frame(width: thumb, height: thumb)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens in Safari")
    }

    /// Bolded once per result, query and palette, not on every redraw.
    private func bolded(_ text: String) -> AttributedString {
        // The palette follows the colour scheme, so the scheme keys it.
        let key = "\(result.url)\u{1F}\(query)\u{1F}\(scheme)"
        if let cached = Self.boldedCache[key] { return cached }
        let out = makeBolded(text)
        if Self.boldedCache.count > 500 { Self.boldedCache.removeAll() }
        Self.boldedCache[key] = out
        return out
    }

    private static var boldedCache: [String: AttributedString] = [:]

    private func makeBolded(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let terms = query.split(separator: " ").map(String.init)
            .filter { $0.count >= 2 && !$0.contains(":") && !$0.hasPrefix("-") && !$0.hasPrefix("!") }
        for term in terms {
            var searchRange = out.startIndex..<out.endIndex
            while let found = out[searchRange].range(of: term, options: .caseInsensitive) {
                out[found].inlinePresentationIntent = .stronglyEmphasized
                out[found].foregroundColor = palette.text
                searchRange = found.upperBound..<out.endIndex
            }
        }
        return out
    }
}

/// Save a web page to Hister, with an optional label: the share sheet's
/// path (and outbox when Hister is out of reach), from inside the app.
struct SaveSheet: View {
    let input: Saver.Input
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var label = ""
    @State private var outcome: Saver.Outcome?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(input.title ?? input.url.absoluteString)
                            .textStyle(.headline)
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                        Text(input.url.host() ?? input.url.absoluteString)
                            .textStyle(.caption, design: .monospaced)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .listRowBackground(palette.surface)
                Section {
                    Picker("Label", selection: $label) {
                        Text("None").tag("")
                        ForEach(app.rules.labels, id: \.self) { Text($0).tag($0) }
                    }
                } footer: {
                    Text("A label marks the page as kept. Without one it's saved as visited.")
                }
                .listRowBackground(palette.surface)
                if let outcome {
                    Section {
                        Text(outcome.message).foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .formStyle(.grouped)
            .themedBackground()
            .navigationTitle("Save to Hister")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Cancel" : "Done") {
                        // Cancel stops a save in flight; it isn't queued either.
                        saveTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else if outcome == nil {
                        Button("Save") { saveTask = Task { await save() } }
                    }
                }
            }
            .task { await app.loadRulesIfNeeded() }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }

    private func save() async {
        saving = true
        let result = await Saver.save(input, label: label.isEmpty ? nil : label, via: "app")
        saving = false
        guard result != .cancelled else { return }
        outcome = result
        if result == .saved || result == .queued {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }
}
