import Foundation
import HisterKit

/// Saves one page to Hister: from the share sheet, the Save shortcut, or
/// the app. If Hister can't be reached the page waits in the App Group's
/// outbox, stamped with the time it was saved, and the app sends it later.
nonisolated enum Saver {
    enum Outcome: Sendable, Equatable {
        case saved
        case queued
        case rejected(String)
        case failed(String)
        /// The user cancelled: nothing was saved, and nothing waits.
        case cancelled

        var message: String {
            switch self {
            case .saved: "Saved to Hister."
            case .queued: "Hister is out of reach. Saved on this device; it will be sent when Hister is back."
            case .rejected(let reason): reason
            case .failed(let reason): reason
            case .cancelled: "Cancelled."
            }
        }
    }

    /// What we know about the page before saving. From Safari the page
    /// itself comes along; from other apps usually only the link.
    struct Input: Sendable {
        var url: URL
        var title: String?
        var html: String?
        var text: String?
    }

    static func save(_ input: Input, label: String?, via: String) async -> Outcome {
        let defaults = SharedSettings.defaults
        let serverURL = defaults?.string(forKey: SharedSettings.Key.serverURL) ?? ""
        guard let client = HisterClient(serverURL: serverURL) else {
            return .failed("Set your Hister server in Shiori's Settings first.")
        }
        return await save(input, label: label, via: via, client: client, outbox: SharedSettings.outboxDirectory.map(Outbox.init))
    }

    /// The same, with the server and the outbox given (the tests' way in).
    static func save(_ input: Input, label: String?, via: String, client: HisterClient, outbox: Outbox?) async -> Outcome {
        var page = NewPage(
            url: input.url.absoluteString, title: input.title ?? "", html: input.html, text: input.text,
            label: label, via: via)
        if (page.html ?? "").isEmpty && (page.text ?? "").isEmpty,
            let fetched = try? await PageFetcher.fetch(input.url)
        {
            page.url = fetched.url
            page.html = fetched.html
            if page.title.isEmpty { page.title = fetched.title }
        }
        if page.title.isEmpty { page.title = input.url.host() ?? input.url.absoluteString }

        do {
            try await client.add(page)
            return .saved
        } catch .rejected(let rejection) {
            return .rejected(rejection.reason)
        } catch .cancelled where Task.isCancelled {
            // The user cancelled (not a dropped connection): don't queue it.
            return .cancelled
        } catch .unreachable, .untrusted, .cancelled {
            return queue(page, in: outbox)
        } catch .server(let status, _) where status >= 500 || status == 429 {
            return queue(page, in: outbox)
        } catch {
            return .failed(error.saveMessage)
        }
    }

    private static func queue(_ page: NewPage, in outbox: Outbox?) -> Outcome {
        guard let outbox else {
            return .failed("Hister is out of reach, and the page couldn't be kept for later.")
        }
        do {
            try outbox.enqueue(page)
            return .queued
        } catch {
            return .failed("Hister is out of reach, and the page couldn't be kept for later.")
        }
    }
}

extension Saver {
    /// What became of one link in Save This Note's Links.
    enum LinkOutcome: Sendable, Equatable {
        case saved
        case queued
        /// Hister holds it already (perhaps saved meanwhile by another
        /// device or a room's link checker): never sent again.
        case alreadyInHister
        /// A skip rule refused it (406): only Save Anyway sends it.
        case skipped(String)
        /// Refused for good (413, 422).
        case rejected(String)
        case failed(String)
        case cancelled
        /// A gemini:// or gopher:// page handed to the small-web gateway,
        /// which saves it in the background under this canonical URL.
        case viaGateway(String)
    }

    static let notAPage = "A file, not a web page: not saved."

