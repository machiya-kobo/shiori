import Foundation
import HisterKit
import ShioriAI
import ShioriAIOnDevice
import os

private let log = Logger(subsystem: ShioriID.app, category: "ai")

/// A collection change waiting for the user (Suggested Labels → Collections).
struct CollectionProposal: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case add, create }
    var id: String { kind == .add ? "add:\(labels.first ?? ""):\(keyword)" : "create:\(keyword)" }
    let kind: Kind
    let keyword: String
    /// `.add`: the one label; `.create`: the new collection's labels.
    let labels: [String]
    let reason: String
    let at: Date
}

/// A collection change made (by the user's tap or automatically), kept so
/// it can be undone: `previous` nil means the collection was new.
struct CollectionEdit: Codable, Identifiable, Equatable {
    var id: String { keyword + String(at.timeIntervalSince1970) }
    let keyword: String
    let previous: String?
    let value: String
    let summary: String
    let automatic: Bool
    let at: Date
}

/// Keep Collections Current (Settings → AI; docs/ai.md).
/// Collections are Hister's aliases, edited through Hister's own endpoint,
/// and only under the server's alias rules: `@`-keywords only (a plain
/// alias is the user's own), never a reserved or existing name, only
/// values that are purely a label list.
extension AutoLabeller {
    /// Labels in no collection get one: automatically when Anthropic is sure
    /// or it and Apple Intelligence agree, otherwise asked; loose labels
    /// that share a theme get a proposed new collection (always asked).
    func keepCollectionsCurrent(app: AppState) async {
        guard app.ai.enabled, app.ai.autoCollections else { return }
        _ = await planCollections(app: app, onDemand: false)
    }

    /// Suggest Collections (Settings → AI, Suggested Labels), whether or not
    /// Keep Collections Current is on: every label in no collection is
    /// considered again, even one asked about before, and everything is
    /// asked, never applied, since the user asked for suggestions. A new
    /// collection declined before stays declined. Returns what it found.
    func suggestCollections(app: AppState) async -> String {
        guard !running, app.ai.enabled else { return "" }
        running = true
        defer {
            running = false
            save()
        }
        let message = await planCollections(app: app, onDemand: true)
        lastMessage = message
        return message
    }

    private func planCollections(app: AppState, onDemand: Bool) async -> String {
        guard let client = app.client else { return "Hister didn't answer." }
        await app.reloadRules()
        let editable = Self.editableCollections(app.rules)
        guard !editable.isEmpty else { return "There are no collections Shiori can change." }
        let hints = await app.labelHintsIfNeeded()
        let grouped = Set(editable.flatMap(\.labels))
        let excluded = Set(app.ai.neverSuggest).union(LabelClassifier.notTopics)
        let waiting = Set(state.collectionProposals.flatMap(\.labels))
        var inUse: [String] = []
        for label in hints.pages.map(\.label) + state.applied.map(\.label) where !inUse.contains(label) { inUse.append(label) }
        let loose = inUse.filter {
            !grouped.contains($0) && !excluded.contains($0) && !waiting.contains($0)
                && (onDemand || state.collectionsSeen["label:\($0)"] == nil)
        }
        guard !loose.isEmpty else {
            return waiting.isEmpty ? "Every label is in a collection." : "Nothing new: the suggestions below are still waiting."
        }
        let before = state.collectionProposals.count
        var added = 0

        let cloudEngine = app.ai.cloudEngine.flatMap { LabelPolicy.trusted.contains($0.provider) ? $0 : nil }
        let apple = app.ai.appleIntelligence && AppleIntelligenceEngine.status == .available ? AppleIntelligenceEngine() : nil
        var unplaced: [LooseLabel] = []
        for name in loose.prefix(10) {
            guard app.ai.enabled, onDemand || app.ai.autoCollections, !Task.isCancelled else { break }
            let label = LooseLabel(name: name, examples: Array(hints.pages.filter { $0.label == name }.prefix(3).map(\.title)))
            var onDevice: CollectionPlacement?
            if let apple { onDevice = try? await CollectionPlanner(chain: EngineChain([apple])).place(label, among: editable) }
            var cloud: CollectionPlacement?
            if let cloudEngine, takeCloudRequestForCollections() {
                cloud = try? await CollectionPlanner(chain: EngineChain([cloudEngine])).place(label, among: editable)
            }
            state.collectionsSeen["label:\(name)"] = Date()
            if !onDemand, let keyword = CollectionPolicy.autoPlace(cloud: cloud, onDevice: onDevice) {
                do {
                    try await add(name, to: keyword, automatic: true, app: app, client: client)
                    added += 1
                } catch {
                    log.notice("Collection edit failed: \(error.localizedDescription, privacy: .public)")
                }
            } else if let keyword = CollectionPolicy.ask(cloud: cloud, onDevice: onDevice) {
                state.collectionProposals.append(
                    CollectionProposal(kind: .add, keyword: keyword, labels: [name], reason: Self.reason(cloud: cloud, onDevice: onDevice), at: Date()))
            } else {
                unplaced.append(label)
            }
        }
        if unplaced.count >= 2 {
            // Apple Intelligence first, the cloud if it can't answer: the
            // user's order (never automatic, so no need of the cloud's word).
            let existing = app.rules.aliases.keys.sorted()
            if let proposals = try? await CollectionPlanner(chain: app.ai.chain).propose(for: unplaced, existing: existing) {
                for proposal in proposals where state.collectionsSeen["create:\(proposal.keyword)"] == nil
                    && !state.collectionProposals.contains(where: { $0.kind == .create && $0.keyword == proposal.keyword })
                {
                    state.collectionProposals.append(
                        CollectionProposal(kind: .create, keyword: proposal.keyword, labels: proposal.labels, reason: "Labels in no collection that share a theme", at: Date()))
                }
            }
        }
        save()
        return Self.outcome(asked: state.collectionProposals.count - before, added: added, left: unplaced.count)
    }

