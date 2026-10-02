import HisterKit
import Observation
import SwiftUI

/// Gemini and Gopher results for Search → Small Web, through a small-web
/// gateway (docs/smallweb.md), a page at a time. Asked only
/// for a submitted search (`SearchSession.liveQuery` leaves this scope out).
@Observable
final class SmallWebModel {
    let query: String
    private(set) var results: [SmallWebResult] = []
    /// The engines that failed ("Veronica-2 timed out"): said, not fatal.
    private(set) var failures: [String] = []
    private(set) var phase: ResultsModel.Phase = .idle
    private(set) var isLoadingMore = false
    private var page = 1
    private var hasMore = false
    private var known = Set<String>()

    init(query: String) {
        self.query = query
    }

    func load(using client: SmallWebClient?) async {
        guard let client else {
            phase = .failed(.unreachable)
            return
        }
        if results.isEmpty { phase = .loading }
        do {
            let first = try await client.search(query, page: 1)
            results = first.results
            known = Set(first.results.map(\.url))
            failures = first.failures
            hasMore = first.hasMore
            page = 1
            phase = .loaded
        } catch .cancelled {
        } catch {
            if results.isEmpty { phase = .failed(error) }
        }
    }

    func loadMoreIfNeeded(after result: SmallWebResult, using client: SmallWebClient?) async {
        guard let client, hasMore, !isLoadingMore,
            let index = results.lastIndex(where: { $0.url == result.url }), index >= results.count - 5
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let next = try? await client.search(query, page: page + 1) else { return }
        page += 1
        let fresh = next.results.filter { known.insert($0.url).inserted }
        hasMore = next.hasMore && !fresh.isEmpty
        results += fresh
    }
}

/// The Small Web results.
struct SmallWebResultsList: View {
    let model: SmallWebModel

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        content
            .task(id: model.query) { await model.load(using: app.smallweb) }
            .refreshable { await model.load(using: app.smallweb) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
        case .failed(let error):
            if app.smallweb == nil {
                ContentUnavailableView {
                    Label("No Small Web Gateway Set", systemImage: "leaf")
                } description: {
                    Text("Add the gateway's address in Settings → Search.")
                }
                .themedBackground()
            } else {
                FailureView(error: error, hasServer: true) {
                    Task { await model.load(using: app.smallweb) }
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
            if !model.failures.isEmpty {
                Text(model.failures.joined(separator: " · "))
                    .textStyle(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .listRowBackground(palette.background)
            }
            ForEach(model.results) { result in
                SmallWebItem(result: result, query: model.query)
                    .task { await model.loadMoreIfNeeded(after: result, using: app.smallweb) }
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

/// One Gemini or Gopher result. A tap opens it where Settings says: the
/// gateway's page, or the gemini:// / gopher:// link itself, for an app
/// such as Lagrange (falling back to the gateway when no app takes it,
/// and asking the gateway to save it to Hister, since it never passes
/// through). The other way is in its menu.
struct SmallWebItem: View {
    let result: SmallWebResult
    let query: String

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    private var direct: Bool { app.searchPage.smallWebOpen == "direct" }

    var body: some View {
        Button {
            open(direct: direct)
        } label: {
            SmallWebRow(result: result)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.background)
        .help(direct ? "Open in a Gemini App" : "Open Through the Gateway")
        .contextMenu {
            Button("Open Through the Gateway", systemImage: "globe") { open(direct: false) }
            Button("Open in a Gemini App", systemImage: "arrow.up.forward.app") { open(direct: true) }
            Divider()
            if let url = URL(string: result.url) {
                Button("Copy Link", systemImage: "link") { Pasteboard.copy(url) }
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
        }
    }

    private func open(direct: Bool) {
        // Hister keeps the canonical address, so that's what's remembered.
        app.recordOpened(url: result.url, title: result.title, query: query)
        let proxy = URL(string: result.proxyURL)
        guard direct, let native = URL(string: result.url) else {
            if let proxy { openURL(proxy) }
            return
        }
        let (openURL, app, canonical) = (openURL, app, result.url)
        // On the Mac the completion comes on LaunchServices' queue, not the
        // main thread (as for Obsidian, `openNote`): hop back.
        openURL(native) { @Sendable accepted in
            Task { @MainActor in
                if accepted {
                    await app.saveSmallWebPage(canonical)
                } else if let proxy {
                    openURL(proxy)
                }
            }
        }
    }
}

/// Title, address, the snippet with the matched words marked, the engines.
struct SmallWebRow: View {
    let result: SmallWebResult
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(result.scheme.capitalized)
                    .textStyle(.caption2, weight: .semibold)
                    .foregroundStyle(palette.tint(SearchScope.smallweb.tint))
                Text(result.place)
                    .textStyle(.caption, design: .monospaced)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(palette.secondaryText)
            Text(result.title)
                .textStyle(.headline)
                .foregroundStyle(palette.accent)
                .lineLimit(2)
            if !result.snippet.isEmpty {
                Text(snippet)
                    .textStyle(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(3)
            }
            Text([result.engineNames, result.size ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .textStyle(.caption2)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var snippet: AttributedString {
        var out = AttributedString()
        for run in result.snippetRuns {
            var part = AttributedString(run.text)
            if run.marked {
                part.foregroundColor = palette.text
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            out += part
        }
        return out
    }
}