    /// Saves one of a note's links (Shiori saves pages into Hister; the
    /// other rooms only look up what it holds).
    /// - Never a URL Hister holds: it's looked up right before the save
    ///   (and again under its address after redirects), since `api/add`
    ///   replaces a stored page's metadata.
    /// - The page is downloaded here (Hister doesn't fetch a bare URL).
    /// - Skip rules hold unless `anyway` (Save Anyway, one link at a time).
    /// - Records `via: note-links` and `from_note` (best-effort provenance;
    ///   the rooms' "saved in Hister" badge comes from presence).
    /// - Unreachable, 429 or 5xx: the outbox, as every save.
    static func saveLink(
        _ link: LinkToSave, label: String?, anyway: Bool, client: HisterClient, outbox: Outbox?,
        smallweb: SmallWebClient? = nil,
        fetch: @Sendable (URL) async throws -> PageFetcher.Fetched = { try await PageFetcher.fetch($0) },
        wait: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> LinkOutcome {
        if SaveLinks.isSmallWeb(link.url) {
            return await saveThroughGateway(link, client: client, smallweb: smallweb, wait: wait)
        }
        guard let url = URL(string: link.url) else { return .failed("That isn't a web address.") }
        if SaveLinks.looksLikeFile(link.url) { return .failed(Self.notAPage) }
        if !(await client.savedLabels(for: [link.url])).isEmpty { return .alreadyInHister }
        // An http:// link is tried as https:// first: the apps' transport
        // security refuses plain http (a short link such as go.example
        // answers on https too), and Hister keeps whatever address it lands on.
        var attempt = url
        if url.scheme?.lowercased() == "http", var secure = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            secure.scheme = "https"
            attempt = secure.url ?? url
        }
        var fetchedPage = try? await fetch(attempt)
        if fetchedPage == nil, attempt != url { fetchedPage = try? await fetch(url) }
        guard let fetched = fetchedPage else {
            if Task.isCancelled { return .cancelled }
            return .failed(url.scheme?.lowercased() == "http"
                ? "Couldn't download this page (it's plain http, which Shiori can't fetch)."
                : "Couldn't download this page.")
        }
        // A file, not a page (a package, an image): nothing for Hister to read.
        guard !fetched.html.isEmpty else { return .failed(Self.notAPage) }
        if fetched.url != link.url, !(await client.savedLabels(for: [fetched.url])).isEmpty { return .alreadyInHister }
        let page = NewPage(
            url: fetched.url, title: fetched.title.isEmpty ? (link.text.isEmpty ? (url.host() ?? link.url) : link.text) : fetched.title,
            html: fetched.html, label: label, via: "note-links", ignoreSkipRules: anyway,
            extra: ["from_note": link.notePath])
        do {
            try await client.add(page)
            return .saved
        } catch .rejected(let rejection) where rejection.status == 406 {
            return .skipped(rejection.reason)
        } catch .rejected(let rejection) {
            return .rejected(rejection.reason)
        } catch .cancelled where Task.isCancelled {
            return .cancelled
        } catch .unreachable, .untrusted, .cancelled {
            return queue(page, in: outbox) == .queued ? .queued : .failed("Hister is out of reach, and the page couldn't be kept for later.")
        } catch .server(let status, _) where status >= 500 || status == 429 {
            return queue(page, in: outbox) == .queued ? .queued : .failed("Hister is out of reach, and the page couldn't be kept for later.")
        } catch {
            return .failed(error.saveMessage)
        }
    }
}

extension Saver {
    /// A gemini:// or gopher:// link: Shiori never fetches it; the small-web
    /// gateway does, through its own network, and saves it as a page read
    /// there would be (its POST /api/save). Never one Hister
    /// holds; skip rules don't apply (they're Hister's, for http); a 429
    /// (20 saves already waiting) is waited out, three times at most.
    static func saveThroughGateway(
        _ link: LinkToSave, client: HisterClient, smallweb: SmallWebClient?,
        wait: @Sendable (Duration) async -> Void
    ) async -> LinkOutcome {
        guard let smallweb else { return .failed("Needs the small-web gateway (Settings → Search).") }
        let forms = Array(Set([link.url, SaveLinks.smallWebKey(link.url)]))
        if !(await client.savedLabels(for: forms)).isEmpty { return .alreadyInHister }
        for attempt in 0..<4 {
            do {
                return .viaGateway(try await smallweb.save(link.url))
            } catch .server(429, _) where attempt < 3 {
                await wait(.seconds(5 * (attempt + 1)))
            } catch .server(400, _) {
                return .rejected("The gateway saves only gemini:// and gopher:// pages.")
            } catch .server(429, _) {
                return .failed("The gateway has too many saves waiting; try again in a minute.")
            } catch .cancelled where Task.isCancelled {
                return .cancelled
            } catch .unreachable, .untrusted, .cancelled {
                return .failed("The small-web gateway is out of reach.")
            } catch {
                return .failed(error.saveMessage)
            }
        }
        return .failed("The gateway has too many saves waiting; try again in a minute.")
    }

    /// The batch's label for a page the gateway saves in the background (it
    /// sets none): once Hister holds it, a few tries apart. False when it
    /// hadn't arrived in time.
    static func labelWhenSaved(
        _ url: String, label: String, client: HisterClient, tries: Int = 6,
        wait: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Bool {
        for attempt in 0..<tries {
            if !(await client.savedLabels(for: [url])).isEmpty {
                return (try? await client.setLabel(label, for: url)) != nil
            }
            if attempt < tries - 1 { await wait(.seconds(3)) }
        }
        return false
    }
}

extension HisterError {
    /// A sentence for the share sheet and shortcuts (the app's fuller
    /// `userMessage` is in ResultsList.swift, out of the extension's reach).
    fileprivate var saveMessage: String {
        switch self {
        case .invalidQuery(let message): message.isEmpty ? "Hister couldn't read that page." : message
        case .server(let status, let message): message.isEmpty ? "The server answered \(status)." : "The server answered \(status): \(message)"
        case .badResponse: "The server's reply didn't make sense."
        default: localizedDescription
        }
    }
}
