import Foundation
import HisterKit
import ShioriAI
import ShioriAIOnDevice
import os

private let log = Logger(subsystem: ShioriID.app, category: "ai")

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
            flush()
        }
        guard await loadIfNeeded() else { return "" }
        let message = await planCollections(app: app, onDemand: true)
        lastMessage = message
        return message
    }

    private func planCollections(app: AppState, onDemand: Bool) async -> String {
        guard let client = app.client else { return "Hister didn't answer." }
        // Asked for: the rules as they are now. Automatic: the copy from
        // coming to the foreground (each edit reads them afresh anyway).
        if onDemand { await app.reloadRules() } else { await app.loadRulesIfNeeded() }
        let editable = Self.editableCollections(app.rules)
        guard !editable.isEmpty else { return "There are no collections Shiori can change." }
        // Unattended, hints up to six hours old do to find loose labels
        // (ten requests each time they're read again).
        let hints = await app.labelHintsIfNeeded(maxAge: onDemand ? 30 * 60 : 6 * 3600)
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
        var stopped: String?
        labels: for name in loose.prefix(10) {
            guard app.ai.enabled, onDemand || app.ai.autoCollections, !Task.isCancelled else { break }
            let label = LooseLabel(name: name, examples: Array(hints.pages.filter { $0.label == name }.prefix(3).map(\.title)))
            // An engine that couldn't answer (busy, offline, a refused key)
            // leaves this label and the rest for later, not marked as asked
            // with "No collection fits".
            var onDevice: CollectionPlacement?
            if let apple {
                do {
                    onDevice = try await CollectionPlanner(chain: EngineChain([apple])).place(label, among: editable)
                } catch where AIReachability.isTransient(error) || error is CancellationError {
                    stopped = "Apple Intelligence is busy; the rest wait for the next run."
                    break labels
                } catch {
                    log.notice("On-device placement failed: \(error.localizedDescription, privacy: .private)")
                }
            }
            var cloud: CollectionPlacement?
            if let cloudEngine, takeCloudRequestForCollections() {
                do {
                    cloud = try await CollectionPlanner(chain: EngineChain([cloudEngine])).place(label, among: editable)
                } catch {
                    log.notice("Cloud placement failed: \(error.localizedDescription, privacy: .private)")
                    if error is CancellationError || LabelFailure(error) == .stop {
                        stopped = "\(cloudEngine.provider.displayName) didn't answer; the rest wait for the next run."
                        break labels
                    }
                }
            }
            state.collectionsSeen["label:\(name)"] = Date()
            if !onDemand, let keyword = CollectionPolicy.autoPlace(cloud: cloud, onDevice: onDevice) {
                do {
                    try await add(name, to: keyword, automatic: true, app: app, client: client)
                    added += 1
                } catch {
                    log.notice("Collection edit failed: \(error.localizedDescription, privacy: .private)")
                }
            } else if let keyword = CollectionPolicy.ask(cloud: cloud, onDevice: onDevice) {
                state.collectionProposals.append(
                    CollectionProposal(kind: .add, keyword: keyword, labels: [name], reason: Self.reason(cloud: cloud, onDevice: onDevice), at: Date()))
            } else {
                unplaced.append(label)
            }
        }
        if unplaced.count >= 2, stopped == nil {
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
        let asked = state.collectionProposals.count - before
        let outcome = Self.outcome(asked: asked, added: added, left: unplaced.count)
        guard let stopped else { return outcome }
        return added + asked > 0 ? outcome + " " + stopped : stopped
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

    /// One alias edit at a time: each reads the collection's value afresh
    /// and writes it whole, so two at once (two quick Adds to one
    /// collection) would have kept only the second.
    private func lockAliases() async {
        if aliasEditing {
            await withCheckedContinuation { aliasWaiters.append($0) }
        }
        aliasEditing = true
    }

    /// The next waiting edit goes on holding the lock.
    private func unlockAliases() {
        if aliasWaiters.isEmpty {
            aliasEditing = false
        } else {
            aliasWaiters.removeFirst().resume()
        }
    }

    /// Adds a label to a collection, from the collection's current value
    /// (read fresh), and records it for Undo.
    func add(_ label: String, to keyword: String, automatic: Bool, app: AppState, client: HisterClient) async throws(HisterError) {
        await lockAliases()
        defer { unlockAliases() }
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
        flush()
    }

    func acceptCollection(_ proposal: CollectionProposal, app: AppState) async throws(HisterError) {
        guard let client = app.client else { throw .unreachable }
        switch proposal.kind {
        case .add:
            try await add(proposal.labels[0], to: proposal.keyword, automatic: false, app: app, client: client)
        case .create:
            await lockAliases()
            defer { unlockAliases() }
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
        flush()
    }

    func declineCollection(_ proposal: CollectionProposal) {
        state.collectionProposals.removeAll { $0.id == proposal.id }
        state.collectionsSeen[proposal.id] = Date()
        if proposal.kind == .create { state.collectionsSeen["create:\(proposal.keyword)"] = Date() }
        flush()
    }

    /// Takes the edit back out of the collection as it is now (read first):
    /// unchanged since, it goes back to its value before; changed since
    /// (another label added after), only this edit's labels come out; a new
    /// collection is removed (Hister answers 500 for a keyword it doesn't
    /// have, so only when it's there).
    func undoCollection(_ edit: CollectionEdit, app: AppState) async throws(HisterError) {
        guard let client = app.client else { throw .unreachable }
        await lockAliases()
        defer { unlockAliases() }
        let current = try await client.rules().aliases[edit.keyword]
        if let previous = edit.previous {
            switch AliasUndo(edit, previous: previous, current: current) {
            case .write(let value): try await client.setAlias(edit.keyword, value: value)
            case .nothing: break
            case .cannot: throw .invalidQuery("\(CollectionIcon.title(for: edit.keyword)) has changed since; edit it in Hister.")
            }
        } else if current != nil {
            try await client.deleteAlias(edit.keyword)
        }
        state.collectionEdits.removeAll { $0 == edit }
        await app.reloadRules()
        flush()
    }
}
