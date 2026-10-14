import Foundation
import ShioriAI
import os

// What Label New Pages and Keep Collections Current keep between runs, and
// the rules they run by: here, with no view or AppState, so the tests
// reach them (`AutoLabeller` and `CollectionKeeper` hold the rest).

/// A label suggestion waiting for the user's tap (Suggested Labels).
nonisolated struct PendingSuggestion: Codable, Identifiable, Equatable, Sendable {
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
nonisolated struct AppliedLabel: Codable, Identifiable, Equatable, Sendable {
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
nonisolated struct LabellingState: Codable, Sendable {
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
    /// Whose this is: the Hister server, and the user signed in there when
    /// there was one. Another server or another user starts empty
    /// (`AutoLabeller.adopt`); signing out and back in as the same keeps it.
    var server: String?
    var user: String?
    /// The last scan for unlabelled pages reached the end of what it reads
    /// with fewer than a run's worth: the next one reads the newest page of
    /// results only (one request, not three, when there's nothing to do).
    var caughtUp = false

    enum CodingKeys: String, CodingKey {
        case seen, pending, applied, cloudDay, cloudCount, corrections, stats, collectionProposals, collectionEdits, collectionsSeen
        case server, user, caughtUp
    }

    init() {}

    /// Older files lack the newer keys: each missing one is empty. One
    /// entry that doesn't read (a newer build's, after a downgrade) is
    /// skipped, never the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list<T: Decodable>(_ key: CodingKeys) -> [T] {
            (try? c.decodeIfPresent([Lossy<T>].self, forKey: key))?.compactMap(\.value) ?? []
        }
        func table<T: Decodable>(_ key: CodingKeys) -> [String: T] {
            (try? c.decodeIfPresent([String: Lossy<T>].self, forKey: key))?.compactMapValues(\.value) ?? [:]
        }
        seen = table(.seen)
        pending = list(.pending)
        applied = list(.applied)
        cloudDay = (try? c.decodeIfPresent(String.self, forKey: .cloudDay)) ?? ""
        cloudCount = (try? c.decodeIfPresent(Int.self, forKey: .cloudCount)) ?? 0
        corrections = list(.corrections)
        stats = table(.stats)
        collectionProposals = list(.collectionProposals)
        collectionEdits = list(.collectionEdits)
        collectionsSeen = table(.collectionsSeen)
        server = try? c.decodeIfPresent(String.self, forKey: .server)
        user = try? c.decodeIfPresent(String.self, forKey: .user)
        caughtUp = (try? c.decodeIfPresent(Bool.self, forKey: .caughtUp)) ?? false
    }

    /// How many automatic labels the Undo list keeps: enough for a backlog
    /// of waiting suggestions applied at once (Apply Apple Intelligence's
    /// Labels) to stay undoable.
    static let appliedKept = 1000

    /// Every list bounded, the oldest going first.
    mutating func trim() {
        if seen.count > 5_000 {
            seen = Dictionary(uniqueKeysWithValues: seen.sorted { $0.value > $1.value }.prefix(4_000).map { ($0.key, $0.value) })
        }
        if pending.count > 500 { pending = Array(pending.sorted { $0.at > $1.at }.prefix(500)) }
        if applied.count > Self.appliedKept { applied = Array(applied.prefix(Self.appliedKept)) }
        if corrections.count > 50 { corrections = Array(corrections.prefix(50)) }
        if collectionProposals.count > 100 { collectionProposals = Array(collectionProposals.suffix(100)) }
        if collectionEdits.count > 100 { collectionEdits = Array(collectionEdits.prefix(100)) }
        if collectionsSeen.count > 2_000 {
            collectionsSeen = Dictionary(
                uniqueKeysWithValues: collectionsSeen.sorted { $0.value > $1.value }.prefix(1_500).map { ($0.key, $0.value) })
        }
    }
}

