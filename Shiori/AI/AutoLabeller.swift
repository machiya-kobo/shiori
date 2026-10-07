import Foundation
import HisterKit
import Observation
import ShioriAI
import ShioriAIOnDevice
import os

private let log = Logger(subsystem: ShioriID.app, category: "ai")

/// A label suggestion waiting for the user's tap (Suggested Labels).
struct PendingSuggestion: Codable, Identifiable, Equatable {
    var id: String { url }
    let url: String
    let title: String
    let labels: [String]
    let newLabel: String?
    let at: Date
    /// Why it waits for the user, shown under it: what each engine said.
    var cloudLabel: String? = nil
    var cloudConfidence: String? = nil
    var appleLabel: String? = nil

    /// "Anthropic: retro-tech (medium) · Apple Intelligence agrees", so a
    /// single suggestion that wasn't applied says why.
    var reason: String {
        // Made before the reason was kept: nothing true to say.
        guard cloudLabel != nil || cloudConfidence != nil || appleLabel != nil else { return "" }
        var parts: [String] = []
        if let cloudLabel {
            parts.append("Anthropic: \(cloudLabel) (\(cloudConfidence ?? "unsure"))")
        } else if cloudConfidence != nil {
            parts.append("Anthropic: nothing fits")
        } else {
            parts.append("Anthropic not asked")
        }
        if let appleLabel {
            parts.append(appleLabel == cloudLabel ? "Apple Intelligence agrees" : "Apple Intelligence: \(appleLabel)")
        } else {
            parts.append("Apple Intelligence: no answer")
        }
        return parts.joined(separator: " · ")
    }
}

/// A label automatic labelling applied, kept so it can be undone: Hister
/// holds one label and no provenance, so the record lives here.
struct AppliedLabel: Codable, Identifiable, Equatable {
    var id: String { url + String(at.timeIntervalSince1970) }
    let url: String
    let title: String
    let label: String
    let previous: String
    let by: AIProvider
    let at: Date
    /// Applied because Apple Intelligence picked the same label, not on
    /// the cloud's "high" alone.
    var agreed: Bool? = nil
    /// What Apple Intelligence said (nil: no answer, or asked before it
    /// was always asked): a sure cloud answer Apple disagreed with is the
    /// first to review.
    var appleLabel: String? = nil
    var cloudConfidence: String? = nil

    /// For review, first to last: Anthropic sure but Apple disagreed, then
    /// Apple had no answer, then both agreed.
    enum Review: Int, Comparable {
        case disagreed, unchecked, agreed
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    var review: Review {
        if agreed == true || appleLabel == label { return .agreed }
        if let appleLabel, appleLabel != label { return .disagreed }
        return .unchecked
    }
}

/// What automatic labelling remembers between runs, on this device.
struct LabellingState: Codable {
    /// Pages already dealt with (applied, suggested, skipped, declined), so
    /// none is asked about twice.
    var seen: [String: Date] = [:]
    var pending: [PendingSuggestion] = []
    var applied: [AppliedLabel] = []
    /// Cloud requests today, against the daily cap.
    var cloudDay = ""
    var cloudCount = 0
    /// What the user taught it: recent corrections (newest first) and each
    /// label's record, from which `LabelStat.trust` decides what may be
    /// applied unattended.
    var corrections: [LabelCorrection] = []
    var stats: [String: LabelStat] = [:]
    /// Keep Collections Current: what waits for the user, what was changed
    /// (for Undo), and the labels and proposals already dealt with.
    var collectionProposals: [CollectionProposal] = []
    var collectionEdits: [CollectionEdit] = []
    var collectionsSeen: [String: Date] = [:]

    enum CodingKeys: String, CodingKey {
        case seen, pending, applied, cloudDay, cloudCount, corrections, stats, collectionProposals, collectionEdits, collectionsSeen
    }

    init() {}

