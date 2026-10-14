import CryptoKit
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

    /// The site answered with an error of its own (404, 403, a bot check,
    /// 503): its error page is never saved as if it were the page.
    public struct SiteError: Error, Sendable, Equatable {
        public var status: Int
        public init(status: Int) { self.status = status }
        /// 429 and 5xx: the site may answer later.
        public var isTemporary: Bool { status == 429 || status >= 500 }
        public var message: String {
            isTemporary ? "The site is busy (it answered \(status)): try again later." : "The site answered \(status): not saved."
        }
    }

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

    /// Its own session: no cookies or cache shared with anything else, and
    /// the whole download (redirects included) done in 30 s at most.
    /// Redirects are followed: the save looks the final address up again.
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    public static func fetch(_ url: URL, session: URLSession = PageFetcher.session) async throws -> Fetched {
        // A web page only: never a file:// (or any other scheme's) address.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        let finalURL = (response.url ?? url).absoluteString
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw SiteError(status: status)
        }
        if let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
            !type.contains("html"), !type.contains("text/plain")
        {
            return Fetched(url: finalURL, title: "", html: "")
        }
        // Room for the page up front (the share extension has little memory
        // to spare for regrowing it), capped either way. Read in chunks: a
        // byte at a time costs an await per byte.
        var data = Data()
        let expected = response.expectedContentLength
        data.reserveCapacity(expected > 0 ? min(Int(expected), maxBytes) : 256 * 1024)
        var chunk: [UInt8] = []
        chunk.reserveCapacity(chunkSize)
        for try await byte in bytes {
            chunk.append(byte)
            guard chunk.count == chunkSize else { continue }
            data.append(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
            if data.count >= maxBytes { break }
        }
        data.append(contentsOf: chunk)
        let html = String(decoding: data.prefix(maxBytes), as: UTF8.self)
        return Fetched(url: finalURL, title: title(in: html), html: capped(html))
    }

    static let chunkSize = 64 * 1024

    /// An http:// address tried as https:// first: the apps' transport
    /// security refuses plain http, and most sites (a short link's too)
    /// answer on https. A site error there is the answer (never saved as
    /// the page); no answer at all tries the address as given.
    public static func fetchPreferringHTTPS(
        _ url: URL, fetch: (URL) async throws -> Fetched = { try await PageFetcher.fetch($0) }
    ) async throws -> Fetched {
        guard url.scheme?.lowercased() == "http", var secure = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return try await fetch(url)
        }
        secure.scheme = "https"
        guard let attempt = secure.url else { return try await fetch(url) }
        do {
            return try await fetch(attempt)
        } catch let error as SiteError {
            throw error
        } catch {
            if Task.isCancelled { throw error }
            return try await fetch(url)
        }
    }

    /// The document's <title>, entities decoded.
    public static func title(in html: String) -> String {
        guard let match = html.firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/) else { return "" }
        return Snippet(html: String(match.output.1)).plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cut at the last '>' before the cap, as the Safari extension does.
    public static func capped(_ html: String) -> String {
        // UTF-8 bytes are never fewer than characters, and counted at once.
        guard html.utf8.count > maxHTMLCharacters else { return html }
        let prefix = html.prefix(maxHTMLCharacters)
        if let close = prefix.lastIndex(of: ">") { return String(prefix[...close]) }
        return String(prefix)
    }
}

/// Pages waiting for Hister to be reachable, one JSON file each, oldest
/// first. Lives in the App Group, so the share extension and the Save
/// shortcut can queue and the app sends.
///
/// A file's name says when it was queued, the page's visit time and a key
/// of its address (`<queued>_<added>_<key>.json`), so counting the pages,
/// finding one to replace and dropping old ones read no page (each holds up
/// to 2 MB of HTML). A page given up on (refused, too old, too many tries)
/// is listed in `notSaved()`, never dropped without a word.
public struct Outbox: Sendable {
    public let directory: URL
    public static let maxAttempts = 5
    /// A page nobody could send for this long is dropped, as the Safari
    /// extension's queue drops its own.
    public static let maxAge: TimeInterval = 14 * 24 * 60 * 60
    /// At most this many pages wait, in at most this much space. A save
    /// past either is refused (`Full`); no waiting page is dropped for it.
    public static let maxCount = 300
    public static let maxBytes = 100 * 1024 * 1024
    /// How many pages given up on are remembered, newest first.
    public static let notSavedLimit = 20

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

    /// Too many pages wait already: this one isn't kept.
    public struct Full: Error, Sendable, Equatable {
        public init() {}
    }

    /// A page the outbox gave up on: which, why and when.
    public struct NotSaved: Codable, Sendable, Equatable, Identifiable {
        public var url: String
        public var title: String
        public var reason: String
        public var date: Date
        public var id: String { "\(date.timeIntervalSince1970) \(url)" }

        public init(url: String, title: String, reason: String, date: Date) {
            self.url = url
            self.title = title
            self.reason = reason
            self.date = date
        }
    }

