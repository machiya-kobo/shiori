import Foundation
import os

/// A page to add to Hister (`POST /api/add`).
public struct NewPage: Codable, Sendable, Equatable {
    public var url: String
    public var title: String
    /// Raw HTML; Hister extracts the text itself when `text` is empty.
    public var html: String?
    public var text: String?
    /// A topic label; nil or empty leaves the page "visited".
    public var label: String?
    /// When it was visited or shared, in unix seconds. Set when a page is
    /// queued, so a late send keeps the real time.
    public var added: Int?
    public var metadata: [String: MetadataValue]

    public init(
        url: String, title: String, html: String? = nil, text: String? = nil, label: String? = nil,
        added: Int? = nil, via: String, clientVersion: String = HisterClient.clientVersion,
        ignoreSkipRules: Bool = true, extra: [String: String] = [:]
    ) {
        self.url = url
        self.title = title
        self.html = html
        self.text = text
        self.label = label?.isEmpty == true ? nil : label
        self.added = added
        // Hister's convention for where a document came from, and Shiori's
        // own provenance (`extra`: a note-links save's `from_note`).
        var metadata: [String: MetadataValue] = [
            "source": .string("shiori"),
            "client": .string("shiori"),
            "client_version": .string(clientVersion),
            "via": .string(via),
        ]
        // A deliberate save: skip rules are for automatic capture. Not a
        // bulk save of a note's links, where only Save Anyway overrides.
        if ignoreSkipRules { metadata["ignore_skip_rules"] = .bool(true) }
        for (key, value) in extra { metadata[key] = .string(value) }
        self.metadata = metadata
    }

    public enum MetadataValue: Codable, Sendable, Equatable {
        case string(String)
        case bool(Bool)

        public init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b) } else { self = .string(try c.decode(String.self)) }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .bool(let b): try c.encode(b)
            }
        }
    }
}

extension HisterClient {
    /// The app's version, for `metadata.client_version`.
    public static var clientVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// Adds (or updates) a page. Throws `.rejected` for the replies that
    /// retrying can't change.
    public func add(_ page: NewPage) async throws(HisterError) {
        let body: Data
        do {
            body = try JSONEncoder().encode(page)
        } catch {
            throw .badResponse
        }
        do {
            _ = try await sendAdd(body)
        } catch .server(let status, let message) where [406, 413, 422].contains(status) {
            throw .rejected(Rejection(status: status, message: message))
        }
    }
}

/// Why Hister refused a page, for good.
public struct Rejection: Sendable, Equatable {
    public var status: Int
    public var message: String

    public var reason: String {
        switch status {
        case 406: "Hister skips this site."
        case 413: "The page is too large for Hister."
        case 422: "Hister refused it as sensitive (it looks like it holds a secret)."
        default: message
        }
    }
}

/// Downloads a page that was shared as a bare link, for Hister to index.
/// Capped, because a share extension runs in little memory.
public enum PageFetcher {
    public static let maxBytes = 3 * 1024 * 1024
    public static let maxHTMLCharacters = 2 * 1024 * 1024

    public struct Fetched: Sendable, Equatable {
        public var url: String
        public var title: String
        public var html: String

        public init(url: String, title: String, html: String) {
            self.url = url
            self.title = title
            self.html = html
        }
    }

    public static func fetch(_ url: URL, session: URLSession = .shared) async throws -> Fetched {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        let finalURL = (response.url ?? url).absoluteString
        if let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
            !type.contains("html"), !type.contains("text/plain")
        {
            return Fetched(url: finalURL, title: "", html: "")
        }
        // Room for the page up front (the share extension has little memory
        // to spare for regrowing it), capped either way.
        var data = Data()
        let expected = response.expectedContentLength
        data.reserveCapacity(expected > 0 ? min(Int(expected), maxBytes) : 256 * 1024)
        for try await byte in bytes {
            data.append(byte)
            if data.count >= maxBytes { break }
        }
        let html = String(decoding: data, as: UTF8.self)
        return Fetched(url: finalURL, title: title(in: html), html: capped(html))
    }

    /// The document's <title>, entities decoded.
    public static func title(in html: String) -> String {
        guard let match = html.firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/) else { return "" }
        return Snippet(html: String(match.output.1)).plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cut at the last '>' before the cap, as the Safari extension does.
    public static func capped(_ html: String) -> String {
        guard html.count > maxHTMLCharacters else { return html }
        let prefix = html.prefix(maxHTMLCharacters)
        if let close = prefix.lastIndex(of: ">") { return String(prefix[...close]) }
        return String(prefix)
    }
}

