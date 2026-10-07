import Foundation
import HisterKit
import Observation

/// Delete with Undo: every delete in the app goes this way (swipe, menu,
/// the page's ⋯, dd). The page is gone from every list at once, and from
/// Hister when the toast's time is up. Hister can't bring a deleted page
/// back, so the undo is the wait, not a restore.
@Observable final class PendingDeletes {
    /// A delete waiting out its Undo.
    struct Pending: Identifiable, Equatable {
        let id = UUID()
        let document: StoredPage
    }

    /// Pages deleted in this session; lists hide them without refetching.
    private(set) var hidden: Set<String> = []
    private(set) var pending: Pending?
    /// Why the last delete failed (it's back in its list).
    var failure: String?

    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    @ObservationIgnored private let send: (StoredPage) async throws(HisterError) -> Void
    @ObservationIgnored private let isPrivate: (String) -> Bool
    @ObservationIgnored private let undoWindow: Duration
    @ObservationIgnored private let holdBackground: () -> (() -> Void)

    /// `send`: the delete itself (it refuses a private vault's note or a
    /// file again, and drops the page's offline copies). `isPrivate`: a
    /// private vault's note, never sent. `holdBackground`: time to finish
    /// a delete sent on the way to the background; its result ends it.
    init(
        send: @escaping (StoredPage) async throws(HisterError) -> Void,
        isPrivate: @escaping (String) -> Bool,
        undoWindow: Duration,
        holdBackground: @escaping () -> (() -> Void) = { {} }
    ) {
        self.send = send
        self.isPrivate = isPrivate
        self.undoWindow = undoWindow
        self.holdBackground = holdBackground
    }

    func start(_ document: StoredPage) {
        // Hister never has a work note, and must never be sent one's address.
        guard !isPrivate(document.url) else { return }
        commit()
        // Bounded: the lists refetch long before this many deletes matter.
        if hidden.count >= 2000 { hidden.removeAll() }
        hidden.insert(document.url)
        let pending = Pending(document: document)
        self.pending = pending
        let window = undoWindow
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            await self?.finish(pending)
        }
    }

    func undo() {
        guard let pending else { return }
        pendingTask?.cancel()
        self.pending = nil
        hidden.remove(pending.document.url)
    }

    /// Sends a waiting delete now: another delete started, or the app is
    /// going to the background (a delete is what was asked for).
    func commit() {
        guard let pending else { return }
        pendingTask?.cancel()
        self.pending = nil
        // Leaving for the background, iOS would suspend the app mid-DELETE.
        let release = holdBackground()
        Task {
            await finish(pending)
            release()
        }
    }

    private func finish(_ pending: Pending) async {
        if self.pending?.id == pending.id { self.pending = nil }
        do {
            try await send(pending.document)
        } catch {
            hidden.remove(pending.document.url)
            failure = error.userMessage
        }
    }
}
