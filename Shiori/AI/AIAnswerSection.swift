import HisterKit
import ShioriAI
import SwiftUI

/// Answers already made this session, by query: going back to a search, or
/// opening its answer again, asks no engine (the hosted page keeps its own
/// in its Back copy and the server's cache).
@MainActor
enum AnswerCache {
    private static var answers: [String: (answer: SearchAnswer, at: Date)] = [:]

    static func key(_ query: String) -> String {
        query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func read(_ query: String) -> SearchAnswer? {
        guard let entry = answers[key(query)], Date().timeIntervalSince(entry.at) < 24 * 3600 else { return nil }
        return entry.answer
    }

    static func write(_ answer: SearchAnswer, for query: String) {
        answers[key(query)] = (answer, Date())
        if answers.count > 50, let oldest = answers.min(by: { $0.value.at < $1.value.at })?.key {
            answers[oldest] = nil
        }
    }
}

/// "✦ AI Answer" atop a search's web results (All and Web), as on the
/// hosted search page and in the web app, but on this device's own engines
/// (Settings → AI: Apple Intelligence, a local server, then the AI
/// provider). Collapsed, and nothing is asked until it's opened: every
/// answer sends the search and the results' snippets to an engine. Offered
/// with AI on and Results → AI Answer on.
struct AIAnswerSection: View {
    let query: String
    let results: [WebResult]

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var open = false
    @State private var state: SummaryState.Answer = .none
    @State private var asking: Task<Void, Never>?

    private var tinted: some View {
        palette.surface.overlay(palette.tint(SearchScope.all.tint).opacity(0.12))
    }

    /// Whether to offer it at all.
    static func offered(in app: AppState, results: [WebResult]) -> Bool {
        app.ai.hasEngine(note: false) && app.searchPage.aiAnswer && !results.isEmpty
    }

    var body: some View {
        Section {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
                if open { ask(fresh: false) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityHidden(true)
                    // The All pill's cyan: the answer covers the whole search,
                    // as the search page and the web app tint it.
                    Label("AI Answer", systemImage: "sparkles")
                        .textStyle(.subheadline, weight: .semibold)
                        .foregroundStyle(palette.tint(SearchScope.all.tint))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Open" : "Closed")
            .listRowBackground(tinted)
            if open {
                answerBody
                    .listRowBackground(tinted)
            }
        }
    }

    @ViewBuilder private var answerBody: some View {
        switch state {
        case .none, .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Answering…").foregroundStyle(palette.secondaryText)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).foregroundStyle(palette.text)
                Button("Try Again") { ask(fresh: true) }
            }
        case .done(let answer):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(answer.text.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    Text(cited(String(line), sources: answer.sources))
                        .textStyle(.body)
                        .foregroundStyle(palette.text)
                        .textSelection(.enabled)
                }
                let cited = answer.cited
                if !cited.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(cited) { source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    Text("\(source.n). ").foregroundStyle(palette.secondaryText)
                                        + Text(source.title).foregroundStyle(palette.accent)
                                        + Text("  \(url.host() ?? "")").foregroundStyle(palette.secondaryText)
                                }
                                .textStyle(.footnote)
                                .lineLimit(1)
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    Text("By \(answer.provider.displayName) · from the web results’ snippets")
                        .textStyle(.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(answer.text) }
                        .help("Copy the answer")
                    Button("Regenerate", systemImage: "arrow.clockwise") { ask(fresh: true) }
                        .help("Answer again")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
    }

    /// A line with its [n] citations as small links to their sources.
    private func cited(_ line: String, sources: [AnswerSource]) -> AttributedString {
        var out = AttributedString()
        for run in SearchAnswer.runs(line) {
            switch run {
            case .text(let text):
                out += AttributedString(text)
            case .cite(let n):
                guard let source = sources.first(where: { $0.n == n }), let url = URL(string: source.url) else { continue }
                var mark = AttributedString("\u{2009}\(n)")
                mark.link = url
                mark.font = .caption2
                mark.baselineOffset = 5
                mark.foregroundColor = palette.accent
                out += mark
            }
        }
        return out
    }

    private func ask(fresh: Bool) {
        if !fresh, let cached = AnswerCache.read(query) {
            state = .done(cached)
            return
        }
        if case .working = state { return }
        let chain = app.ai.chain
        let query = query
        let results = results.map { (title: $0.title, url: $0.url, snippet: $0.content) }
        asking?.cancel()
        state = .working
        asking = Task {
            do {
                let answer = try await SearchAnswerer(chain: chain).answer(query: query, results: results)
                AnswerCache.write(answer, for: query)
                guard !Task.isCancelled else { return }
                state = .done(answer)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }
}

extension SummaryState {
    /// Where an answer is, as a summary's state.
    enum Answer: Equatable {
        case none
        case working
        case done(SearchAnswer)
        case failed(String)
    }
}