/// Pages waiting for Hister to be reachable, one JSON file each, oldest
/// first. Lives in the App Group, so the share extension and the Save
/// shortcut can queue and the app sends.
public struct Outbox: Sendable {
    public let directory: URL
    public static let maxAttempts = 5
    /// A page nobody could send for this long is dropped, as the Safari
    /// extension's queue drops its own.
    public static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    public init(directory: URL) {
        self.directory = directory
    }

    private static let log = Logger(subsystem: logSubsystem, category: "outbox")

    /// Atomic, and on iOS readable only once the device has been unlocked
    /// since boot (the share extension and the app both run unlocked).
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }

    struct Entry: Codable {
        var page: NewPage
        var attempts: Int
    }

    public struct Status: Sendable, Equatable {
        public var count: Int
        public var oldest: Date?

        public init(count: Int, oldest: Date?) {
            self.count = count
            self.oldest = oldest
        }
    }

    /// Queues a page, stamping its visit time if it has none. A page
    /// already waiting is replaced, keeping its first time.
    public func enqueue(_ page: NewPage, now: Date = .now) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Pages in transit, holding their HTML: not for device backups.
        var directory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? directory.setResourceValues(resourceValues)
        var page = page
        for file in files() {
            if let entry = read(file), entry.page.url == page.url {
                page.added = page.added ?? entry.page.added
                try? FileManager.default.removeItem(at: file)
            }
        }
        page.added = page.added ?? Int(now.timeIntervalSince1970)
        let name = String(format: "%.6f-%@.json", now.timeIntervalSince1970, UUID().uuidString)
        let data = try JSONEncoder().encode(Entry(page: page, attempts: 0))
        try data.write(to: directory.appending(path: name), options: Self.writeOptions)
    }

    public func status() -> Status {
        let files = files()
        let oldest = files.first.flatMap { read($0)?.page.added }.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return Status(count: files.count, oldest: oldest)
    }

    public var pages: [NewPage] { files().compactMap { read($0)?.page } }

    public enum DrainResult: Sendable, Equatable {
        case sent(Int)
        /// Stopped: the server is unreachable or unwell; the rest waits.
        case stopped(sent: Int)
    }

    /// Sends oldest first. Stops at the first unreachable/5xx; drops pages
    /// Hister rejects for good (skip rule, too large, sensitive), and
    /// pages older than `maxAge`.
    @discardableResult
    public func drain(using client: HisterClient, now: Date = .now) async -> DrainResult {
        var sent = 0
        for file in files() {
            guard var entry = read(file) else {
                // Unreadable (a damaged write, or a newer app's shape): the
                // page is lost either way, so say so rather than nothing.
                Self.log.error("Dropping an outbox entry that couldn't be read: \(file.lastPathComponent, privacy: .public)")
                try? FileManager.default.removeItem(at: file)
                continue
            }
            if let added = entry.page.added, now.timeIntervalSince1970 - TimeInterval(added) > Self.maxAge {
                Self.log.notice("Dropping an outbox entry older than \(Int(Self.maxAge / 86400)) days")
                try? FileManager.default.removeItem(at: file)
                continue
            }
            do {
                try await client.add(entry.page)
                sent += 1
                try? FileManager.default.removeItem(at: file)
            } catch .rejected, .invalidQuery, .notFound, .badResponse {
                try? FileManager.default.removeItem(at: file)
            } catch .signedOut {
                // Kept, no try counted: it goes once this device signs in again.
                return .stopped(sent: sent)
            } catch .server(let status, _) where status < 500 && status != 429 {
                try? FileManager.default.removeItem(at: file)
            } catch .server {
                entry.attempts += 1
                if entry.attempts >= Self.maxAttempts {
                    try? FileManager.default.removeItem(at: file)
                } else if let data = try? JSONEncoder().encode(entry) {
                    try? data.write(to: file, options: Self.writeOptions)
                }
                return .stopped(sent: sent)
            } catch {
                return .stopped(sent: sent)
            }
        }
        return .sent(sent)
    }

    private func files() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path())) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { directory.appending(path: $0) }
    }

    private func read(_ file: URL) -> Entry? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }
}
