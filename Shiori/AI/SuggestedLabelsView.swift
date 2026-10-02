import HisterKit
import ShioriAI
import SwiftUI

/// Suggested Labels (Label New Pages, Settings → AI): the pages automatic
/// labelling wasn't sure of, each with its suggestions (a tap applies one),
/// and the labels it applied, each with Undo.
struct SuggestedLabelsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var failure: String?
    @State private var busy: Set<String> = []
    /// Other…: the full label picker for this page.
    @State private var choosing: PendingSuggestion?

    private var labeller: AutoLabeller { app.labeller }

    var body: some View {
        List {
            Section {
                status
            }
            .listRowBackground(palette.surface)

            if app.ai.enabled || !labeller.state.collectionProposals.isEmpty {
                Section {
                    ForEach(labeller.state.collectionProposals) { proposal in
                        collectionRow(proposal)
                    }
                    if app.ai.enabled {
                        SuggestCollectionsButton()
                    }
                } header: {
                    Text("Collections")
                } footer: {
                    Text("A label in no collection doesn't show up under any collection. Adding it puts it in one; only @ collections that are a plain list of labels are changed.")
                }
                .listRowBackground(palette.surface)
            }

            Section {
                if labeller.state.pending.isEmpty {
                    Text("Nothing waiting.")
                        .foregroundStyle(palette.secondaryText)
                }
                ForEach(labeller.state.pending) { suggestion in
                    pendingRow(suggestion)
                }
            } header: {
                Text("Suggested")
            } footer: {
                Text("Tap a label to apply it. Apple Intelligence's suggestion comes first when it has one.")
            }
            .listRowBackground(palette.surface)

            if !labeller.state.applied.isEmpty {
                Section {
                    // The ones worth a second look first: Anthropic was sure
                    // but Apple Intelligence picked something else.
                    ForEach(reviewOrder) { entry in
                        appliedRow(entry)
                    }
                } header: {
                    Text("Labelled Automatically")
                } footer: {
                    Text("Applied when Anthropic was sure, or when it and Apple Intelligence picked the same label. Orange: Apple Intelligence disagreed, worth a look. Green: both agreed. Undo takes a label off again, and Shiori learns from it.")
                }
                .listRowBackground(palette.surface)
            }

            if !labeller.state.collectionEdits.isEmpty {
                Section {
                    ForEach(labeller.state.collectionEdits.prefix(50)) { edit in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(edit.summary)
                                    .foregroundStyle(palette.text)
                                Text("\(edit.automatic ? "Automatically" : "By you") · \(edit.at.formatted(.relative(presentation: .named)))")
                                    .textStyle(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            Spacer()
                            Button("Undo") {
                                Task {
                                    do { try await labeller.undoCollection(edit, app: app) } catch { failure = Self.message(error) }
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Collections Changed")
                }
                .listRowBackground(palette.surface)
            }
        }
        .themedBackground()
        .navigationTitle("Suggested Labels")
        .sheet(item: $choosing, onDismiss: pickerClosed) { suggestion in
            LabelPicker(document: Self.page(suggestion)) { failure = $0 }
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

    @ViewBuilder private var status: some View {
        if !app.ai.enabled || !(app.ai.autoLabel || app.ai.autoCollections) {
            Text("Label New Pages and Keep Collections Current are off. Turn them on in Settings → AI.")
                .foregroundStyle(palette.secondaryText)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(labeller.running ? "Labelling…" : (labeller.lastMessage ?? "Waiting for the first run."))
                    if let last = labeller.lastRun {
                        Text("Last run \(last.formatted(.relative(presentation: .named)))")
                            .textStyle(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                Spacer()
                if labeller.running {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run Now") { Task { await labeller.run(app: app) } }
                }
            }
        }
    }

    private func pendingRow(_ suggestion: PendingSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let url = URL(string: suggestion.url) { openURL(url) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title.isEmpty ? suggestion.url : suggestion.title)
                        .foregroundStyle(palette.accent)
                        .lineLimit(2)
                    Text(URL(string: suggestion.url)?.host() ?? suggestion.url)
                        .textStyle(.caption, design: .monospaced)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                ForEach(suggestion.labels, id: \.self) { label in
                    Button { accept(suggestion, label) } label: { LabelChip(label: label) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Apply \(label)")
                }
                if let newLabel = suggestion.newLabel {
                    Button { accept(suggestion, newLabel) } label: { LabelChip(label: "+ \(newLabel)") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Apply the new label \(newLabel)")
                }
                Spacer()
                Button("Other…") { choosing = suggestion }
                    .buttonStyle(.borderless)
                    .help("Choose any label")
                Button("Skip") { labeller.skip(suggestion) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(palette.secondaryText)
            }
            .disabled(busy.contains(suggestion.url))
            if !suggestion.reason.isEmpty {
                Text(suggestion.reason)
                    .textStyle(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }

    /// The picker works on a page; this is enough of one (it reads the
    /// address, the title and the current label, which is none).
    private static func page(_ suggestion: PendingSuggestion) -> StoredPage {
        StoredPage(
            url: suggestion.url, title: suggestion.title, domain: URL(string: suggestion.url)?.host() ?? "", label: "",
            added: suggestion.at, updated: suggestion.at, faviconKey: "", snippetHTML: "")
    }

    /// A label chosen in the picker takes the page off the list, and
    /// teaches Shiori (the suggestion was passed over for it).
    private func pickerClosed() {
        for suggestion in labeller.state.pending {
            guard let chosen = app.labelEdits[suggestion.url] else { continue }
            labeller.learn(suggested: suggestion.labels.first, chosen: chosen, title: suggestion.title, url: suggestion.url)
            labeller.skip(suggestion)
        }
    }

    private var reviewOrder: [AppliedLabel] {
        Array(labeller.state.applied.prefix(100))
            .sorted { $0.review != $1.review ? $0.review < $1.review : $0.at > $1.at }
    }

    private func collectionRow(_ proposal: CollectionProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CollectionLabel(name: proposal.keyword)
                    .foregroundStyle(palette.text)
                Text(proposal.kind == .add ? "add \(proposal.labels[0])" : "new: \(proposal.labels.joined(separator: ", "))")
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                Spacer()
                Button(proposal.kind == .add ? "Add" : "Create") {
                    Task {
                        busy.insert(proposal.id)
                        defer { busy.remove(proposal.id) }
                        do { try await labeller.acceptCollection(proposal, app: app) } catch { failure = Self.message(error) }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(busy.contains(proposal.id))
                Button("Not Now") { labeller.declineCollection(proposal) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(palette.secondaryText)
            }
            Text(proposal.reason)
                .textStyle(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.vertical, 2)
    }

    private func appliedRow(_ entry: AppliedLabel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: reviewSymbol(entry.review))
                .foregroundStyle(reviewColour(entry.review))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? entry.url : entry.title)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    LabelChip(label: entry.label)
                    Text("\(reviewText(entry)) · \(entry.at.formatted(.relative(presentation: .named)))")
                        .textStyle(.caption)
                        .foregroundStyle(entry.review == .disagreed ? reviewColour(.disagreed) : palette.secondaryText)
                }
            }
            Spacer()
            Button("Undo") {
                Task {
                    busy.insert(entry.url)
                    defer { busy.remove(entry.url) }
                    do { try await labeller.undo(entry, app: app) } catch { failure = Self.message(error) }
                }
            }
            .buttonStyle(.borderless)
            .disabled(busy.contains(entry.url))
        }
    }

    private func reviewSymbol(_ review: AppliedLabel.Review) -> String {
        switch review {
        case .disagreed: "exclamationmark.triangle.fill"
        case .unchecked: "questionmark.circle"
        case .agreed: "checkmark.circle.fill"
        }
    }

    private func reviewColour(_ review: AppliedLabel.Review) -> Color {
        switch review {
        case .disagreed: .orange
        case .unchecked: palette.secondaryText
        case .agreed: .green
        }
    }

    private func reviewText(_ entry: AppliedLabel) -> String {
        switch entry.review {
        case .disagreed: "Anthropic sure; Apple Intelligence said \(entry.appleLabel ?? "")"
        case .unchecked: "Anthropic sure; Apple Intelligence not asked"
        case .agreed: "Anthropic and Apple Intelligence agreed"
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? HisterError)?.userMessage ?? error.localizedDescription
    }

    private func accept(_ suggestion: PendingSuggestion, _ label: String) {
        Task {
            busy.insert(suggestion.url)
            defer { busy.remove(suggestion.url) }
            do { try await labeller.accept(suggestion, label: label, app: app) } catch { failure = Self.message(error) }
        }
    }
}

/// Suggest Collections, on demand (docs/ai.md): works
/// whether or not Keep Collections Current is on, and only ever asks.
struct SuggestCollectionsButton: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var result: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Button("Suggest Collections") {
                    Task { result = await app.labeller.suggestCollections(app: app) }
                }
                .disabled(!app.ai.enabled || app.labeller.running)
                if let result, !result.isEmpty {
                    Text(result)
                        .textStyle(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer()
            if app.labeller.running {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// A row that leads to Suggested Labels, with the number waiting. It
/// takes its colours from where it sits: the sidebar's own on the Mac and
/// iPad, like the rows around it; the Labels tab sets the theme's.
struct SuggestedLabelsRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            HStack {
                Text("Suggested Labels")
                Spacer()
                let count = app.labeller.state.pending.count + app.labeller.state.collectionProposals.count
                if count > 0 {
                    Text(count.formatted())
                        .textStyle(.caption, weight: .semibold)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        } icon: {
            RowIcon(symbol: "sparkles")
        }
    }
}