    /// Older files lack the newer keys: each missing one is empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seen = try c.decodeIfPresent([String: Date].self, forKey: .seen) ?? [:]
        pending = try c.decodeIfPresent([PendingSuggestion].self, forKey: .pending) ?? []
        applied = try c.decodeIfPresent([AppliedLabel].self, forKey: .applied) ?? []
        cloudDay = try c.decodeIfPresent(String.self, forKey: .cloudDay) ?? ""
        cloudCount = try c.decodeIfPresent(Int.self, forKey: .cloudCount) ?? 0
        corrections = try c.decodeIfPresent([LabelCorrection].self, forKey: .corrections) ?? []
        stats = try c.decodeIfPresent([String: LabelStat].self, forKey: .stats) ?? [:]
        collectionProposals = try c.decodeIfPresent([CollectionProposal].self, forKey: .collectionProposals) ?? []
        collectionEdits = try c.decodeIfPresent([CollectionEdit].self, forKey: .collectionEdits) ?? []
        collectionsSeen = try c.decodeIfPresent([String: Date].self, forKey: .collectionsSeen) ?? [:]
    }
}

/// Label New Pages (Settings → AI; docs/ai.md). Finds the
/// newest pages with no label, asks Anthropic (its "high" answers are
/// applied), and puts every other page's
/// suggestion, Apple Intelligence's first, in Suggested Labels. Never
/// touches a page that has a label, and stops the moment AI or the switch
/// is turned off.
@MainActor @Observable final class AutoLabeller {
    var state = LabellingState()
    var running = false
    private(set) var lastRun: Date?
    var lastMessage: String?
    @ObservationIgnored private var loop: Task<Void, Never>?

    /// Pages per run, and cloud requests per day (a cost cap: a cent or so
    /// each on Sonnet 5.5).
    static let perRun = 25
    static let dailyCloudLimit = 200

    init() {
        state = Self.load()
    }

    // MARK: Scheduling

