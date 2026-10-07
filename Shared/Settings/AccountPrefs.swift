import Foundation
import os

/// The settings that follow the person (machiya docs/contracts/prefs.md):
/// the account's copy at the sign-in helper on Hister's host
/// (`/machiya/api/prefs`), kept in step with this device's App Group, where
/// the app, Safari's results page and the share extension read them.
///
/// One contact (`contact`): what this device changed since the last one is
/// sent first (with anything a failed send left pending), then the account's
/// answer is merged by the contract's rules (`PrefsSync.sync`), written to
/// the App Group, and what the account lacks is sent. A change made in
/// Safari's results page is in the App Group too, so it's picked up the same
/// way. Failures are silent: the App Group stays the first-paint and offline
/// copy, and Settings' state line says so.
enum AccountPrefs {
    enum State: Equatable {
        /// No sign-in on this device (and no Hister token): nothing follows.
        case notSignedIn
        case synced
        /// The helper said sign in again (401).
        case signInNeeded
        /// The helper, Hister or the network didn't answer (or 503).
        case unavailable
    }

    /// How the request proves who's asking: the app's sign-in id, else
    /// Hister's token (the helper is on Hister's own host).
    enum Credential: Sendable {
        case session(String)
        case token(String)
    }

    static let pendingKey = "prefsPending"
    static let seenKey = "prefsSeen"
    static let localKey = "prefsLocal"

    // MARK: This device's values

    /// This device's settings in the account's words (the App Group's).
    static func current(_ d: UserDefaults) -> [String: String] {
        var settings: [String: Any] = [:]
        for key in [SharedSettings.Key.theme, SharedSettings.Key.palette, SharedSettings.Key.textSize, SharedSettings.Key.resultStyle,
                    SharedSettings.Key.smallWebOpen] {
            if let value = d.string(forKey: key) { settings[key] = value }
        }
        if let pills = d.array(forKey: SharedSettings.Key.pills) { settings[SharedSettings.Key.pills] = PillOrder.clean(pills) }
        for key in PrefsSync.flags where d.object(forKey: key) != nil { settings[key] = d.bool(forKey: key) }
        for key in PrefsSync.counts where d.object(forKey: key) != nil { settings[key] = d.integer(forKey: key) }
        return PrefsSync.accountValues(settings)
    }

    /// The account's values written to the App Group (nil: back to the default).
    static func apply(_ values: [String: String?], to d: UserDefaults) {
        let mine = d.string(forKey: SharedSettings.Key.textSize) ?? "system"
        for (key, value) in PrefsSync.localValues(values, mine: mine) {
            if value is NSNull { d.removeObject(forKey: key) } else { d.set(value, forKey: key) }
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, _ key: String, _ d: UserDefaults) -> T? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static let log = Logger(subsystem: ShioriID.app, category: "prefs")

    /// What a failed send left, value by value: one that doesn't read (not
    /// a string or null) is logged and dropped, never the rest with it.
    private static func readPending(_ d: UserDefaults) -> [String: String?] {
        guard let data = d.data(forKey: pendingKey) else { return [:] }
        if let pending = try? JSONDecoder().decode([String: String?].self, from: data) { return pending }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.error("Pending settings unreadable: none kept")
            return [:]
        }
        var pending: [String: String?] = [:]
        for (key, value) in object {
            if let text = value as? String { pending[key] = .some(text) } else if value is NSNull { pending[key] = .some(nil) }
        }
        // Counts only: the keys and values are the person's settings.
        log.error("Pending settings partly unreadable: \(pending.count, privacy: .public) of \(object.count, privacy: .public) kept")
        return pending
    }

