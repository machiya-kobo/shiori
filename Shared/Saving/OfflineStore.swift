import CryptoKit
import Foundation
import HisterKit
import Synchronization

/// What the apps can show without the network: the first page of each
/// Library list (All, Pages, Notes, newest first) and the last
/// `previewLimit` previews opened, in this app's caches (the system may
/// clear them; nothing is lost but the offline copy). Each copy belongs to
/// the server and Kura it came from (`origin`), and says when it was made.
///
/// Fails closed: a note from a private vault (`Notes.isPrivateNote`, which
/// counts an unknown vault as private), a file and code are never kept, and
/// what's read back is checked again, since a vault may have turned private
/// since (and a copy that fails is deleted). Signing out of Hister, or
/// another token or user, empties it all; a delete drops its preview.
///
/// Writes, pruning, forgetting and clearing run on one serial queue off the
/// caller's (the main) actor, in the order asked: a save asked for before a
/// sign-out's clear can't land after it, nor one fetched before it and
/// asked for after (`epoch`). Reads stay where the UI waits.
nonisolated enum OfflineStore {
    static let previewLimit = 50
    /// The first page a Library list loads.
    static let listLimit = 30
    /// Lists kept, newest first: the Library's few, for a few servers (a
    /// changed address leaves the old one's behind).
    static let listFiles = 12

    /// May this page be kept on the device?
    static func keepable(_ page: StoredPage) -> Bool {
        keepable(url: page.url) && page.code == nil
    }

    static func keepable(url: String) -> Bool {
        !Notes.isPrivateNote(url) && !LocalFiles.isLocalFile(url)
    }

    /// The server and Kura a copy came from: one changed, the copy is another's.
    static func origin(server: String, kura: String) -> String { "\(server)|\(kura)" }

    // MARK: Lists

    /// Bumped by every `clear`. A caller reads it before asking the server
    /// and passes it with the copy: one fetched under the credential a
    /// sign-out just cleared is then never written.
    static var epoch: Int { epochs.withLock { $0 } }
    private static let epochs = Mutex(0)
    private static func current(_ epoch: Int) -> Bool { epochs.withLock { $0 == epoch } }

    static func saveList(_ name: String, origin: String, pages: [StoredPage], now: Date = .now, epoch: Int = OfflineStore.epoch) {
        // Which pages may be kept is decided now; the rest happens off this actor.
        let kept = Array(pages.filter(keepable).prefix(listLimit))
        guard let file = file("lists", "\(origin)|\(name)") else { return }
        queue.async {
            guard current(epoch) else { return }
            write(ListEntry(origin: origin, savedAt: now, pages: kept.map(Page.init)), to: file)
            prune(file.deletingLastPathComponent(), keeping: listFiles)
        }
    }

    static func list(_ name: String, origin: String) -> (pages: [StoredPage], savedAt: Date)? {
        guard let file = file("lists", "\(origin)|\(name)"), let entry: ListEntry = read(file), entry.origin == origin else { return nil }
        let pages = entry.pages.map(\.page).filter(keepable)
        if pages.count < entry.pages.count {
            // A vault turned private since: its notes leave the copy now.
            let left = ListEntry(origin: entry.origin, savedAt: entry.savedAt, pages: pages.map(Page.init))
            queue.async { write(left, to: file) }
        }
        return pages.isEmpty ? nil : (pages, entry.savedAt)
    }

    // MARK: Previews

    /// One copy per page, named by its address alone (so `forget` finds it
    /// without reading anything); the origin inside is checked on reading.
    static func savePreview(_ preview: PagePreview, for page: StoredPage, origin: String, now: Date = .now, epoch: Int = OfflineStore.epoch) {
        guard keepable(page), let file = previewFile(page.url), let folder = directory?.appending(path: "previews", directoryHint: .isDirectory)
        else { return }
        let url = page.url
        queue.async {
            guard current(epoch) else { return }
            write(PreviewEntry(origin: origin, url: url, savedAt: now, preview: Preview(preview)), to: file)
            prune(folder, keeping: previewLimit)
        }
    }

    static func preview(for page: StoredPage, origin: String) -> (preview: PagePreview, savedAt: Date)? {
        guard keepable(page) else {
            // A vault turned private since: its copy goes now (as SummaryCache's does).
            forget(url: page.url)
            return nil
        }
        guard let entry: PreviewEntry = read(previewFile(page.url)),
              entry.origin == origin, entry.url == page.url
        else { return nil }
        return (entry.preview.preview, entry.savedAt)
    }

    /// A deleted page's preview goes with it (whichever origin's copy it
    /// is), and it leaves the lists' copies.
    static func forget(url: String) {
        guard let file = previewFile(url) else { return }
        let lists = directory?.appending(path: "lists", directoryHint: .isDirectory)
        queue.async {
            try? FileManager.default.removeItem(at: file)
            guard let lists, let files = try? FileManager.default.contentsOfDirectory(at: lists, includingPropertiesForKeys: nil) else { return }
            for list in files {
                guard let entry: ListEntry = read(list), entry.pages.contains(where: { $0.url == url }) else { continue }
                write(ListEntry(origin: entry.origin, savedAt: entry.savedAt, pages: entry.pages.filter { $0.url != url }), to: list)
            }
        }
    }

    /// Everything, on signing out.
    static func clear() {
        // At once, not on the queue: a copy asked for before this, and
        // still waiting there, is dropped.
        epochs.withLock { $0 &+= 1 }
        guard let directory else { return }
        queue.async { try? FileManager.default.removeItem(at: directory) }
    }

    /// Returns once every write, prune and clear asked for so far is done.
    static func settled() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in queue.async { done.resume() } }
    }

    // MARK: Files

    /// Serial, so writes and clears land in the order asked.
    private static let queue = DispatchQueue(label: "Offline", qos: .utility)

    static var directory: URL? {
        #if DEBUG
        if let testDirectory { return testDirectory }
        #endif
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "Offline", directoryHint: .isDirectory)
    }

    #if DEBUG
    /// Set by the tests: a folder of their own instead of the app's caches.
    nonisolated(unsafe) static var testDirectory: URL?
    #endif

    private static func file(_ folder: String, _ key: String) -> URL? {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: folder, directoryHint: .isDirectory).appending(path: name + ".json")
    }

    private static func previewFile(_ url: String) -> URL? { file("previews", url) }

    private static func write(_ value: some Encodable, to file: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func read<T: Decodable>(_ file: URL?) -> T? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// The newest `limit` stay.
    private static func prune(_ folder: URL, keeping limit: Int) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys),
              files.count > limit
        else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Stored shapes (HisterKit's models aren't Codable)

    private struct ListEntry: Codable {
        let origin: String
        let savedAt: Date
        let pages: [Page]
    }

    private struct PreviewEntry: Codable {
        let origin: String
        let url: String
        let savedAt: Date
        let preview: Preview
    }

    private struct Page: Codable {
        let url, title, domain, label, faviconKey, snippetHTML: String
        let added, updated: Date

        init(_ page: StoredPage) {
            url = page.url
            title = page.title
            domain = page.domain
            label = page.label
            faviconKey = page.faviconKey
            snippetHTML = page.snippetHTML
            added = page.added
            updated = page.updated
        }

        var page: StoredPage {
            StoredPage(url: url, title: title, domain: domain, label: label, added: added, updated: updated,
                       faviconKey: faviconKey, snippetHTML: snippetHTML)
        }
    }

    private struct Preview: Codable {
        let title, contentHTML, label: String
        let added, updated: Date
        let visits: Int
        let author, summary: String?
        let tags: [String]

        init(_ preview: PagePreview) {
            title = preview.title
            contentHTML = preview.contentHTML
            label = preview.label
            added = preview.added
            updated = preview.updated
            visits = preview.visits
            author = preview.author
            summary = preview.summary
            tags = preview.tags
        }

        var preview: PagePreview {
            PagePreview(title: title, contentHTML: contentHTML, added: added, updated: updated, label: label,
                        visits: visits, author: author, summary: summary, tags: tags)
        }
    }
}

extension Date {
    /// "Offline · as of 3:42 PM" (a day before today: "as of Oct 4, 3:42 PM").
    var offlineAsOf: String {
        "Offline · as of " + formatted(date: Calendar.current.isDateInToday(self) ? .omitted : .abbreviated, time: .shortened)
    }
}
