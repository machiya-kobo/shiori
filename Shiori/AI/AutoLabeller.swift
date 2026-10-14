import Foundation
import HisterKit
import Observation
import ShioriAI
import ShioriAIOnDevice
import os

private let log = Logger(subsystem: ShioriID.app, category: "ai")

/// Label New Pages (Settings → AI; docs/ai.md). Finds the
/// newest pages with no label, asks Anthropic (its "high" answers are
/// applied), and puts every other page's
/// suggestion, Apple Intelligence's first, in Suggested Labels. Never
/// touches a page that has a label, and stops the moment AI or the switch
/// is turned off.
@MainActor @Observable final class AutoLabeller {
    var state = LabellingState() {
        didSet { refreshWaiting() }
    }
    var running = false
    private(set) var lastRun: Date?
    var lastMessage: String?
    /// Suggestions and collection proposals waiting for the user: what the
    /// sidebar and the Labels tab read, so a run's bookkeeping for every
    /// page doesn't redraw them.
    private(set) var waiting = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var loopID = 0
    /// Whether labelling.json has been read (or found missing). Until then
    /// nothing is written, so an early save can't replace the file with an
    /// empty state; a file that couldn't be read is tried again before the
    /// next run.
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// The account given before the file was read: checked once it is.
    @ObservationIgnored private var owner: (server: String, user: String?)?
    /// Collection edits, one at a time (`CollectionKeeper`): each reads
    /// the alias afresh, so two quick Adds to one collection both land.
    @ObservationIgnored var aliasEditing = false
    @ObservationIgnored var aliasWaiters: [CheckedContinuation<Void, Never>] = []

    /// Pages per run, and cloud requests per day (a cost cap: a cent or so
    /// each on Sonnet 5.5).
    static let perRun = 25
    static let dailyCloudLimit = 200

    init() {
        loading = Task { [weak self] in await self?.load() }
    }

    private func refreshWaiting() {
        let count = state.pending.count + state.collectionProposals.count
        if count != waiting { waiting = count }
    }

    // MARK: Scheduling

