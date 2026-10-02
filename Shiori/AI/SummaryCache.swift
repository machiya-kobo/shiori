import CryptoKit
import Foundation
import ShioriAI

/// Summaries already made, per page and version (its `updated`): a second
/// look is instant and costs nothing. In this app's caches (the system
/// may clear them; nothing is lost but a regeneration), not in Hister,
/// where the next visit would overwrite them.
nonisolated enum SummaryCache {
    struct Entry: Codable {
        let url: String
        let updated: Date
        let summary: Summary
        /// The prompt's style it was made under (`Summarizer.style`); none
        /// before the short style, so those are made again.
        var style: Int?
    }

    static let limit = 300

    static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "Summaries", directoryHint: .isDirectory)
    }

    static func read(url: String, updated: Date) -> Summary? {
        guard let file = file(for: url), let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.url == url, entry.updated == updated, entry.style == Summarizer.style
        else { return nil }
        return entry.summary
    }

    static func write(_ summary: Summary, url: String, updated: Date) {
        guard let directory, let file = file(for: url),
              let data = try? JSONEncoder().encode(Entry(url: url, updated: updated, summary: summary, style: Summarizer.style))
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        prune(directory)
    }

    static func remove(url: String) {
        if let file = file(for: url) { try? FileManager.default.removeItem(at: file) }
    }

    private static func file(for url: String) -> URL? {
        let name = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: name + ".json")
    }

    /// The newest `limit` stay.
    private static func prune(_ directory: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys),
              files.count > limit
        else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
