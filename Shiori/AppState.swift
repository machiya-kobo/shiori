import HisterKit
import Observation
import SwiftUI
import os

/// App-wide state: settings, the server client, what the server says about
/// labels, and edits made in this session so every list reflects them.
@Observable
final class AppState {
    private enum Keys {
        static let serverURL = "serverURL"
    }

    /// The Hister server; empty until set. Defaults to the build-time URL.
    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: Keys.serverURL)
            SharedSettings.defaults?.set(serverURL, forKey: SharedSettings.Key.serverURL)
            client = makeClient()
            Task { await checkHisterSignIn() }
            rules = Rules(aliases: [:])
            rulesLoaded = false
            capabilities = nil
        }
    }

    /// Settings → Appearance → Text Size: the app's and Safari's results
    /// page's, kept in the App Group so the page (and its own Settings) share it.
    var textSize: TextSize {
        didSet {
            UserDefaults.standard.set(textSize.rawValue, forKey: TextSize.storageKey)
            SharedSettings.defaults?.set(textSize.rawValue, forKey: SharedSettings.Key.textSize)
        }
    }

    /// Settings → This Device → Use This Device's Size: this device's own
    /// text size, over the shared one (which every other device follows).
    /// nil follows the shared size. Never sent; Safari's results page reads
    /// it from the App Group (`textSizeDevice`).
    var deviceTextSize: TextSize? {
        didSet {
            UserDefaults.standard.set(deviceTextSize?.rawValue, forKey: Self.deviceTextSizeKey)
            SharedSettings.defaults?.set(deviceTextSize?.rawValue, forKey: SharedSettings.Key.textSizeDevice)
        }
    }
    static let deviceTextSizeKey = "textSizeDevice"

    /// The size this device draws in: its own when it has one, else the shared one.
    var effectiveTextSize: TextSize { deviceTextSize ?? textSize }

    /// The settings that follow the person: where this device stands with
    /// the account (Settings' state line).
    var prefsState: AccountPrefs.State = .notSignedIn
    private var prefsContactAt: Date?
    private var prefsBusy = false

    /// One contact with the account's settings (AccountPrefs): on coming to
    /// the foreground (at most every 30 s), after signing in and on opening
    /// Settings (`force`). Then the App Group's values are taken up.
    func syncAccountPrefs(force: Bool = false) async {
        guard let base = client?.baseURL else { prefsState = .notSignedIn; return }
        let credential: AccountPrefs.Credential? =
            if let account = histerAccount { .session(account.sessionID) } else if !histerToken.isEmpty { .token(histerToken) } else { nil }
        guard let credential, let defaults = SharedSettings.defaults else { prefsState = .notSignedIn; return }
        if !force, let at = prefsContactAt, Date.now.timeIntervalSince(at) < 30 { return }
        // One contact at a time (the foreground and Settings can ask together).
        guard !prefsBusy else { return }
        prefsBusy = true
        defer { prefsBusy = false }
        prefsContactAt = .now
        prefsState = await AccountPrefs.contact(base: base, credential: credential, defaults: defaults)
        reloadSharedSettings()
    }

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.storageKey)
            // The combined-search page follows the app's theme.
            SharedSettings.defaults?.set(theme.rawValue, forKey: SharedSettings.Key.theme)
        }
    }

    /// Settings → Appearance → Theme: one of the Machiya rooms' ten, per
    /// device. In the App Group so the share extension draws in it too.
    var palette: AppPalette {
        didSet {
            UserDefaults.standard.set(palette.key, forKey: AppPalette.storageKey)
            SharedSettings.defaults?.set(palette.key, forKey: SharedSettings.Key.palette)
        }
    }

    /// Safari searches (via DuckDuckGo) open Shiori's combined results.
    var combinedSearch: Bool {
        didSet {
            SharedSettings.defaults?.set(combinedSearch, forKey: SharedSettings.Key.combinedSearch)
        }
    }

    /// The SearXNG instance for the web half of combined search.
    var searxngURL: String {
        didSet {
            SharedSettings.defaults?.set(searxngURL, forKey: SharedSettings.Key.searxngURL)
        }
    }

    /// How the combined results page looks (Settings → Search from Safari).
    var searchPage: SearchPageOptions {
        didSet {
            searchPage.save(to: SharedSettings.defaults)
            // Off keeps nothing: what was there goes too.
            if oldValue.searchHistory, !searchPage.searchHistory { clearRecentSearches() }
            refreshListSettings()
        }
    }

    /// The label suggestions' hints from the user's own filing (LabelHints).
    var labelHints: LabelHints?
    /// Label New Pages (Settings → AI): its queue, its log, its runs.
    let labeller = AutoLabeller()

    /// Settings → AI: per device (see AISettings).
    var ai: AISettings {
        didSet { ai.save(to: SharedSettings.defaults) }
    }

    /// Bumped by Find (⌘F) on the Mac: the search field takes focus.
    var searchFocusRequests = 0
    private static let log = Logger(subsystem: ShioriID.app, category: "app")

    /// Safari's results page has its own Settings, which write the App
    /// Group: coming to the foreground picks up what changed there.
    func reloadSharedSettings() {
        let shared = SharedSettings.defaults
        if let value = shared?.object(forKey: SharedSettings.Key.combinedSearch) as? Bool, value != combinedSearch {
            combinedSearch = value
        }
        if let stored = shared?.string(forKey: SharedSettings.Key.searxngURL), stored != searxngURL {
            searxngURL = stored
        }
        let page = SearchPageOptions(from: shared)
        if page != searchPage { searchPage = page }
        let pillsNow = PillOrder.clean(shared?.array(forKey: SharedSettings.Key.pills))
        if pillsNow != pills { pills = pillsNow }
        if let raw = shared?.string(forKey: SharedSettings.Key.theme) {
            let fromPage = AppTheme.resolve(raw)
            if fromPage != theme { theme = fromPage }
        }
        if let raw = shared?.string(forKey: SharedSettings.Key.palette) {
            let fromPage = AppPalette.resolve(raw)
            if fromPage != palette { palette = fromPage }
        }
        if let raw = shared?.string(forKey: SharedSettings.Key.textSize) {
            let fromPage = TextSize.resolve(raw)
            if fromPage != textSize { textSize = fromPage }
        }
        reloadRecentSearches()
    }

    /// The last few searches, here and in Safari's results, newest first.
    private(set) var recentSearches: [String] = []

    func recordSearch(_ query: String) {
        SharedSettings.recordSearch(query)
        reloadRecentSearches()
    }

    /// Safari may have added some since.
    func reloadRecentSearches() {
        let latest = SharedSettings.recentSearches()
        if latest != recentSearches { recentSearches = latest }
    }

    func clearRecentSearches() {
        SharedSettings.clearRecentSearches()
        recentSearches = []
    }

    private(set) var client: HisterClient?

    /// The SearXNG instance, for the app's web search.
    var searx: SearxClient? { SearxClient(serverURL: searxngURL) }
    /// The last text's respellings from SearXNG's autocompleter, shared by the lists
    /// that ask at once (Search → All's pages and notes).
    @ObservationIgnored private var suggestionsFor: (text: String, task: Task<[String], Never>)?

    /// SearXNG's autocompleter for `text` (never a web search), for respelling a search that
    /// found nothing; none without web results.
    func webSuggestions(for text: String) async -> [String] {
        guard allSearch.webResults, let searx else { return [] }
        if let cached = suggestionsFor, cached.text == text { return await cached.task.value }
        // The autocompleter's respellings, never a web search (each one counts).
        let task = Task { await searx.autocomplete(text) }
        suggestionsFor = (text, task)
        return await task.value
    }
    private(set) var rules = Rules(aliases: [:])
    /// Sites Hister has pages from, most first: `domain:` completions.
    private(set) var domains: [String] = []
    /// Bumped by File → Add Page… on the Mac: RootView shows the sheet.
    var addPageRequests = 0
    /// Bumped when a search is submitted (Return): the results list takes
    /// the keyboard, for its vi keys.
    /// Kura, where every notes list comes from (Settings → Notes → Kura);
    /// nil without an address: then there are no notes. Signed in to
    /// Machiya when the device is (`machiyaSignIn`).
    var notesKura: KuraClient? {
        KuraClient(serverURL: searchPage.niwaURL, signIn: machiyaSignIn)
    }

    // MARK: Hister's token

    /// Hister's access token (Settings → Server), from the Keychain
    /// (`HisterKeychain`, never UserDefaults): every request to Hister
    /// carries it as `X-Access-Token`; empty, none does. Read at launch
    /// and after every change; never shown back or logged.
    private(set) var histerToken = HisterKeychain.token

    /// Keeps a token (or removes it, when empty) and rebuilds the client.
    /// Nil when kept, else what to tell the person.
    func setHisterToken(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = HisterToken.clean(trimmed)
        if !trimmed.isEmpty && token == nil { return "That isn't a token: it's 8 to 512 characters with no spaces." }
        guard HisterKeychain.save(token ?? "") else { return "The Keychain didn't keep it. Try again." }
        histerToken = HisterKeychain.token
        credentialsChanged()
        return nil
    }

    /// The client for the server, with this device's token and sign-in.
    private func makeClient() -> HisterClient? {
        HisterClient(serverURL: serverURL, token: histerToken, histerSession: histerAccount?.session)
    }

    /// A new credential: a new client, and what came from the old one asked again.
    private func credentialsChanged() {
        client = makeClient()
        rulesLoaded = false
        capabilities = nil
        vaultsReadAt = nil
        cardsLoaded = false
    }

    // MARK: Signing in to Hister (docs/signing-in.md)

    /// This device's own sign-in (Settings → Server → Sign in to Hister):
    /// its Hister session, the sign-in helper's id and who, from the
    /// Keychain (`HisterKeychain`). nil when signed out. Never logged.
    private(set) var histerAccount: HisterAccount.SignedIn? = AppState.storedAccount()

    private static func storedAccount() -> HisterAccount.SignedIn? {
        guard let session = HisterAccount.session(HisterKeychain.session),
            let sid = HisterAccount.sessionID(HisterKeychain.sessionID)
        else { return nil }
        return HisterAccount.SignedIn(session: session, sessionID: sid, username: HisterKeychain.username)
    }

    /// Whether to offer signing in (Settings → Server → Sign in to Hister):
    /// the sign-in helper on the server's host says Hister has users
    /// (`HisterAccount.available`). Checked at launch, on every return to
    /// the foreground and when the server changes; here, not in the view,
    /// whose body is empty until it's true (SwiftUI never runs an empty
    /// view's `.task`: it never showed).
    private(set) var histerSignInOffered = false
    /// Hister's sign-in providers besides the password (`oauthProviders`):
    /// "oidc" puts Sign In with Tailscale first.
    private(set) var histerOAuthProviders: [String] = []

    func checkHisterSignIn() async {
        guard let server = client?.baseURL else {
            histerSignInOffered = false
            histerOAuthProviders = []
            return
        }
        let offered = await HisterAccount.available(server: server)
        if offered != histerSignInOffered { histerSignInOffered = offered }
        let providers = offered ? await HisterAccount.oauthProviders(server: server) : []
        if providers != histerOAuthProviders { histerOAuthProviders = providers }
    }

    /// Keeps a sign-in. Nil when kept, else what to tell the person.
    func keepHisterSignIn(_ signedIn: HisterAccount.SignedIn) -> String? {
        guard HisterKeychain.saveSignIn(session: signedIn.session, sessionID: signedIn.sessionID, username: signedIn.username) else {
            return "The Keychain didn't keep the sign-in. Try again."
        }
        histerAccount = Self.storedAccount()
        credentialsChanged()
        Task { await syncAccountPrefs(force: true) }
        return nil
    }

    /// Signs out through the helper (the Hister session and its id end
    /// everywhere), then forgets both here whatever it answered.
    func signOutOfHister() async {
        if let account = histerAccount, let server = client?.baseURL {
            await HisterAccount.signOut(server: server, sessionID: account.sessionID)
        }
        HisterKeychain.signOut()
        histerAccount = nil
        credentialsChanged()
    }

    // MARK: Machiya sign-in

    /// The Machiya sign-in (Settings → Notes → Sign in to Machiya): the
    /// token and who it signs in as, from the Keychain (`MachiyaKeychain`,
    /// never UserDefaults), read at launch and after every change.
    private(set) var machiyaToken = MachiyaKeychain.token
    private(set) var machiyaPrincipal = MachiyaKeychain.principal

    /// The sign-in for the room clients: the token, and the rooms it may go
    /// to by origin (Kura and Konbini as set in Settings → Notes, less
    /// Hister's and SearXNG's origins). Hister's and SearXNG's clients never
    /// take it. nil when signed out.
    var machiyaSignIn: MachiyaSignIn? {
        let rooms = Machiya.rooms([searchPage.niwaURL, searchPage.konbiniURL], excluding: [serverURL, searxngURL])
        // Signed in through Hister, the rooms get the helper's id (rooms in
        // Hister sign-in mode refuse the identity file's tokens); else the
        // Machiya token, as before.
        if let account = histerAccount, let signIn = MachiyaSignIn(sessionID: account.sessionID, rooms: rooms) { return signIn }
        // Not signed in: the identity token, and Hister's token, which rooms
        // in Hister sign-in mode take (X-Access-Token, read first there).
        return MachiyaSignIn(token: machiyaToken, rooms: rooms, histerToken: histerToken)
    }

    /// Signs in with what was typed: a pairing code (paired against Kura,
    /// `POST /api/pair`) or a pasted token. Nil when signed in, else what
    /// to tell the person.
    func signInToMachiya(_ text: String, device: String) async -> String? {
        switch Machiya.entry(text) {
        case nil:
            return "Type the pairing code from identity pair, or paste a token (mch_… or mcd_…)."
        case .token(let token):
            guard MachiyaKeychain.save(token: token, principal: "") else { return "The Keychain didn't keep it. Try again." }
        case .code(let code):
            let pairing: Machiya.Pairing
            do {
                pairing = try await Machiya.pair(base: searchPage.niwaURL, code: code, device: device)
            } catch {
                return error.message
            }
            guard MachiyaKeychain.save(token: pairing.token, principal: pairing.principal) else {
                return "The Keychain didn't keep it. Try again."
            }
        }
        machiyaChanged()
        return nil
    }

    /// Signs out: the token is deleted from this device (revoke it on the
    /// server with the identity CLI's `device revoke` or `token revoke`).
    func signOutOfMachiya() {
        MachiyaKeychain.signOut()
        machiyaChanged()
    }

    /// Reads the sign-in again, and Kura's vaults and Konbini's cards with it.
    private func machiyaChanged() {
        machiyaToken = MachiyaKeychain.token
        machiyaPrincipal = MachiyaKeychain.principal
        vaultsReadAt = nil
        cardsLoaded = false
    }

    /// The pills over a list or search: Opened only while Show Opened is on.
    var searchScopes: [SearchScope] {
        let available = SearchScope.allCases.filter {
            switch $0 {
            case .opened: searchPage.showOpened
            case .smallweb: smallweb != nil
            case .files: hasLocalFiles
            case .code: hasCodeDocs
            default: true
            }
        }
        // In the order set in Settings → Search → Pills, less the ones
        // switched off (`PillOrder`).
        return PillOrder.ordered(available: available.map(\.pillKey), pills)
            .compactMap { key in available.first { $0.pillKey == key } }
    }

    /// Settings → Search → Pills: their order and which show, shared with
    /// Safari's results page through the App Group (`PillOrder`).
    var pills: [String] {
        didSet { SharedSettings.defaults?.set(pills, forKey: SharedSettings.Key.pills) }
    }

    /// The small-web gateway, while its tab is on (Settings → Search).
    var smallweb: SmallWebClient? {
        searchPage.smallWebTab ? SmallWebClient(serverURL: searchPage.smallwebURL) : nil
    }

    /// A page opened directly in a Gemini app: the gateway fetches and
    /// saves it to Hister, as it does what it shows. Best effort.
    func saveSmallWebPage(_ url: String) async {
        do {
            try await smallweb?.save(url)
        } catch {
            Self.log.notice("Small web page not saved: \(String(describing: error), privacy: .public)")
        }
    }

    var resultsFocusRequests = 0
    /// Bumped by `shiori://settings` (the Safari extension's settings page):
    /// each layout opens its Settings.
    var settingsRequests = 0
    /// Save This Note's Links, asked for by a note's ⋯ menu or a
    /// `shiori://save-links?path=…` / `?folder=…` link (Kura's note view).
    var saveLinksRequest: SaveLinksTarget?
    /// The list last on screen, for Settings → Export & Feed on iOS (the
    /// Mac has them in File, through the `listExport` focused value).
    var shownList: ListExport?
    private var rulesLoaded = false

    /// Pages deleted in this session; lists hide them without refetching.
    private(set) var deletedURLs: Set<String> = []
    /// Labels changed in this session, by page URL.
    private(set) var labelEdits: [String: String] = [:]

    let favicons = FaviconCache()

    /// Konbini's cards, for linking vault notes to their cards.
    private(set) var konbiniCards: [Notes.Card] = []
    private var cardsLoaded = false

    func loadCardsIfNeeded() async {
        await loadVaultsIfNeeded()
        guard !cardsLoaded, !searchPage.konbiniURL.isEmpty else { return }
        cardsLoaded = true
        konbiniCards = await Notes.fetchCards(base: searchPage.konbiniURL, signIn: machiyaSignIn)
    }

    /// Kura's vaults: the default one and the others, for the Notes filter,
    /// another vault's note's place and links, and which vaults are shared
    /// (`Notes.useVaults`). Read again when older than ten minutes, so a
    /// vault made private again counts; a failed read shares none.
    private(set) var kuraVaults: [KuraVault] = []
    private var vaultsReadAt: Date?

    func loadVaultsIfNeeded() async {
        guard let kura = notesKura else {
            Notes.useVaults([])
            return
        }
        if let at = vaultsReadAt, Date.now.timeIntervalSince(at) < 10 * 60 { return }
        vaultsReadAt = .now
        do {
            let found = try await kura.vaults()
            kuraVaults = found
            Notes.useVaults(found)
        } catch {
            Notes.useVaults([])
        }
    }

    /// Which vaults the Notes lists search: "all" (the default), or one
    /// vault's name. Per device, never synced. All's Your Notes is always
    /// the default vault only.
    var notesVault: String = UserDefaults.standard.string(forKey: "notesVault") ?? "all" {
        didSet { UserDefaults.standard.set(notesVault, forKey: "notesVault") }
    }

    /// A work vault by name, for a note's place and Obsidian vault.
    func kuraVault(_ name: String) -> KuraVault? { kuraVaults.first { $0.name == name } }

    /// Where a vault note opens: Obsidian, its Niwa page, its Konbini card.
    struct NoteLinks {
        /// Where the note sits: the vault, then its folders and name.
        var place: String
        var obsidian: URL?
        var niwa: URL?
        var konbini: URL?
    }

    /// Links for a vault note; nil for any other page.
    /// What every result row reads (a note's links and place), apart from
    /// the rest of `searchPage`: Observation tracks whole properties, so
    /// rows reading `searchPage` redrew on every unrelated switch.
    struct NoteSources: Equatable {
        var vault = ""
        var niwaURL = ""
        var konbiniURL = ""
    }
    private(set) var noteSources = NoteSources()

    /// What Search → All reads (how many, and whether the web shows).
    struct AllSearchOptions: Equatable {
        var histerCount = 5
        var vaultCount = 3
        var webResults = true
    }
    private(set) var allSearch = AllSearchOptions()

    /// Copies the two out of `searchPage`, only when they changed.
    private func refreshListSettings() {
        let notes = NoteSources(vault: searchPage.obsidianVault, niwaURL: searchPage.niwaURL, konbiniURL: searchPage.konbiniURL)
        if notes != noteSources { noteSources = notes }
        let all = AllSearchOptions(
            histerCount: searchPage.histerCount, vaultCount: searchPage.vaultCount, webResults: searchPage.webResults)
        if all != allSearch { allSearch = all }
    }

    /// A vault note by its address alone (a Niwa page or Konbini card with
    /// a place in the vault): opened results carry no label.
    func isNotePage(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host()?.lowercased() else { return false }
        let bases = [noteSources.niwaURL, noteSources.konbiniURL].compactMap { URL(string: $0)?.host()?.lowercased() }
        let noteHost = bases.contains(host) || host.hasPrefix("niwa.") || host.hasPrefix("kura.") || host.hasPrefix("konbini.")
        return noteHost && Notes.path(of: url, cards: konbiniCards) != nil
    }

    /// A work vault's note: never sent to Hister, never
    /// given to a model, never cached, exported or put in a feed.
    func isWorkNote(_ url: String) -> Bool { Notes.isPrivateNote(url) }

    // MARK: Files

    /// Hister holds files from the folders it watches (`type:local`): the
    /// Files pill shows only then. Asked with the rules.
    private(set) var hasLocalFiles = false

    func loadLocalFiles() async {
        guard let client else { hasLocalFiles = false; return }
        if let page = try? await client.search(LocalFiles.query(""), limit: 1) { hasLocalFiles = page.total > 0 }
        if let page = try? await client.search(CodeDocs.query(""), limit: 1) { hasCodeDocs = page.total > 0 }
    }

    // MARK: Code

    /// Hister holds your repos (code-import, `metadata.source:code`):
    /// the Code pill shows only then. Asked with the files.
    private(set) var hasCodeDocs = false

    /// A code document: shown on the Code pill only, never labelled,
    /// deleted or given to a model off the device (`AIContent.code`).
    func isCode(_ document: StoredPage) -> Bool { document.code != nil }

    /// A repo's note in the default vault (`Repos/<name>.git.md`), Kura's
    /// reader page for it when Kura has one; asked once per repo a launch.
    @ObservationIgnored private var repoNotes: [String: URL?] = [:]
    func repoNoteURL(repoName: String) async -> URL? {
        if let known = repoNotes[repoName] { return known }
        guard let path = CodeDocs.notePath(repoName: repoName), let kura = notesKura else { return nil }
        let url = await kura.hasNote(path: path) ? Notes.niwaURL(base: searchPage.niwaURL, path: path) : nil
        repoNotes[repoName] = url
        return url
    }

    /// A file from those folders: shown on the Files pill only, opened from
    /// Hister's copy, never recorded, labelled, deleted or given to a model.
    func isLocalFile(_ url: String) -> Bool { LocalFiles.isLocalFile(url) }

    /// Hister's served copy of a file (`/api/file`).
    func servedFile(_ url: String) -> URL? {
        client.flatMap { LocalFiles.servedURL(for: url, server: $0.baseURL) }
    }

    /// The same with Kura asked afresh, for anything about another vault's
    /// note that goes to Hister or a model (a shared vault may be private
    /// by now; unanswered, it is). The default vault's notes ask nothing.
    func isWorkNoteNow(_ url: String) async -> Bool {
        await Notes.isPrivateNoteNow(url, kura: notesKura)
    }

    func noteLinks(for document: StoredPage) -> NoteLinks? {
        guard label(of: document) == Notes.label || document.label == Notes.label,
            let path = Notes.path(of: document.url, cards: konbiniCards)
        else { return nil }
        let host = URL(string: document.url)?.host() ?? ""
        let page = URL(string: document.url)
        let crumbs = path.replacing(/\.md$/, with: "").split(separator: "/").joined(separator: " › ")
        // A work vault's note: its own vault's name and Obsidian vault, read
        // in Kura, never a Konbini card.
        if let name = Notes.otherVault(of: document.url) {
            let vault = kuraVault(name)
            return NoteLinks(
                place: "\(vault?.title ?? name) › \(crumbs)",
                obsidian: Notes.obsidianURL(vault: vault?.obsidian ?? name, path: path),
                niwa: page,
                konbini: nil)
        }
        return NoteLinks(
            place: "\(noteSources.vault) › \(crumbs)",
            obsidian: Notes.obsidianURL(vault: noteSources.vault, path: path),
            niwa: Notes.readerURL(page: document.url, base: noteSources.niwaURL, path: path),
            konbini: Notes.konbiniURL(base: noteSources.konbiniURL, path: path, cards: konbiniCards)
                ?? (host.hasPrefix("konbini.") ? page : nil))
    }

    /// Pages waiting to be sent: from the share sheet and shortcuts (the
    /// outbox, which the app sends) and from Safari (the extension's queue,
    /// which only browsing can send).
    struct Waiting: Equatable {
        var outbox = Outbox.Status(count: 0, oldest: nil)
        var safari = 0
        var safariOldest: Date?
        var safariReportedAt: Date?
    }

    private(set) var waiting = Waiting()
    private(set) var isSending = false

    private var outbox: Outbox? { SharedSettings.outboxDirectory.map(Outbox.init(directory:)) }
    /// Where a save waits when Hister is out of reach (Save This Note's Links).
    var saveOutbox: Outbox? { outbox }

    func refreshWaiting() {
        var next = Waiting(outbox: outbox?.status() ?? .init(count: 0, oldest: nil))
        if let report = SharedSettings.defaults?.dictionary(forKey: SharedSettings.Key.extensionQueue) {
            next.safari = report["count"] as? Int ?? 0
            next.safariOldest = (report["oldest"] as? Double).map { Date(timeIntervalSince1970: $0) }
            next.safariReportedAt = (report["reportedAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        }
        waiting = next
    }

    /// Sends what the share sheet and shortcuts queued.
    func sendWaiting() async {
        guard !isSending, let outbox, let client else {
            refreshWaiting()
            return
        }
        isSending = true
        let result = await outbox.drain(using: client)
        isSending = false
        sendStopped = if case .stopped = result { true } else { false }
        refreshWaiting()
    }

    /// The last Send Now (or foreground send) stopped: Hister didn't answer.
    private(set) var sendStopped = false

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        let fallback = (bundle.object(forInfoDictionaryKey: "ShioriDefaultServerURL") as? String) ?? ""
        let stored = defaults.string(forKey: Keys.serverURL)
        serverURL = stored ?? fallback
        // The App Group's copy first: Safari's results page can change it.
        theme = AppTheme.resolve(
            SharedSettings.defaults?.string(forKey: SharedSettings.Key.theme)
                ?? defaults.string(forKey: AppTheme.storageKey))
        textSize = TextSize.resolve(
            SharedSettings.defaults?.string(forKey: SharedSettings.Key.textSize)
                ?? defaults.string(forKey: TextSize.storageKey))
        palette = AppPalette.resolve(
            SharedSettings.defaults?.string(forKey: SharedSettings.Key.palette)
                ?? defaults.string(forKey: AppPalette.storageKey))
        deviceTextSize = defaults.string(forKey: Self.deviceTextSizeKey).map(TextSize.resolve)
        client = HisterClient(serverURL: stored ?? fallback, token: HisterKeychain.token, histerSession: HisterKeychain.session)

        let shared = SharedSettings.defaults
        pills = PillOrder.clean(shared?.array(forKey: SharedSettings.Key.pills))
        combinedSearch = shared?.object(forKey: SharedSettings.Key.combinedSearch) as? Bool ?? true
        let defaultSearxng = (bundle.object(forInfoDictionaryKey: "ShioriDefaultSearxngURL") as? String) ?? ""
        searxngURL = shared?.string(forKey: SharedSettings.Key.searxngURL) ?? defaultSearxng
        ai = AISettings(from: shared)
        searchPage = SearchPageOptions(from: shared)
        searchPage.save(to: shared)
        refreshListSettings()
        recentSearches = SharedSettings.recentSearches(in: shared)
        // Publish the effective values once, so the extension sees them even
        // before anything is changed here.
        shared?.set(combinedSearch, forKey: SharedSettings.Key.combinedSearch)
        shared?.set(searxngURL, forKey: SharedSettings.Key.searxngURL)
        shared?.set(theme.rawValue, forKey: SharedSettings.Key.theme)
        shared?.set(textSize.rawValue, forKey: SharedSettings.Key.textSize)
        shared?.set(serverURL, forKey: SharedSettings.Key.serverURL)
    }

    /// The server's aliases and labels, fetched once per server.
    /// Again, even if loaded: coming back to the app (collections may have
    /// been edited in Hister's web UI meanwhile) and pull to refresh.
    func reloadRules() async {
        rulesLoaded = false
        await loadRulesIfNeeded()
    }

    func loadRulesIfNeeded() async {
        guard !rulesLoaded, let client else { return }
        do {
            let fetched = try await client.rules()
            rules = fetched
            rulesLoaded = true
            // The share sheet's label picker works from this copy.
            SharedSettings.defaults?.set(fetched.labels, forKey: SharedSettings.Key.labels)
            if let found = try? await client.topDomains() { domains = found }
            await loadLocalFiles()
        } catch .cancelled {
        } catch {
            // Tried again on the next screen that needs them; say why here.
            Self.log.notice("Rules not loaded: \(error.userMessage, privacy: .public)")
        }
    }

    func label(of document: StoredPage) -> String {
        labelEdits[document.url] ?? document.label
    }

    func setLabel(_ label: String, for document: StoredPage) async throws(HisterError) {
        try await setLabel(label, url: document.url)
    }

    /// By address: automatic labelling and its Undo hold no StoredPage.
    func setLabel(_ label: String, url: String) async throws(HisterError) {
        guard let client else { throw .unreachable }
        // Hister never has a private vault's note.
        guard !(await isWorkNoteNow(url)), !isLocalFile(url) else { throw .notFound }
        try await client.setLabel(label, for: url)
        // Bounded: the lists refetch long before this many edits matter.
        if labelEdits.count >= 2000 { labelEdits.removeAll() }
        labelEdits[url] = label
    }

    func delete(_ document: StoredPage) async throws(HisterError) {
        guard let client else { throw .unreachable }
        guard !(await isWorkNoteNow(document.url)), !isLocalFile(document.url) else { throw .notFound }
        try await client.delete(url: document.url)
        if deletedURLs.count >= 2000 { deletedURLs.removeAll() }
        deletedURLs.insert(document.url)
    }

    // MARK: Delete with Undo

    /// A delete waiting out its Undo: the page is gone from every list at
    /// once, and from Hister when the toast's time is up. Hister can't
    /// bring a deleted page back, so the undo is the wait, not a restore.
    struct PendingDelete: Identifiable, Equatable {
        let id = UUID()
        let document: StoredPage
    }

    private(set) var pendingDelete: PendingDelete?
    /// Why the last delete failed (it's back in its list).
    var deleteFailure: String?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    static let undoWindow = Duration.seconds(6)

    /// Every delete in the app goes this way: swipe, menu, the page's ⋯, dd.
    func deleteWithUndo(_ document: StoredPage) {
        // Hister never has a work note, and must never be sent one's address.
        guard !isWorkNote(document.url) else { return }
        commitPendingDelete()
        deletedURLs.insert(document.url)
        let pending = PendingDelete(document: document)
        pendingDelete = pending
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            await self?.finish(pending)
        }
    }

    func undoDelete() {
        guard let pending = pendingDelete else { return }
        pendingTask?.cancel()
        pendingDelete = nil
        deletedURLs.remove(pending.document.url)
    }

    /// Sends a waiting delete now: another delete started, or the app is
    /// going to the background (a delete is what was asked for).
    func commitPendingDelete() {
        guard let pending = pendingDelete else { return }
        pendingTask?.cancel()
        pendingDelete = nil
        Task { await finish(pending) }
    }

    private func finish(_ pending: PendingDelete) async {
        if pendingDelete?.id == pending.id { pendingDelete = nil }
        do {
            try await delete(pending.document)
        } catch {
            deletedURLs.remove(pending.document.url)
            deleteFailure = error.userMessage
        }
    }

    // MARK: Opened results (Settings → Remember What You Open)

    /// Tells Hister `document` was opened from a search for `query`, so it
    /// ranks it first the next time. Not for the Library's `*`, and quietly
    /// best effort: nothing waits on it.
    func recordOpened(_ document: StoredPage, query: String) {
        recordOpened(url: document.url, title: document.title, query: query)
    }

    func recordOpened(url: String, title: String, query: String) {
        // Never a work note's address or title to Hister.
        // Never a file's: what you open there stays here.
        guard searchPage.rememberOpened, let client, Self.remembers(query), !isWorkNote(url), !isLocalFile(url) else { return }
        Task {
            // Another vault's note: Kura asked afresh first.
            guard !(await self.isWorkNoteNow(url)) else { return }
            do {
                try await client.recordOpened(url: url, title: title, query: query)
            } catch {
                Self.log.notice("Opened result not recorded: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func forgetOpened(_ url: String, query: String) async throws(HisterError) {
        guard let client else { throw .unreachable }
        try await client.forgetOpened(url: url, query: query)
    }

    /// A real search, not a browse (the Library's `*`, a note list).
    static func remembers(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && q != "*"
    }

    // MARK: What the server can do

    /// Found once per server: whether meaning-based search is set up.
    private(set) var capabilities: ServerCapabilities?

    func loadCapabilitiesIfNeeded() async {
        guard capabilities == nil, let client else { return }
        capabilities = try? await client.capabilities()
    }

    /// Meaning-based search is on in Settings and set up on the server.
    var semanticOn: Bool { searchPage.semanticSearch && capabilities?.semantic == true }
}

/// Favicons by key, fetched once each and kept for the session.
@MainActor
final class FaviconCache {
    /// NSCache: bounded, and emptied under memory pressure (a Mac window
    /// left open for days would otherwise keep every icon it ever showed).
    private let images: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 300
        return cache
    }()
    private var missing: Set<String> = []
    private var inFlight: [String: Task<Fetch, Never>] = [:]

    private enum Fetch {
        case image(PlatformImage)
        /// The server has no usable icon; don't ask again this session.
        case none
        /// Unreachable or similar; worth another try later.
        case failed
    }

    func image(for key: String, using client: HisterClient?) async -> PlatformImage? {
        guard !key.isEmpty, let client else { return nil }
        if let image = images.object(forKey: key as NSString) { return image }
        if missing.contains(key) { return nil }
        let task = inFlight[key] ?? Task { () -> Fetch in
            do {
                let data = try await client.favicon(key: key)
                return PlatformImage(data: data).map(Fetch.image) ?? .none
            } catch HisterError.notFound {
                return .none
            } catch {
                return .failed
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        switch result {
        case .image(let image):
            images.setObject(image, forKey: key as NSString)
            return image
        case .none:
            if missing.count > 2000 { missing.removeAll() }
            missing.insert(key)
            return nil
        case .failed:
            return nil
        }
    }
}

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#else
import AppKit
typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#endif

/// The combined results page's options, shared with the Safari extension.
/// Each source can be switched off on its own: Hister and the vault each
/// in General and as a tab, and the web results.
struct SearchPageOptions: Equatable {
    static let counts = [3, 5, 10, 20]

    var showInfobox = true
    var showRelated = true
    var aiAnswer = true
    var showThumbnails = true
    var histerInGeneral = true
    var histerTab = true
    var histerCount = 5
    var vaultInGeneral = true
    var vaultTab = true
    var vaultCount = 3
    var webResults = true
    var searchHistory = true
    var previewPane = true
    var previewImages = true
    /// Tell Hister which result you opened for a search, so it ranks it
    /// first next time (and show those first).
    var rememberOpened = true
    /// The filter bar (site, date, visits…) on search results.
    var searchFilters = true
    /// Meaning-based matches mixed in, where the server has them set up.
    var semanticSearch = false
    /// A run of pages from one site shows its first, then "N more".
    var foldRepeats = true
    /// Pages you opened, shown (lifted into Your Pages, "You Opened", the
    /// Opened pill); off, they're left out and not counted. Off by default:
    /// they mostly cluttered things.
    var showOpened = false
    /// "tint", "solid", "bar" or "none": how your pages, notes and opened pages
    /// stand apart in lists (`ResultBar`).
    var resultStyle = "tint"
    /// Set once Result Style has been put back to Tint (0.5.0).
    static let resultStyleResetKey = "resultStyleTintReset"
    /// Labels and collections lead the search field's suggestions.
    var labelSuggestions = true
    /// The user's NewsBlur, for "Subscribe in NewsBlur" (opened in the browser).
    var newsBlurURL = ""
    /// Obsidian matches vault names exactly. The default is the build's
    /// `SHIORI_OBSIDIAN_VAULT` (local.yml), if a build sets one; empty,
    /// notes link to Kura only until Settings → Notes names one.
    var obsidianVault = ""
    var niwaURL = ""
    var konbiniURL = ""
    /// The small-web gateway (Gemini and Gopher search), its tab, and
    /// where a result opens: "gateway" (its HTML page, the default) or
    /// "direct" (the gemini:// link, for an app such as Lagrange).
    var smallwebURL = ""
    var smallWebTab = true
    var smallWebOpen = "gateway"

    init() {}

    init(from defaults: UserDefaults?, bundle: Bundle = .main) {
        niwaURL = (bundle.object(forInfoDictionaryKey: "ShioriDefaultNiwaURL") as? String) ?? ""
        konbiniURL = (bundle.object(forInfoDictionaryKey: "ShioriDefaultKonbiniURL") as? String) ?? ""
        smallwebURL = (bundle.object(forInfoDictionaryKey: "ShioriDefaultSmallwebURL") as? String) ?? ""
        obsidianVault = (bundle.object(forInfoDictionaryKey: "ShioriDefaultObsidianVault") as? String) ?? ""
        guard let defaults else { return }
        typealias K = SharedSettings.Key
        func flag(_ key: String, _ value: inout Bool) {
            if defaults.object(forKey: key) != nil { value = defaults.bool(forKey: key) }
        }
        func count(_ key: String, _ value: inout Int) {
            let n = defaults.integer(forKey: key)
            if Self.counts.contains(n) { value = n }
        }
        flag(K.showInfobox, &showInfobox)
        flag(K.showRelated, &showRelated)
        flag(K.aiAnswer, &aiAnswer)
        flag(K.showThumbnails, &showThumbnails)
        // The old "Hister Tab Only" choice means: not in General.
        if defaults.string(forKey: K.histerPlacement) == "tab" { histerInGeneral = false }
        flag(K.histerInGeneral, &histerInGeneral)
        flag(K.histerTab, &histerTab)
        count(K.histerCount, &histerCount)
        flag(K.vaultInGeneral, &vaultInGeneral)
        flag(K.vaultTab, &vaultTab)
        count(K.vaultCount, &vaultCount)
        flag(K.webResults, &webResults)
        flag(K.searchHistory, &searchHistory)
        flag(K.previewPane, &previewPane)
        flag(K.previewImages, &previewImages)
        flag(K.rememberOpened, &rememberOpened)
        flag(K.searchFilters, &searchFilters)
        flag(K.semanticSearch, &semanticSearch)
        flag(K.foldRepeats, &foldRepeats)
        flag(K.showOpened, &showOpened)
        // Tint, once, whatever was saved before (the user’s call, 0.5.0); a
        // style chosen after that is kept.
        if !defaults.bool(forKey: Self.resultStyleResetKey) {
            defaults.set("tint", forKey: K.resultStyle)
            defaults.set(true, forKey: Self.resultStyleResetKey)
        }
        if let v = defaults.string(forKey: K.resultStyle), SharedSettings.resultStyles.contains(v) { resultStyle = v }
        flag(K.labelSuggestions, &labelSuggestions)
        if let v = defaults.string(forKey: K.newsBlurURL) { newsBlurURL = v }
        if let v = defaults.string(forKey: K.obsidianVault), !v.isEmpty { obsidianVault = v }
        if let v = defaults.string(forKey: K.niwaURL) { niwaURL = v }
        if let v = defaults.string(forKey: K.konbiniURL) { konbiniURL = v }
        if let v = defaults.string(forKey: K.smallwebURL), !v.isEmpty { smallwebURL = v }
        flag(K.smallWebTab, &smallWebTab)
        if let v = defaults.string(forKey: K.smallWebOpen), SharedSettings.smallWebOpens.contains(v) { smallWebOpen = v }
    }

    func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        typealias K = SharedSettings.Key
        defaults.set(showInfobox, forKey: K.showInfobox)
        defaults.set(showRelated, forKey: K.showRelated)
        defaults.set(aiAnswer, forKey: K.aiAnswer)
        defaults.set(showThumbnails, forKey: K.showThumbnails)
        defaults.set(histerInGeneral, forKey: K.histerInGeneral)
        defaults.set(histerTab, forKey: K.histerTab)
        defaults.set(histerCount, forKey: K.histerCount)
        defaults.set(vaultInGeneral, forKey: K.vaultInGeneral)
        defaults.set(vaultTab, forKey: K.vaultTab)
        defaults.set(vaultCount, forKey: K.vaultCount)
        defaults.set(webResults, forKey: K.webResults)
        defaults.set(searchHistory, forKey: K.searchHistory)
        defaults.set(previewPane, forKey: K.previewPane)
        defaults.set(previewImages, forKey: K.previewImages)
        defaults.set(rememberOpened, forKey: K.rememberOpened)
        defaults.set(searchFilters, forKey: K.searchFilters)
        defaults.set(semanticSearch, forKey: K.semanticSearch)
        defaults.set(foldRepeats, forKey: K.foldRepeats)
        defaults.set(showOpened, forKey: K.showOpened)
        defaults.set(resultStyle, forKey: K.resultStyle)
        defaults.set(labelSuggestions, forKey: K.labelSuggestions)
        defaults.set(newsBlurURL, forKey: K.newsBlurURL)
        defaults.removeObject(forKey: K.pageTextSize)
        defaults.set(obsidianVault, forKey: K.obsidianVault)
        defaults.set(niwaURL, forKey: K.niwaURL)
        defaults.set(konbiniURL, forKey: K.konbiniURL)
        defaults.set(smallwebURL, forKey: K.smallwebURL)
        defaults.set(smallWebTab, forKey: K.smallWebTab)
        defaults.set(smallWebOpen, forKey: K.smallWebOpen)
        defaults.removeObject(forKey: K.histerPlacement)
    }
}