    private static func write<T: Encodable>(_ value: T?, _ key: String, _ d: UserDefaults) {
        if let value, let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) } else { d.removeObject(forKey: key) }
    }

    // MARK: One contact

    /// One contact with the account; the App Group is updated in place.
    static func contact(base: URL, credential: Credential, defaults d: UserDefaults, session: URLSession = AccountPrefs.session) async -> State {
        let now = current(d)
        // What the person changed here since the last contact, and what a
        // failed send left: both go first (rule 2). A first contact has no
        // snapshot: the rules fill the account's blanks instead.
        var pending = readPending(d)
        if let last = read([String: String].self, localKey, d) {
            for key in Set(now.keys).union(last.keys) where now[key] != last[key] { pending[key] = now[key] }
        }
        let seen = read(PrefsSync.Snapshot.self, seenKey, d)
        var answer: PrefsSync.Snapshot
        if !pending.isEmpty {
            switch await send(pending, base: base, credential: credential, session: session) {
            case .ok(let reply):
                answer = reply
                write(Optional<[String: String?]>.none, pendingKey, d)
            case .refused:
                // 400: the store will never take it.
                write(Optional<[String: String?]>.none, pendingKey, d)
                guard case .ok(let reply) = await fetch(base: base, credential: credential, etag: nil, session: session) else { return .unavailable }
                answer = reply
            case .failed(let state):
                write(pending, pendingKey, d)
                write(now, localKey, d)
                return state
            case .unchanged:
                return .unavailable
            }
        } else {
            switch await fetch(base: base, credential: credential, etag: seen?.rev, session: session) {
            case .ok(let reply): answer = reply
            case .unchanged:
                write(now, localKey, d)
                return .synced
            case .refused: return .unavailable
            case .failed(let state): return state
            }
        }
        let (applyValues, sendValues) = PrefsSync.sync(mine: now, seen: seen, answer: answer)
        apply(applyValues, to: d)
        if !sendValues.isEmpty {
            switch await send(sendValues.mapValues { Optional($0) }, base: base, credential: credential, session: session) {
            case .ok(let reply): answer = reply
            case .failed: write(sendValues.mapValues { Optional($0) }, pendingKey, d)
            case .refused, .unchanged: break
            }
        }
        write(answer, seenKey, d)
        write(current(d), localKey, d)
        return .synced
    }

    // MARK: The helper's API

    /// Its own: the request carries a credential, so no cookies or cache
    /// shared with anything else, and no redirect followed.
    static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    enum Reply {
        case ok(PrefsSync.Snapshot)
        case unchanged
        case refused
        case failed(State)
    }

    private struct Wire: Decodable {
        var rev: Int?
        var prefs: [String: String]?
        var updated: [String: Int]?
    }

    static func request(base: URL, credential: Credential, method: String, body: Data? = nil, etag: Int? = nil) -> URLRequest {
        var request = URLRequest(url: base.appending(path: "machiya/api/prefs"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        switch credential {
        case .session(let id): request.setValue("Bearer \(id)", forHTTPHeaderField: "Authorization")
        case .token(let token): request.setValue(token, forHTTPHeaderField: "X-Access-Token")
        }
        if let etag { request.setValue("\"\(etag)\"", forHTTPHeaderField: "If-None-Match") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func fetch(base: URL, credential: Credential, etag: Int?, session: URLSession) async -> Reply {
        await perform(request(base: base, credential: credential, method: "GET", etag: etag), session: session)
    }

    private static func send(_ values: [String: String?], base: URL, credential: Credential, session: URLSession) async -> Reply {
        var prefs: [String: Any] = [:]
        for (key, value) in values { prefs[key] = value.map { $0 as Any } ?? NSNull() }
        guard let body = try? JSONSerialization.data(withJSONObject: ["prefs": prefs]) else { return .refused }
        return await perform(request(base: base, credential: credential, method: "PUT", body: body), session: session)
    }

    private static func perform(_ request: URLRequest, session: URLSession) async -> Reply {
        do {
            // The credential never follows a redirect anywhere.
            let (data, response) = try await session.data(for: request, delegate: NoRedirects())
            guard let http = response as? HTTPURLResponse else { return .failed(.unavailable) }
            switch http.statusCode {
            case 200:
                guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return .failed(.unavailable) }
                return .ok(PrefsSync.Snapshot(rev: wire.rev, prefs: wire.prefs ?? [:], updated: wire.updated ?? [:]))
            case 304: return .unchanged
            case 400: return .refused
            case 401: return .failed(.signInNeeded)
            default: return .failed(.unavailable)
            }
        } catch {
            return .failed(.unavailable)
        }
    }

    /// Called off the main thread: nonisolated (the target's default is the MainActor).
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        nonisolated func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
