import HisterKit
import ShioriAI
import SwiftUI

/// Picks a topic label for one page. Tapping a label applies it and
/// closes the sheet; Cancel leaves the page as it was. Labels are grouped
/// by the server's collections (its aliases), so the picker shows where
/// the page will appear; a label in several collections is under each.
struct LabelPicker: View {
    let document: StoredPage
    let onFailure: (String) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var filter = ""
    @State private var saving = false
    /// Settings → AI's suggestion for this page, at the top.
    @State private var suggestion: LabelSuggestion?
    @State private var suggesting = false
    @State private var suggestionFailure: String?

    var body: some View {
        NavigationStack {
            List {
                let current = app.label(of: document)
                #if os(macOS)
                // A plain field on the Mac: a .searchable in a sheet joined the
                // window's toolbar search, which then read "Filter labels" and
                // showed recent searches in both.
                TextField("Filter labels", text: $filter, prompt: Text("Filter labels"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                #endif
                if filterText.isEmpty, app.ai.hasEngine(note: false) {
                    suggested(current: current)
                }
                Section {
                    row(title: "No Label", value: "", current: current, systemImage: "tag.slash")
                } footer: {
                    Text("Pages you only visited have no label. A label marks a page as kept.")
                }
                if filterText.isEmpty {
                    grouped(current: current)
                } else {
                    matching(current: current)
                }
            }
            .themedBackground()
            .disabled(saving)
            .overlay {
                if app.rules.labels.isEmpty {
                    ProgressView()
                }
            }
            #if os(iOS)
            // No .searchSuggestions(.hidden, for: .content) here: on iOS 27
            // it left the whole sheet blank. The presenting
            // field's recent searches don't show in this one anyway.
            .searchable(text: $filter, prompt: "Filter labels")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            .navigationTitle("Label")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await app.loadRulesIfNeeded()
                await suggest()
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 480)
        #endif
    }

    private var filterText: String {
        filter.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// One section per collection, then the labels in none.
    @ViewBuilder private func grouped(current: String) -> some View {
        ForEach(app.rules.collections, id: \.name) { collection in
            Section {
                ForEach(collection.labels, id: \.self) { label in
                    row(title: label, value: label, current: current, systemImage: nil)
                }
            } header: {
                CollectionLabel(name: collection.name)
            }
        }
        let other = app.rules.ungroupedLabels
        if !other.isEmpty {
            Section(app.rules.collections.isEmpty ? "Labels" : "Other Labels") {
                ForEach(other, id: \.self) { label in
                    row(title: label, value: label, current: current, systemImage: nil)
                }
            }
        }
    }

    /// While filtering: each match once, saying where it leads.
    @ViewBuilder private func matching(current: String) -> some View {
        let matches = app.rules.labels.filter { $0.contains(filterText) }
        Section("Labels") {
            ForEach(matches, id: \.self) { label in
                row(
                    title: label, value: label, current: current, systemImage: nil,
                    collections: app.rules.collections(containing: label))
            }
            if matches.isEmpty, !app.rules.labels.isEmpty {
                Text("No labels match “\(filter)”.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private func row(
        title: String, value: String, current: String, systemImage: String?, collections: [String] = []
    ) -> some View {
        Button {
            Task { await apply(value) }
        } label: {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    LabelChip(label: title)
                }
                if !collections.isEmpty {
                    Text(collections.joined(separator: " · "))
                        .textStyle(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                if value == current {
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Current")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.text)
        .listRowBackground(palette.surface)
        .accessibilityAddTraits(value == current ? .isSelected : [])
        .accessibilityHint(collections.isEmpty ? "" : "In \(collections.joined(separator: ", "))")
    }

    // MARK: Suggested (Settings → AI)

    /// The AI's first choice and runner-up, or a new label when none fits.
    /// A tap applies it like any row: nothing is written until then.
    @ViewBuilder private func suggested(current: String) -> some View {
        Section {
            if suggesting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Suggesting…")
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(palette.surface)
            } else if let suggestion {
                ForEach(suggestion.labels, id: \.self) { label in
                    row(title: label, value: label, current: current, systemImage: nil,
                        collections: app.rules.collections(containing: label))
                }
                if let newLabel = suggestion.newLabel {
                    row(title: "New Label: \(newLabel)", value: newLabel, current: current, systemImage: "plus")
                }
                if suggestion.labels.isEmpty, suggestion.newLabel == nil {
                    Text("Nothing fits well.")
                        .foregroundStyle(palette.secondaryText)
                        .listRowBackground(palette.surface)
                }
            } else if let suggestionFailure {
                Text(suggestionFailure)
                    .foregroundStyle(palette.secondaryText)
                    .listRowBackground(palette.surface)
            }
        } header: {
            Label("Suggested", systemImage: "sparkles")
        } footer: {
            if let suggestion {
                Text(suggestionFooter(suggestion))
            }
        }
    }

    private func suggestionFooter(_ suggestion: LabelSuggestion) -> String {
        var parts = ["By \(suggestion.provider.displayName)"]
        if suggestion.confidence == .low { parts.append("unsure") }
        if suggestion.newLabel != nil { parts.append("a new label joins no collection until you add it to one") }
        return parts.joined(separator: " · ")
    }

    private func suggest() async {
        guard app.ai.hasEngine(note: false), suggestion == nil, let client = app.client else { return }
        // Another vault's note reaches a model only while Kura, asked afresh, still shares it.
        guard !(await app.isWorkNoteNow(document.url)) else { return }
        let excluded = Set(app.ai.neverSuggest)
        let labels = app.rules.labels.filter { !LabelClassifier.notTopics.contains($0) && !excluded.contains($0) }
        guard !labels.isEmpty else { return }
        suggesting = true
        defer { suggesting = false }
        do {
            async let preview = client.preview(of: document.url)
            let hints = await app.labelHintsIfNeeded()
            let rules = app.rules
            let choices = hints.choices(labels, collections: { rules.collections(containing: $0) }, excluding: document.url)
            let page = try await preview
            let title = page.title.isEmpty ? document.displayTitle : page.title
            let similar = await AutoLabeller.neighbours(of: document.url, title: title, labels: Set(labels), client: client)
            suggestion = try await LabelClassifier(chain: app.ai.chain).suggest(
                title: title, url: document.url, html: page.contentHTML, choices: choices,
                siteLabels: hints.siteLabels(for: document.url), neighbours: similar,
                corrections: Array(app.labeller.state.corrections.prefix(10)),
                content: document.label == Notes.label ? .note : .page)
        } catch is CancellationError {
        } catch let error as HisterError {
            if error != .cancelled { suggestionFailure = error.userMessage }
        } catch {
            suggestionFailure = error.localizedDescription
        }
    }

    private func apply(_ label: String) async {
        guard label != app.label(of: document) else {
            dismiss()
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await app.setLabel(label, for: document)
            // Where Shiori had a suggestion, what was chosen teaches it.
            if let suggestion {
                app.labeller.learn(suggested: suggestion.labels.first, chosen: label, title: document.displayTitle, url: document.url)
            }
            dismiss()
        } catch {
            dismiss()
            onFailure(error.userMessage)
        }
    }
}
