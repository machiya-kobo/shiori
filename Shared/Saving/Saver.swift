import Foundation
import HisterKit

/// Saves one page to Hister: from the share sheet, the Save shortcut, or
/// the app. If Hister can't be reached the page waits in the App Group's
/// outbox, stamped with the time it was saved, and the app sends it later.
nonisolated enum Saver {
    enum Outcome: Sendable, Equatable {
        case saved
        case queued
        /// Kept on this device for a reason of the site's own (it was busy):
        /// downloaded and sent later, as the outbox drains.
        case waiting(String)
        case rejected(String)
        case failed(String)
        /// The user cancelled: nothing was saved, and nothing waits.
        case cancelled

        /// Saved, or kept to send later: the sheet can close.
        var isKept: Bool {
            switch self {
            case .saved, .queued, .waiting: true
            default: false
            }
        }

        var message: String {
            switch self {
            case .saved: "Saved to Hister."
            case .queued: "Hister is out of reach. Saved on this device; it will be sent when Hister is back."
            case .waiting(let reason): reason
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
        // Hister's token from the Keychain, when this device has one.
        guard let client = HisterClient(serverURL: serverURL, token: HisterKeychain.token, histerSession: HisterKeychain.session) else {
            return .failed("Set your Hister server in Shiori's Settings first.")
        }
        return await save(input, label: label, via: via, client: client, outbox: SharedSettings.outboxDirectory.map(Outbox.init))
    }

    /// The same, with the server and the outbox given (the tests' way in).
    static func save(_ input: Input, label: String?, via: String, client: HisterClient, outbox: Outbox?,
                     fetch: @Sendable (URL) async throws -> PageFetcher.Fetched = { try await PageFetcher.fetch($0) }) async -> Outcome {
        // A web page only: never a file:// or any other scheme's address.
        guard let scheme = input.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .rejected("Only web pages (http or https) can be saved.")
        }
        // Another vault's note never, not even fetched (fail closed).
        if Notes.otherVault(of: input.url.absoluteString) != nil {
            return .rejected("A note from another vault stays in Kura.")
        }
        var page = NewPage(
            url: input.url.absoluteString, title: input.title ?? "", html: input.html, text: input.text,
            label: label, via: via)
        if (page.html ?? "").isEmpty && (page.text ?? "").isEmpty {
            do {
                // An http:// link is tried as https:// first, as Save This Note's Links does.
                let fetched = try await PageFetcher.fetchPreferringHTTPS(input.url, fetch: fetch)
                page.url = fetched.url
                page.html = fetched.html
                if page.title.isEmpty { page.title = fetched.title }
            } catch let error as PageFetcher.SiteError {
                // The site's own error page is never saved as the page. A busy
                // site: the link waits, and the outbox downloads it later.
                guard error.isTemporary else { return .rejected(error.message) }
                if page.title.isEmpty { page.title = input.url.host() ?? input.url.absoluteString }
                let kept = queue(page, in: outbox)
                return kept == .queued ? .waiting("The site is busy (it answered \(error.status)). Saved on this device; it will be tried again later.") : kept
            } catch {
                if Task.isCancelled { return .cancelled }
                if (error as? URLError)?.code == .appTransportSecurityRequiresSecureConnection {
                    return .failed("Couldn't download this page (it's plain http, which Shiori can't fetch).")
                }
                // Out of reach: kept as its link and downloaded when the
                // outbox drains, never sent to Hister as an empty page.
                if page.title.isEmpty { page.title = input.url.host() ?? input.url.absoluteString }
                let kept = queue(page, in: outbox)
                return kept == .queued ? .waiting("Couldn't download the page just now. Saved on this device; it will be tried again later.") : kept
            }
        }
        if page.title.isEmpty { page.title = input.url.host() ?? input.url.absoluteString }
        // Another vault's note, shared or not, never from here (after
        // redirects too): whether Kura still shares it would need asking
        // first (fail closed).
        if Notes.otherVault(of: input.url.absoluteString) != nil || Notes.otherVault(of: page.url) != nil {
            return .rejected("A note from another vault stays in Kura.")
        }

        do {
            try await client.add(page)
            return .saved
        } catch .rejected(let rejection) {
            return .rejected(rejection.reason)
        } catch .cancelled where Task.isCancelled {
            // The user cancelled (not a dropped connection): don't queue it.
            return .cancelled
        } catch .unreachable, .untrusted, .plainHTTP, .cancelled {
            return queue(page, in: outbox)
        } catch .server(let status, _) where status >= 500 || status == 429 {
            return queue(page, in: outbox)
        } catch .signedOut {
            // Kept until this device signs in again (the outbox waits too):
            // said as that, not as Hister being out of reach.
            let kept = queue(page, in: outbox)
            return kept == .queued ? .waiting(Self.waitingForSignIn) : kept
        } catch {
            return .failed(error.saveMessage)
        }
    }

    static let waitingForSignIn = "Hister wants you signed in. Saved on this device; it will be sent once you sign in (Settings → Account)."

    private static func queue(_ page: NewPage, in outbox: Outbox?) -> Outcome {
        guard let outbox else {
            return .failed("Hister is out of reach, and the page couldn't be kept for later.")
        }
        do {
            try outbox.enqueue(page)
            return .queued
        } catch is Outbox.Full {
            return .failed("Too many pages are waiting to be sent, so this one wasn't kept.")
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

    /// Hister's exact answer before a save (`HisterClient.holds`): held,
    /// or why it couldn't be asked. Nil means it doesn't hold the page.
    /// A lookup that fails never reads as "not held": `api/add` would
    /// replace a stored page's metadata.
    private static func heldOutcome(_ url: String, client: HisterClient) async -> LinkOutcome? {
        do {
            return try await client.holds(url) ? .alreadyInHister : nil
        } catch .cancelled where Task.isCancelled {
            return .cancelled
        } catch .signedOut {
            return .failed("Hister wants you signed in: Settings → Account.")
        } catch .plainHTTP {
            return .failed(HisterError.plainHTTP.saveMessage)
        } catch .unreachable, .untrusted, .cancelled {
            return .failed("Hister is out of reach, so this couldn't be checked: try again later.")
        } catch {
            return .failed("Couldn't ask Hister whether it has this page.")
        }
    }

    /// The same for several forms of one address, in one search where
    /// they fit in one (`heldLabels`), else one by one (`holds`).
    private static func heldOutcome(forms: [String], client: HisterClient) async -> LinkOutcome? {
        let searchable = forms.filter(HisterClient.lookupTakes)
        if !searchable.isEmpty {
            do {
                if !(try await client.heldLabels(for: searchable)).isEmpty { return .alreadyInHister }
            } catch .cancelled where Task.isCancelled {
                return .cancelled
            } catch .signedOut {
                return .failed("Hister wants you signed in: Settings → Account.")
            } catch .unreachable, .untrusted, .cancelled {
                return .failed("Hister is out of reach, so this couldn't be checked: try again later.")
            } catch {
                return .failed("Couldn't ask Hister whether it has this page.")
            }
        }
        for form in forms where !HisterClient.lookupTakes(form) {
            if let held = await heldOutcome(form, client: client) { return held }
        }
        return nil
    }

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
        if let held = await heldOutcome(link.url, client: client) { return held }
        // An http:// link is tried as https:// first (`fetchPreferringHTTPS`),
        // and Hister keeps whatever address it lands on.
        var fetchedPage: PageFetcher.Fetched?
        do {
            fetchedPage = try await PageFetcher.fetchPreferringHTTPS(url, fetch: fetch)
        } catch let error as PageFetcher.SiteError {
            // The site's own error page (404, a bot check) is never saved as the page.
            return .failed(error.message)
        } catch {}
        guard let fetched = fetchedPage else {
            if Task.isCancelled { return .cancelled }
            return .failed(url.scheme?.lowercased() == "http"
                ? "Couldn't download this page (it's plain http, which Shiori can't fetch)."
                : "Couldn't download this page.")
        }
        // A file, not a page (a package, an image): nothing for Hister to read.
        guard !fetched.html.isEmpty else { return .failed(Self.notAPage) }
        if fetched.url != link.url, let held = await heldOutcome(fetched.url, client: client) { return held }
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
        } catch .unreachable, .untrusted, .plainHTTP, .cancelled {
            let kept = queue(page, in: outbox)
            return kept == .queued ? .queued : .failed(kept.message)
        } catch .server(let status, _) where status >= 500 || status == 429 {
            let kept = queue(page, in: outbox)
            return kept == .queued ? .queued : .failed(kept.message)
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
        if let held = await heldOutcome(forms: forms, client: client) { return held }
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
        case .plainHTTP: "This address uses http://, and Shiori needs https://."
        case .signedOut: "Hister wants you to sign in: sign in again in Shiori's Settings → Account."
        default: localizedDescription
        }
    }
}