/// One element that may not decode: nil then, so the rest still do.
nonisolated struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// A collection change waiting for the user (Suggested Labels → Collections).
nonisolated struct CollectionProposal: Codable, Identifiable, Equatable, Sendable {
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
nonisolated struct CollectionEdit: Codable, Identifiable, Equatable, Sendable {
    var id: String { keyword + String(at.timeIntervalSince1970) }
    let keyword: String
    let previous: String?
    let value: String
    let summary: String
    let automatic: Bool
    let at: Date
}

/// Whose labelling state it is (`LabellingState.server`/`user`).
nonisolated enum LabellingOwner {
    /// Another account than the one kept: another server, or another user
    /// signed in than the one before. No user now (signed out), or none
    /// known before, is no change.
    static func changed(fromServer old: String?, user oldUser: String?, toServer server: String, user: String?) -> Bool {
        let otherServer = old.map { $0 != server } ?? false
        let otherUser = user != nil && oldUser != nil && oldUser != user
        return otherServer || otherUser
    }
}

/// When the automatic runs go.
nonisolated enum LabellingSchedule {
    /// Between runs.
    static let interval: TimeInterval = 15 * 60

    /// Seconds until the first run: 20 to let the app settle, or until the
    /// last run is `interval` old, whichever is later.
    static func firstWait(after lastRun: Date?, now: Date = Date()) -> TimeInterval {
        let settle: TimeInterval = 20
        guard let lastRun else { return settle }
        return max(settle, lastRun.addingTimeInterval(interval).timeIntervalSince(now))
    }
}

/// What a failed answer means for a run: this page only (it was declined,
/// or isn't one the engine may see), or every page (no network, a refused
/// key, a model that doesn't exist, a reply that didn't read): the run
/// stops there and the page stays for the next, rather than spending a
/// request on each of the rest and marking them done.
nonisolated enum LabelFailure: Equatable {
    case thisPage
    case stop

    init(_ error: Error) {
        switch error as? AIError {
        case .declined, .tooLong, .emptyContent, .noEngine: self = .thisPage
        default: self = .stop
        }
    }
}

/// What takes a collection edit back out of the collection's value now.
nonisolated enum AliasUndo: Equatable {
    case write(String)
    /// Gone, or already without what the edit added.
    case nothing
    /// No longer a plain label list: the user's own now.
    case cannot

    /// Unchanged since: back to `previous`. Changed since (another label
    /// added after): only this edit's labels come out.
    init(_ edit: CollectionEdit, previous: String, current: String?) {
        guard let current, current != previous else {
            self = .nothing
            return
        }
        if current == edit.value {
            self = .write(previous)
            return
        }
        guard let now = AliasValue.labels(in: current), let made = AliasValue.labels(in: edit.value),
              let before = AliasValue.labels(in: previous)
        else {
            self = .cannot
            return
        }
        let added = Set(made).subtracting(before)
        let kept = now.filter { !added.contains($0) }
        if kept == now {
            self = .nothing
        } else {
            self = kept.isEmpty ? .cannot : .write(AliasValue.value(for: kept))
        }
    }
}

/// labelling.json in Application Support: this device's own, as the
/// outbox (kept out of backups, and on iOS readable only once the device
/// has been unlocked since boot). Read and written on one serial queue, off
/// the main thread, so a write asked for before another lands before it.
nonisolated enum LabellingStore {
    enum Outcome: Sendable {
        case missing
        case read(LabellingState)
        /// There, but not readable now (the device locked since boot):
        /// nothing is written over it.
        case unreadable
    }

    private static let log = Logger(subsystem: ShioriID.app, category: "ai")
    private static let queue = DispatchQueue(label: "Labelling", qos: .utility)
    /// Copies of a file that didn't decode, newest kept.
    static let keptAside = 3

    static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "AI", directoryHint: .isDirectory).appending(path: "labelling.json")
    }

    static func read() async -> Outcome {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: readNow()) }
        }
    }

    static func write(_ state: LabellingState) {
        queue.async { writeNow(state) }
    }

    static func readNow(from file: URL? = Self.file) -> Outcome {
        guard let file else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .missing
        } catch {
            log.error("Labelling state not read: \(error.localizedDescription, privacy: .private)")
            return .unreadable
        }
        do {
            return .read(try JSONDecoder().decode(LabellingState.self, from: data))
        } catch {
            // Kept aside before starting empty, so the next save can't
            // overwrite the Undo log and what was learnt.
            keepAside(file)
            log.error("Labelling state unreadable, kept aside: \(error.localizedDescription, privacy: .private)")
            return .missing
        }
    }

    /// labelling-<time>.json.bak beside it, the newest `keptAside` kept
    /// (one bad file no longer replaces the copy of the one before).
    static func keepAside(_ file: URL, now: Date = Date()) {
        let folder = file.deletingLastPathComponent()
        let stamp = Int(now.timeIntervalSince1970)
        try? FileManager.default.moveItem(at: file, to: folder.appending(path: "labelling-\(stamp).json.bak"))
        let copies = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("labelling") && $0.pathExtension == "bak" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in copies.dropFirst(keptAside) { try? FileManager.default.removeItem(at: old) }
    }

    static func writeNow(_ state: LabellingState, to file: URL? = Self.file) {
        guard let file else { return }
        do {
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
            log.error("Labelling state not saved: \(error.localizedDescription, privacy: .private)")
        }
    }
}