    /// On coming to the foreground: a run shortly after (not while the app
    /// is busy starting), and on the Mac, which stays open, another every
    /// 15 minutes.
    func start(app: AppState) {
        loop?.cancel()
        guard app.ai.enabled, app.ai.autoLabel || app.ai.autoCollections else { return }
        // Both weak: held only while a run is under way, never across the sleeps.
        loop = Task { [weak self, weak app] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                if let self, let app { await self.run(app: app) } else { return }
                #if os(macOS)
                try? await Task.sleep(for: .seconds(15 * 60))
                #else
                break
                #endif
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: A run

    func run(app: AppState) async {
        guard !running, app.ai.enabled, app.ai.autoLabel || app.ai.autoCollections else { return }
        running = true
        lastMessage = nil
        defer {
            running = false
            lastRun = Date()
            save()
        }
        if app.ai.autoLabel { await labelNewPages(app: app) }
        // After the labels: a label just applied may be one no collection has.
        await keepCollectionsCurrent(app: app)
    }

    private func labelNewPages(app: AppState) async {
        guard let client = app.client else { return }
        await app.loadRulesIfNeeded()
        let excluded = Set(app.ai.neverSuggest)
        let labels = app.rules.labels.filter { !LabelClassifier.notTopics.contains($0) && !excluded.contains($0) }
        await revisitWaiting(app: app, excluded: excluded)
        guard !labels.isEmpty else {
            lastMessage = "No labels from Hister yet."
            return
        }
        let candidates: [StoredPage]
        do {
            candidates = try await unlabelled(using: client, app: app)
        } catch {
            lastMessage = "Hister didn't answer."
            return
        }
        guard !candidates.isEmpty else {
            lastMessage = "No new pages to label."
            return
        }
        let hints = await app.labelHintsIfNeeded()
        let rules = app.rules
        var applied = 0
        var suggested = 0
        pages: for document in candidates {
            guard app.ai.enabled, app.ai.autoLabel, !Task.isCancelled else { break }
            let preview: PagePreview
            do {
                preview = try await client.preview(of: document.url)
            } catch {
                lastMessage = "Hister didn't answer."
                break
            }
            // Labelled meanwhile (by the user, or another device): theirs.
            guard preview.label.isEmpty else {
                state.seen[document.url] = Date()
                continue
            }
            let choices = hints.choices(labels, collections: { rules.collections(containing: $0) }, excluding: document.url)
            let site = hints.siteLabels(for: document.url)
            let title = preview.title.isEmpty ? document.displayTitle : preview.title
            let similar = await Self.neighbours(of: document.url, title: title, labels: Set(labels), client: client)
            let learnt = Array(state.corrections.prefix(10))

            var cloud: LabelSuggestion?
            if let engine = app.ai.cloudEngine, LabelPolicy.trusted.contains(engine.provider), takeCloudRequest() {
                do {
                    cloud = try await LabelClassifier(chain: EngineChain([engine])).suggest(
                        title: title, url: document.url, html: preview.contentHTML, choices: choices, siteLabels: site,
                        neighbours: similar, corrections: learnt, content: .page)
                } catch where AIReachability.isTransient(error) {
                    lastMessage = "\(engine.provider.displayName) didn't answer; the rest wait for the next run."
                    break pages
                } catch {
                    log.notice("Cloud label failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            // Always asked, even when the cloud is sure: free, on the device,
            // and a sure answer Apple disagrees with is the one to review.
            var onDevice: LabelSuggestion?
            if app.ai.appleIntelligence, AppleIntelligenceEngine.status == .available {
                onDevice = try? await LabelClassifier(chain: EngineChain([AppleIntelligenceEngine()])).suggest(
                    title: title, url: document.url, html: preview.contentHTML, choices: choices, siteLabels: site,
                    neighbours: similar, corrections: learnt, content: .page)
            }

            switch LabelPolicy.decide(
                cloud: cloud, onDevice: onDevice, trust: LabelStat.trust(state.stats), applyOnDevice: app.ai.applyAppleLabels
            ) {
            case .apply(let label, let by, let agreed):
                do {
                    try await app.setLabel(label, url: document.url)
                    state.applied.insert(
                        AppliedLabel(
                            url: document.url, title: title, label: label, previous: "", by: by, at: Date(), agreed: agreed,
                            appleLabel: onDevice?.labels.first, cloudConfidence: cloud?.confidence.rawValue),
                        at: 0)
                    state.stats[label, default: LabelStat()].applied += 1
                    state.applied = Array(state.applied.prefix(Self.appliedKept))
                    applied += 1
                } catch {
                    lastMessage = "Hister didn't take a label: \(error.userMessage)"
                    break pages
                }
            case .suggest(let labels, let newLabel):
                state.pending.removeAll { $0.url == document.url }
                state.pending.append(
                    PendingSuggestion(
                        url: document.url, title: title, labels: labels, newLabel: newLabel, at: Date(),
                        cloudLabel: cloud?.labels.first, cloudConfidence: cloud?.confidence.rawValue,
                        appleLabel: onDevice?.labels.first))
                suggested += 1
            case .nothing:
                break
            }
            state.seen[document.url] = Date()
            save()
        }
        if lastMessage == nil || applied + suggested > 0 {
            lastMessage = "Labelled \(applied), suggested \(suggested)."
        }
        log.info("Labelling run: \(applied) applied, \(suggested) suggested")
    }

    /// Suggestions already waiting, under today's rules: one where both
    /// engines picked the same label is applied (the agreement rule came
    /// after it was queued); one made before the engines' answers were
    /// stored is put back to be asked again; a never-suggested label comes
    /// off the offer. With Apply Apple Intelligence's Labels on, Apple's
    /// choice for a waiting page is applied (undoable, as any).
    /// How many automatic labels the Undo list keeps: enough for a backlog
    /// of waiting suggestions applied at once (Apply Apple Intelligence's
    /// Labels) to stay undoable.
    static let appliedKept = 1000

    private func revisitWaiting(app: AppState, excluded: Set<String>) async {
        let held = LabelStat.trust(state.stats).held
        for suggestion in state.pending {
            guard app.ai.enabled, app.ai.autoLabel else { return }
            if suggestion.reason.isEmpty {
                state.pending.removeAll { $0.url == suggestion.url }
                state.seen[suggestion.url] = nil
                continue
            }
            if app.ai.applyAppleLabels, let label = suggestion.appleLabel, !excluded.contains(label), !held.contains(label) {
                guard (try? await app.setLabel(label, url: suggestion.url)) != nil else { return }
                state.pending.removeAll { $0.url == suggestion.url }
                state.applied.insert(
                    AppliedLabel(
                        url: suggestion.url, title: suggestion.title, label: label, previous: "", by: .appleIntelligence, at: Date(),
                        agreed: suggestion.cloudLabel == label, appleLabel: label, cloudConfidence: suggestion.cloudConfidence),
                    at: 0)
                state.stats[label, default: LabelStat()].applied += 1
                state.applied = Array(state.applied.prefix(Self.appliedKept))
                continue
            }
            if let label = suggestion.cloudLabel, label == suggestion.appleLabel, !excluded.contains(label),
               LabelPolicy.trusted.contains(.anthropic)
            {
                guard (try? await app.setLabel(label, url: suggestion.url)) != nil else { return }
                state.pending.removeAll { $0.url == suggestion.url }
                state.applied.insert(
                    AppliedLabel(
                        url: suggestion.url, title: suggestion.title, label: label, previous: "", by: .anthropic, at: Date(), agreed: true,
                        appleLabel: suggestion.appleLabel, cloudConfidence: suggestion.cloudConfidence),
                    at: 0)
                state.stats[label, default: LabelStat()].applied += 1
                continue
            }
            let kept = suggestion.labels.filter { !excluded.contains($0) }
            if kept.count != suggestion.labels.count {
                state.pending.removeAll { $0.url == suggestion.url }
                if !kept.isEmpty || suggestion.newLabel != nil {
                    var trimmed = PendingSuggestion(
                        url: suggestion.url, title: suggestion.title, labels: kept, newLabel: suggestion.newLabel, at: suggestion.at)
                    trimmed.cloudLabel = suggestion.cloudLabel
                    trimmed.cloudConfidence = suggestion.cloudConfidence
                    trimmed.appleLabel = suggestion.appleLabel
                    state.pending.append(trimmed)
                }
            }
        }
        save()
    }

    /// The newest pages with no label that haven't been dealt with, notes
    /// left out (they carry "vault"), up to a run's worth, from the newest
    /// 300 pages.
    private func unlabelled(using client: HisterClient, app: AppState) async throws(HisterError) -> [StoredPage] {
        var found: [StoredPage] = []
        var key: String?
        var read = 0
        repeat {
            let page = try await client.search("*", sort: .newest, pageKey: key, limit: 100)
            for document in page.documents
            where document.label.isEmpty && state.seen[document.url] == nil && !app.isNotePage(document.url)
                && !app.isLocalFile(document.url) && found.count < Self.perRun {
                found.append(document)
            }
            read += page.documents.count
            key = page.nextPageKey
        } while key != nil && found.count < Self.perRun && read < 300
        return found
    }

    /// Counts a cloud request against today's cap, or says the cap is reached.
    private func takeCloudRequest() -> Bool { takeCloudRequestShared() }

    func takeCloudRequestShared() -> Bool {
        let today = Date().formatted(.iso8601.year().month().day())
        if state.cloudDay != today {
            state.cloudDay = today
            state.cloudCount = 0
        }
        guard state.cloudCount < Self.dailyCloudLimit else { return false }
        state.cloudCount += 1
        return true
    }

    // MARK: The user's answers

    func accept(_ suggestion: PendingSuggestion, label: String, app: AppState) async throws(HisterError) {
        try await app.setLabel(label, url: suggestion.url)
        state.pending.removeAll { $0.url == suggestion.url }
        learn(suggested: suggestion.labels.first, chosen: label, title: suggestion.title, url: suggestion.url)
        save()
    }

    /// A label the user chose where one was suggested (a tap in Suggested
    /// Labels, Other…, or Edit Label's Suggested section): agreeing counts
    /// for the label, choosing another is a correction the model sees next
    /// time.
    func learn(suggested: String?, chosen: String, title: String, url: String) {
        guard let suggested, !chosen.isEmpty else { return }
        if suggested == chosen {
            state.stats[chosen, default: LabelStat()].accepted += 1
        } else {
            state.stats[suggested, default: LabelStat()].overridden += 1
            remember(LabelCorrection(title: title, host: URL(string: url)?.host() ?? "", suggested: suggested, chosen: chosen))
        }
        save()
    }

    private func remember(_ correction: LabelCorrection) {
        state.corrections.removeAll { $0.title == correction.title && $0.host == correction.host }
        state.corrections.insert(correction, at: 0)
        state.corrections = Array(state.corrections.prefix(50))
    }

    /// Settings → AI's "Forget What It Learnt".
    func forgetLearning() {
        state.corrections = []
        state.stats = [:]
        save()
    }

    /// The user's labelled pages most like this one: a union of its title's
    /// key words in Hister, never the page itself, only labels on offer.
    static func neighbours(of url: String, title: String, labels: Set<String>, client: HisterClient) async -> [LabelNeighbour] {
        guard let terms = NeighbourQuery.terms(from: title),
              let page = try? await client.search(terms, limit: 30)
        else { return [] }
        return page.documents
            .filter { $0.url != url && labels.contains($0.label) && !$0.title.isEmpty }
            .prefix(8)
            .map { LabelNeighbour(title: $0.title, host: URL(string: $0.url)?.host() ?? "", label: $0.label) }
    }

    func skip(_ suggestion: PendingSuggestion) {
        state.pending.removeAll { $0.url == suggestion.url }
        save()
    }

    func undo(_ entry: AppliedLabel, app: AppState) async throws(HisterError) {
        try await app.setLabel(entry.previous, url: entry.url)
        state.applied.removeAll { $0 == entry }
        state.stats[entry.label, default: LabelStat()].undone += 1
        remember(LabelCorrection(title: entry.title, host: URL(string: entry.url)?.host() ?? "", suggested: entry.label, chosen: ""))
        save()
    }

    // MARK: Storage (this device's Application Support)

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "AI", directoryHint: .isDirectory).appending(path: "labelling.json")
    }

    private static func load() -> LabellingState {
        guard let file, let data = try? Data(contentsOf: file) else { return LabellingState() }
        do {
            return try JSONDecoder().decode(LabellingState.self, from: data)
        } catch {
            // Kept aside (the newest such copy) before starting empty, so
            // the next save can't overwrite the Undo log and what was learnt.
            let backup = file.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            let kept = (try? FileManager.default.moveItem(at: file, to: backup)) != nil
            log.error("Labelling state unreadable\(kept ? ", kept as labelling.json.bak" : "", privacy: .public): \(error.localizedDescription, privacy: .public)")
            return LabellingState()
        }
    }

    func save() {
        guard let file = Self.file else { return }
        // Bounded: the oldest "seen" entries go first.
        if state.seen.count > 5_000 {
            state.seen = Dictionary(uniqueKeysWithValues: state.seen.sorted { $0.value > $1.value }.prefix(4_000).map { ($0.key, $0.value) })
        }
        do {
            // This device's own, as the outbox: kept out of backups, and on
            // iOS readable only once the device has been unlocked since boot.
            var folder = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            #if os(iOS)
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            #else
            let options: Data.WritingOptions = [.atomic]
            #endif
            try JSONEncoder().encode(state).write(to: file, options: options)
        } catch {
            log.error("Labelling state not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