    static func outcome(asked: Int, added: Int, left: Int) -> String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) \(added == 1 ? "label" : "labels") added to collections") }
        if asked > 0 { parts.append("\(asked) \(asked == 1 ? "suggestion" : "suggestions") waiting") }
        if parts.isEmpty {
            return left > 0 ? "No collection fits the \(left) loose \(left == 1 ? "label" : "labels"), and none share a theme." : "Nothing to suggest."
        }
        return parts.joined(separator: ", ") + "."
    }

    /// The collections Shiori may edit: `@`-keywords whose value is purely a
    /// label list.
    static func editableCollections(_ rules: Rules) -> [CollectionInfo] {
        rules.aliases.compactMap { keyword, value in
            guard keyword.hasPrefix("@"), let labels = AliasValue.labels(in: value) else { return nil }
            return CollectionInfo(keyword: keyword, labels: labels)
        }
        .sorted { $0.keyword < $1.keyword }
    }

    private static func reason(cloud: CollectionPlacement?, onDevice: CollectionPlacement?) -> String {
        let apple = onDevice?.keyword.map { "Apple Intelligence: \(CollectionIcon.title(for: $0))" } ?? "Apple Intelligence: no answer"
        let anthropic = cloud.map { placement in
            placement.keyword.map { "Anthropic: \(CollectionIcon.title(for: $0)) (\(placement.confidence.rawValue))" } ?? "Anthropic: none fits"
        } ?? "Anthropic not asked"
        return "\(apple) · \(anthropic)"
    }

    private func takeCloudRequestForCollections() -> Bool { takeCloudRequestShared() }

    // MARK: Changes

    /// Adds a label to a collection, from the collection's current value
    /// (read fresh), and records it for Undo.
    func add(_ label: String, to keyword: String, automatic: Bool, app: AppState, client: HisterClient) async throws(HisterError) {
        let rules = try await client.rules()
        guard keyword.hasPrefix("@"), let current = rules.aliases[keyword], let value = AliasValue.adding(label, to: current) else {
            throw .invalidQuery("\(CollectionIcon.title(for: keyword)) isn't a collection Shiori can change.")
        }
        try await client.setAlias(keyword, value: value)
        state.collectionEdits.insert(
            CollectionEdit(keyword: keyword, previous: current, value: value, summary: "\(label) added to \(CollectionIcon.title(for: keyword))",
                           automatic: automatic, at: Date()), at: 0)
        state.collectionEdits = Array(state.collectionEdits.prefix(100))
        await app.reloadRules()
        save()
    }

    func acceptCollection(_ proposal: CollectionProposal, app: AppState) async throws(HisterError) {
        guard let client = app.client else { throw .unreachable }
        switch proposal.kind {
        case .add:
            try await add(proposal.labels[0], to: proposal.keyword, automatic: false, app: app, client: client)
        case .create:
            let rules = try await client.rules()
            let bare = String(proposal.keyword.dropFirst())
            guard proposal.keyword.hasPrefix("@"), rules.aliases[proposal.keyword] == nil, rules.aliases[bare] == nil,
                !CollectionPlanner.reserved.contains(bare) else {
                throw .invalidQuery("\(CollectionIcon.title(for: proposal.keyword)) already exists.")
            }
            let value = AliasValue.value(for: proposal.labels)
            try await client.setAlias(proposal.keyword, value: value)
            state.collectionEdits.insert(
                CollectionEdit(keyword: proposal.keyword, previous: nil, value: value,
                               summary: "New collection \(CollectionIcon.title(for: proposal.keyword)): \(proposal.labels.joined(separator: ", "))",
                               automatic: false, at: Date()), at: 0)
            await app.reloadRules()
        }
        state.collectionProposals.removeAll { $0.id == proposal.id }
        save()
    }

    func declineCollection(_ proposal: CollectionProposal) {
        state.collectionProposals.removeAll { $0.id == proposal.id }
        state.collectionsSeen[proposal.id] = Date()
        if proposal.kind == .create { state.collectionsSeen["create:\(proposal.keyword)"] = Date() }
        save()
    }

    /// Puts the collection back as it was; a new one is removed (read
    /// first: Hister answers 500 for a keyword it doesn't have).
    func undoCollection(_ edit: CollectionEdit, app: AppState) async throws(HisterError) {
        guard let client = app.client else { throw .unreachable }
        if let previous = edit.previous {
            try await client.setAlias(edit.keyword, value: previous)
        } else if try await client.rules().aliases[edit.keyword] != nil {
            try await client.deleteAlias(edit.keyword)
        }
        state.collectionEdits.removeAll { $0 == edit }
        await app.reloadRules()
        save()
    }
}