    /// On coming to the foreground: a run shortly after (not while the app
    /// is busy starting) once the last run is 15 minutes old, and on the
    /// Mac, which stays open, another every 15 minutes. Coming back while
    /// one is waiting or running changes nothing: the clock isn't reset
    /// and a run under way isn't cut short.
    func start(app: AppState) {
        guard app.ai.enabled, app.ai.autoLabel || app.ai.autoCollections else {
            stop()
            return
        }
        guard loop == nil else { return }
        loopID += 1
        let id = loopID
        let wait = LabellingSchedule.firstWait(after: lastRun)
        // Both weak: held only while a run is under way, never across the sleeps.
        loop = Task { [weak self, weak app] in
            try? await Task.sleep(for: .seconds(wait))
            while !Task.isCancelled {
                if let self, let app { await self.run(app: app) } else { return }
                #if os(macOS)
                try? await Task.sleep(for: .seconds(LabellingSchedule.interval))
                #else
                break
                #endif
            }
            if let self, self.loopID == id { self.loop = nil }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        loopID += 1
    }

    /// Low Power Mode, or a device running hot: the automatic runs wait
    /// (on-device inference is the heaviest work Shiori does). A run the
    /// user asks for still goes.
    static var mayRunUnattended: Bool {
        let info = ProcessInfo.processInfo
        return !info.isLowPowerModeEnabled && info.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }

    // MARK: A run

    func run(app: AppState) async {
        guard !running, app.ai.enabled, app.ai.autoLabel || app.ai.autoCollections else { return }
        guard Self.mayRunUnattended else {
            lastMessage = "Waiting while Low Power Mode is on or the device is warm."
            return
        }
        guard await loadIfNeeded() else { return }
        running = true
        lastMessage = nil
        defer {
            running = false
            lastRun = Date()
            flush()
        }
        if app.ai.autoLabel { await labelNewPages(app: app) }
        // After the labels: a label just applied may be one no collection has.
        await keepCollectionsCurrent(app: app)
    }

    /// Suggest Labels (Settings → AI), whether or not Label New Pages is
    /// on: the newest unlabelled pages not yet looked at are asked about
    /// now, and every answer waits in Suggested Labels, never applied,
    /// since the user asked for suggestions. A page skipped before stays
    /// skipped. Returns what it found.
    func suggestLabels(app: AppState) async -> String {
        guard !running, app.ai.enabled, await loadIfNeeded() else { return "" }
        running = true
        lastMessage = nil
        defer {
            running = false
            flush()
        }
        await labelNewPages(app: app, onDemand: true)
        return lastMessage ?? ""
    }

    private func labelNewPages(app: AppState, onDemand: Bool = false) async {
        guard let client = app.client else { return }
        await app.loadRulesIfNeeded()
        let excluded = Set(app.ai.neverSuggest)
        let labels = app.suggestableLabels
        // Waiting suggestions may be applied there: not on request.
        if !onDemand { await revisitWaiting(app: app, excluded: excluded) }
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
        var applied = 0
        var suggested = 0
        pages: for document in candidates {
            guard app.ai.enabled, onDemand || app.ai.autoLabel, !Task.isCancelled else { break }
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
            // The same question Edit Label asks, so the page goes only where
            // its kind may (`AIContent.classify`, `EngineChain.eligible`).
            guard let question = await app.labelQuestion(
                url: document.url, title: document.displayTitle, label: document.label, isCode: document.code != nil,
                preview: preview, labels: labels, hints: hints, corrections: Array(state.corrections.prefix(10)))
            else {
                state.seen[document.url] = Date()
                continue
            }

            var cloud: LabelSuggestion?
            if let engine = app.ai.cloudEngine, LabelPolicy.trusted.contains(engine.provider), takeCloudRequest() {
                do {
                    cloud = try await question.ask(EngineChain([engine]))
                } catch is CancellationError {
                    break pages
                } catch {
                    log.notice("Cloud label failed: \(error.localizedDescription, privacy: .private)")
                    if LabelFailure(error) == .stop {
                        lastMessage = AIReachability.isTransient(error)
                            ? "\(engine.provider.displayName) didn't answer; the rest wait for the next run."
                            : "\(engine.provider.displayName) couldn't label pages: \(error.localizedDescription)"
                        break pages
                    }
                }
            }
            // Always asked, even when the cloud is sure: free, on the device,
            // and a sure answer Apple disagrees with is the one to review.
            var onDevice: LabelSuggestion?
            if app.ai.appleIntelligence, AppleIntelligenceEngine.status == .available {
                do {
                    onDevice = try await question.ask(EngineChain([AppleIntelligenceEngine()]))
                } catch is CancellationError {
                    break pages
                } catch where AIReachability.isTransient(error) {
                    // Busy for now: this page and the rest wait, not marked done
                    // with no answer of Apple's.
                    lastMessage = "Apple Intelligence is busy; the rest wait for the next run."
                    break pages
                } catch {
                    log.notice("On-device label failed: \(error.localizedDescription, privacy: .private)")
                }
            }

            switch LabelPolicy.decide(
                cloud: cloud, onDevice: onDevice, trust: LabelStat.trust(state.stats), applyOnDevice: app.ai.applyAppleLabels,
                suggestOnly: onDemand
            ) {
            case .apply(let label, let by, let agreed):
                do {
                    try await app.setLabel(label, url: document.url)
                    state.applied.insert(
                        AppliedLabel(
                            url: document.url, title: question.title, label: label, previous: "", by: by, at: Date(), agreed: agreed,
                            appleLabel: onDevice?.labels.first, cloudConfidence: cloud?.confidence.rawValue),
                        at: 0)
                    state.stats[label, default: LabelStat()].applied += 1
                    applied += 1
                } catch {
                    lastMessage = "Hister didn't take a label: \(error.userMessage)"
                    break pages
                }
            case .suggest(let labels, let newLabel):
                state.pending.removeAll { $0.url == document.url }
                state.pending.append(
                    PendingSuggestion(
                        url: document.url, title: question.title, labels: labels, newLabel: newLabel, at: Date(),
                        cloudLabel: cloud?.labels.first, cloudConfidence: cloud?.confidence.rawValue,
                        appleLabel: onDevice?.labels.first))
                suggested += 1
            case .nothing:
                break
            }
            state.seen[document.url] = Date()
            // Written a few seconds after the last page, not after every one.
            save()
        }
        if lastMessage == nil || applied + suggested > 0 {
            lastMessage = onDemand ? "Suggested \(suggested)." : "Labelled \(applied), suggested \(suggested)."
        }
        log.info("Labelling run: \(applied) applied, \(suggested) suggested")
    }

    /// Whether the page has a label now (an edit here, or Hister's own
    /// answer); nil when Hister didn't answer.
    private func labelledMeanwhile(_ url: String, app: AppState) async -> Bool? {
        if let edited = app.labelEdits[url], !edited.isEmpty { return true }
        guard let client = app.client, let preview = try? await client.preview(of: url) else { return nil }
        return !preview.label.isEmpty
    }

    /// A page the user labelled: its waiting suggestion goes.
    func dropWaiting(_ url: String) {
        guard state.pending.contains(where: { $0.url == url }) else { return }
        state.pending.removeAll { $0.url == url }
        flush()
    }

    /// Suggestions already waiting, under today's rules: one where both
    /// engines picked the same label is applied (the agreement rule came
    /// after it was queued); one made before the engines' answers were
    /// stored is put back to be asked again; a never-suggested label comes
    /// off the offer. With Apply Apple Intelligence's Labels on, Apple's
    /// choice for a waiting page is applied (undoable, as any).
    private func revisitWaiting(app: AppState, excluded: Set<String>) async {
        let held = LabelStat.trust(state.stats).held
        for suggestion in state.pending {
            guard app.ai.enabled, app.ai.autoLabel else { return }
            if suggestion.reason.isEmpty {
                state.pending.removeAll { $0.url == suggestion.url }
                state.seen[suggestion.url] = nil
                continue
            }
            let applies = (app.ai.applyAppleLabels && suggestion.appleLabel.map { !excluded.contains($0) && !held.contains($0) } == true)
                || (suggestion.cloudLabel != nil && suggestion.cloudLabel == suggestion.appleLabel
                    && !excluded.contains(suggestion.cloudLabel ?? "") && LabelPolicy.trusted.contains(.anthropic))
            // Before writing, as the first pass does: a page labelled
            // meanwhile (by the user, or another device) keeps its label, and
            // its suggestion goes. Undo would otherwise blank theirs.
            if applies {
                switch await labelledMeanwhile(suggestion.url, app: app) {
                case .none: return  // Hister didn't answer: next run.
                case .some(true):
                    state.pending.removeAll { $0.url == suggestion.url }
                    state.seen[suggestion.url] = Date()
                    continue
                case .some(false): break
                }
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
                state.applied = Array(state.applied.prefix(LabellingState.appliedKept))
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
    }

    /// The newest pages with no label that haven't been dealt with, notes
    /// left out (they carry "vault"), up to a run's worth, from the newest
    /// 300 pages; only the newest 100 once a scan has found the rest dealt
    /// with (`caughtUp`), until a run finds a full run's worth again.
    private func unlabelled(using client: HisterClient, app: AppState) async throws(HisterError) -> [StoredPage] {
        var found: [StoredPage] = []
        var key: String?
        var read = 0
        let limit = state.caughtUp ? 100 : 300
        repeat {
            let page = try await client.search("*", sort: .newest, pageKey: key, limit: 100)
            for document in page.documents
            where document.label.isEmpty && state.seen[document.url] == nil && !app.isNotePage(document.url)
                && !app.isLocalFile(document.url) && found.count < Self.perRun {
                found.append(document)
            }
            read += page.documents.count
            key = page.nextPageKey
        } while key != nil && found.count < Self.perRun && read < limit
        // Fewer than a run's worth in all it reads: there's no backlog behind.
        state.caughtUp = found.count < Self.perRun
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
        flush()
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
        flush()
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
        flush()
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
        flush()
    }

    func undo(_ entry: AppliedLabel, app: AppState) async throws(HisterError) {
        try await app.setLabel(entry.previous, url: entry.url)
        state.applied.removeAll { $0 == entry }
        state.stats[entry.label, default: LabelStat()].undone += 1
        remember(LabelCorrection(title: entry.title, host: URL(string: entry.url)?.host() ?? "", suggested: entry.label, chosen: ""))
        flush()
    }

    // MARK: Storage (this device's Application Support, `LabellingStore`)

    /// Reads labelling.json, off the main thread, once; again before a run
    /// when it couldn't be read. Whether it's ready.
    @discardableResult
    func loadIfNeeded() async -> Bool {
        if !loaded {
            if loading == nil { loading = Task { [weak self] in await self?.load() } }
            await loading?.value
        }
        return loaded
    }

    private func load() async {
        let outcome = await LabellingStore.read()
        loading = nil
        switch outcome {
        case .missing: break
        case .read(let stored): state = stored
        case .unreadable: return
        }
        loaded = true
        if let owner { adopt(server: owner.server, user: owner.user) }
    }

    /// Whose labelling this is: another Hister server, or another user than
    /// the one it was kept for, starts empty (the Undo log, the waiting
    /// suggestions, what was learnt: theirs, not this account's); signed
    /// out, or the same user again, keeps it. Returns whether it started
    /// over.
    @discardableResult
    func adopt(server: String, user: String?) -> Bool {
        let user = user.flatMap { $0.isEmpty ? nil : $0 }
        owner = (server, user)
        guard loaded else { return false }
        let startOver = LabellingOwner.changed(fromServer: state.server, user: state.user, toServer: server, user: user)
        if startOver {
            stop()
            state = LabellingState()
            lastRun = nil
            lastMessage = nil
        }
        if startOver || state.server != server || (user != nil && state.user != user) {
            state.server = server
            if let user { state.user = user }
            flush()
        }
        return startOver
    }

    /// Soon: a run's pages are written a few seconds after the last, not
    /// one by one (each write encoded every page seen).
    func save() {
        guard loaded else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Now: encoded and written off the main thread, in order.
    func flush() {
        guard loaded else { return }
        pendingSave?.cancel()
        pendingSave = nil
        state.trim()
        LabellingStore.write(state)
    }
}