    static let tooOld = "Waited more than \(Int(maxAge / 86400)) days."

    /// Queues a page, stamping its visit time if it has none. A page
    /// already waiting is replaced, keeping its first time. Throws `Full`
    /// past `maxCount` pages or `maxBytes`.
    public func enqueue(_ page: NewPage, now: Date = .now) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Pages in transit, holding their HTML: not for device backups.
        var directory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? directory.setResourceValues(resourceValues)
        var page = page
        let key = Self.key(page.url)
        var replaced: [URL] = []
        var count = 0
        var bytes = 0
        for item in listing() {
            var added = item.added
            var same = false
            if let itemKey = item.key {
                // The same key: read that one alone, to be sure it's the same address.
                if itemKey == key, let entry = read(item.file), entry.page.url == page.url {
                    same = true
                    added = entry.page.added
                }
            } else if let entry = read(item.file) {
                // Queued before names said what's inside.
                same = entry.page.url == page.url
                added = entry.page.added
            }
            if same {
                page.added = page.added ?? added
                replaced.append(item.file)
            } else if let added, now.timeIntervalSince1970 - TimeInterval(added) > Self.maxAge {
                // Too old to send: gone now, not only when a drain reaches it.
                Self.log.notice("Dropping an outbox entry older than \(Int(Self.maxAge / 86400)) days")
                drop(item.file, page: nil, reason: Self.tooOld, now: now)
            } else {
                count += 1
                bytes += item.bytes
            }
        }
        let added = page.added ?? Int(now.timeIntervalSince1970)
        page.added = added
        let data = try JSONEncoder().encode(Entry(page: page, attempts: 0))
        guard count < Self.maxCount, bytes + data.count <= Self.maxBytes else { throw Full() }
        let name = Self.name(queued: Self.stamp(now), added: added, url: page.url)
        try data.write(to: directory.appending(path: name), options: Self.writeOptions)
        for file in replaced where file.lastPathComponent != name {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public func status() -> Status {
        let items = listing()
        let oldest = items.compactMap { $0.key == nil ? read($0.file)?.page.added : $0.added }.min()
        return Status(count: items.count, oldest: oldest.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    public var pages: [NewPage] { listing().compactMap { read($0.file)?.page } }

    public enum DrainResult: Sendable, Equatable {
        case sent(Int)
        /// Stopped: the server is unreachable or unwell; the rest waits.
        case stopped(sent: Int)
        /// Stopped: Hister wants this device signed in; the rest waits for that.
        case signedOut(sent: Int)
    }

    /// Sends oldest first. Stops at the first unreachable/unwell reply
    /// (a try counted for a reply, none for no answer or a sign-in); drops
    /// pages Hister refuses for good (skip rule, too large, sensitive, a
    /// request it can't read), pages older than `maxAge` and pages out of
    /// tries, each listed in `notSaved()`. A page kept as its link alone
    /// (the site or the network was down when it was shared) is downloaded
    /// with `fetch` first: a site error drops it, a busy site keeps it a try.
    @discardableResult
    public func drain(using client: HisterClient, now: Date = .now,
                      fetch: (@Sendable (URL) async throws -> PageFetcher.Fetched)? = nil) async -> DrainResult {
        var sent = 0
        for item in listing() {
            let file = item.file
            guard var entry = read(file) else {
                // Unreadable (a damaged write, or a newer app's shape): the
                // page is lost either way, so say so rather than nothing.
                Self.log.error("Dropping an outbox entry that couldn't be read: \(file.lastPathComponent, privacy: .public)")
                drop(file, page: nil, reason: "Its copy on this device couldn't be read.", now: now)
                continue
            }
            if let added = entry.page.added, now.timeIntervalSince1970 - TimeInterval(added) > Self.maxAge {
                Self.log.notice("Dropping an outbox entry older than \(Int(Self.maxAge / 86400)) days")
                drop(file, page: entry.page, reason: Self.tooOld, now: now)
                continue
            }
            if let fetch, (entry.page.html ?? "").isEmpty, (entry.page.text ?? "").isEmpty, let url = URL(string: entry.page.url) {
                do {
                    let fetched = try await fetch(url)
                    entry.page.html = fetched.html
                    if !fetched.url.isEmpty { entry.page.url = fetched.url }
                    if !fetched.title.isEmpty, entry.page.title.isEmpty || entry.page.title == url.host() { entry.page.title = fetched.title }
                } catch let error as PageFetcher.SiteError where !error.isTemporary {
                    Self.log.notice("Dropping an outbox entry: the site answered \(error.status)")
                    drop(file, page: entry.page, reason: error.message, now: now)
                    continue
                } catch {
                    // Busy or out of reach: kept, a try counted, for the next drain.
                    countTry(&entry, at: file, reason: "Couldn't download it in \(Self.maxAttempts) tries.", now: now)
                    continue
                }
            }
            do {
                try await client.add(entry.page)
                sent += 1
                try? FileManager.default.removeItem(at: file)
            } catch .rejected(let rejection) {
                drop(file, page: entry.page, reason: rejection.reason, now: now)
            } catch .invalidQuery(let message) {
                // 400: Hister can't read this page's request; sending it again won't change that.
                drop(file, page: entry.page, reason: message.isEmpty ? "Hister couldn't read it." : "Hister refused it: \(message.prefix(120))", now: now)
            } catch .badResponse {
                drop(file, page: entry.page, reason: "It couldn't be put in a form Hister reads.", now: now)
            } catch .signedOut {
                // Kept, no try counted: it goes once this device signs in again.
                return .signedOut(sent: sent)
            } catch .notFound {
                // Hister always has api/add: a 404 is the way there (a proxy), so it waits, a try counted.
                countTry(&entry, at: file, reason: "Hister answered 404 \(Self.maxAttempts) times.", now: now)
                return .stopped(sent: sent)
            } catch .server(let status, _) {
                countTry(&entry, at: file, reason: "Hister answered \(status) \(Self.maxAttempts) times.", now: now)
                return .stopped(sent: sent)
            } catch {
                return .stopped(sent: sent)
            }
        }
        return .sent(sent)
    }

    // MARK: Not Saved

    /// The pages given up on, newest first (at most `notSavedLimit`).
    public func notSaved() -> [NotSaved] {
        (try? Data(contentsOf: notSavedFile)).flatMap { try? JSONDecoder().decode([NotSaved].self, from: $0) } ?? []
    }

    public func clearNotSaved() {
        try? FileManager.default.removeItem(at: notSavedFile)
    }

    /// Not a page: no ".json", so never listed as one.
    private var notSavedFile: URL { directory.appending(path: "NotSaved.data") }

    private func drop(_ file: URL, page: NewPage?, reason: String, now: Date) {
        let page = page ?? read(file)?.page
        try? FileManager.default.removeItem(at: file)
        var list = notSaved()
        list.insert(NotSaved(url: page?.url ?? "", title: page?.title ?? "", reason: reason, date: now), at: 0)
        guard let data = try? JSONEncoder().encode(Array(list.prefix(Self.notSavedLimit))) else { return }
        try? data.write(to: notSavedFile, options: Self.writeOptions)
    }

    /// A try that failed: the page waits for the next drain, or, out of
    /// tries, is given up on.
    private func countTry(_ entry: inout Entry, at file: URL, reason: String, now: Date) {
        entry.attempts += 1
        if entry.attempts >= Self.maxAttempts {
            drop(file, page: entry.page, reason: reason, now: now)
        } else {
            rewrite(entry, at: file)
        }
    }

    /// Writes an entry back under its name (renamed if a download moved its
    /// address). Not if it's gone meanwhile (queued again from the share
    /// sheet, so a newer copy waits): that one stays the only one.
    private func rewrite(_ entry: Entry, at file: URL) {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
            let data = try? JSONEncoder().encode(entry)
        else { return }
        let name = Self.name(queued: Self.queuedPart(of: file.lastPathComponent), added: entry.page.added ?? 0, url: entry.page.url)
        guard (try? data.write(to: directory.appending(path: name), options: Self.writeOptions)) != nil else { return }
        if name != file.lastPathComponent { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: Files

    private struct Listed {
        let file: URL
        /// From the name; nil for a name from before names said what's inside.
        let added: Int?
        let key: String?
        let bytes: Int
    }

    /// The pages' files, oldest queued first. Listed by URL, not by path: a
    /// path (`path()`) is percent-encoded, and the Mac's App Group folder
    /// ("Group Containers") has a space.
    private func listing() -> [Listed] {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { file in
                let parsed = Self.parse(file.lastPathComponent)
                return Listed(file: file, added: parsed?.added, key: parsed?.key,
                              bytes: (try? file.resourceValues(forKeys: keys).fileSize) ?? 0)
            }
    }

    private func read(_ file: URL) -> Entry? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    static func stamp(_ date: Date) -> String { String(format: "%.6f", date.timeIntervalSince1970) }

    static func name(queued: String, added: Int, url: String) -> String { "\(queued)_\(added)_\(key(url)).json" }

    /// A short key of the address, for the file's name (not the address
    /// itself: names have a length limit and no "/").
    static func key(_ url: String) -> String {
        SHA256.hash(data: Data(url.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func parse(_ name: String) -> (added: Int, key: String)? {
        guard name.hasSuffix(".json") else { return nil }
        let parts = name.dropLast(5).split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 3, Double(parts[0]) != nil, let added = Int(parts[1]), parts[2].count == 16 else { return nil }
        return (added, String(parts[2]))
    }

    /// The queued time a name starts with (either shape of name).
    static func queuedPart(of name: String) -> String {
        String(name.prefix { $0.isNumber || $0 == "." })
    }
}
