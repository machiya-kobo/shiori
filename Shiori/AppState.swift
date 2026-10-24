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

    /// Settings → Appearance → Use This Device's Size: this device's own
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
        guard client?.baseURL != nil else { prefsState = .notSignedIn; return }
        if !force, let at = prefsContactAt, Date.now.timeIntervalSince(at) < 30 { return }
        // One contact at a time (the foreground and Settings can ask together).
        guard !prefsBusy else { return }
        prefsBusy = true
        defer { prefsBusy = false }
        // Another server or sign-in while a contact was out (signing in asks
        // for one, which the busy check would have dropped): its state is
        // the old account's, so the new one is asked again.
        while true {
            guard let base = client?.baseURL else { prefsState = .notSignedIn; return }
            let credential: AccountPrefs.Credential? =
                if let account = histerAccount { .session(account.sessionID) } else if !histerToken.isEmpty { .token(histerToken) } else { nil }
            guard let credential, let defaults = SharedSettings.defaults else { prefsState = .notSignedIn; return }
            let generation = clientGeneration
            prefsContactAt = .now
            let state = await AccountPrefs.contact(base: base, credential: credential, defaults: defaults)
            guard generation != clientGeneration else {
                prefsState = state
                reloadSharedSettings()
                return
            }
        }
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

    /// How the combined results page looks (Settings → Results, and Safari → Shiori Search).
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
    /// Bumped when the account changes: hints read for the one before
    /// aren't kept.
    @ObservationIgnored private(set) var labelAccount = 0
    @ObservationIgnored private var labelOwner: (server: String, user: String?)?
    /// Label New Pages (Settings → AI): its queue, its log, its runs.
    let labeller = AutoLabeller()

    /// Settings → AI: per device (see AISettings).
    var ai: AISettings {
        didSet { ai.save(to: SharedSettings.defaults) }
    }

    /// Bumped by Find (⌘F) on the Mac: the search field takes focus.
    var searchFocusRequests = 0
    /// Bumped by View → Reload (⌘R): the list on screen and the rules load
    /// again (`pullToRefresh`'s action).
    var reloadRequests = 0
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

    private(set) var client: HisterClient? {
        didSet { clientGeneration &+= 1 }
    }
    /// Bumped with every new client (another server or credential): an
    /// answer that set off under the old one is dropped, not applied.
    @ObservationIgnored private var clientGeneration = 0
    /// The same for the rooms (Kura, Konbini): bumped when the sign-in they
    /// carry changes.
    @ObservationIgnored private var roomsGeneration = 0

    /// The SearXNG instance, for the app's web search.
    var searx: SearxClient? {
        var client = SearxClient(serverURL: searxngURL)
        client?.safeSearch = searchPage.safeSearch
        return client
    }
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
    /// Bumped by File → Add Page… on the Mac: RootView shows the sheet.
    var addPageRequests = 0
    /// Bumped when a search is submitted (Return): the results list takes
    /// the keyboard, for its vi keys.
    /// Kura, where every notes list comes from (Settings → Search → Notes → Kura);
    /// nil without an address: then there are no notes. Signed in to
    /// Machiya when the device is (`machiyaSignIn`).
    var notesKura: KuraClient? {
        KuraClient(serverURL: searchPage.niwaURL, signIn: machiyaSignIn)
    }

    /// Where notes come from (Settings → Notes → Notes From): the person's
    /// choice, else Kura when one is set up, else Hister (`NotesSource`).
    /// From Hister, only the default vault's notes (`Notes.histerNoteShown`).
    var notesFrom: NotesSource {
        NotesSource.effective(choice: searchPage.notesSource, kuraConfigured: notesKura != nil)
    }

    /// Kura, when notes come from it; nil when they come from Hister.
    var notesKuraInUse: KuraClient? { notesFrom == .kura ? notesKura : nil }

    // MARK: Hister's token

    /// Hister's access token (Settings → Account), from the Keychain
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
        let before = histerToken
        histerToken = HisterKeychain.token
        // Another token may be another account: its copies aren't this one's.
        if histerToken != before { forgetAccountCopies() }
        credentialsChanged()
        return nil
    }

    /// What this device kept for reading offline, summaries and the network
    /// cache came through the old credential: they go with it.
    private func forgetAccountCopies() {
        OfflineStore.clear()
        Task { await SpotlightIndex.clear() }
        SummaryCache.clear()
        HisterClient.clearCache()
    }

    /// Label New Pages' state and the label hints belong to one account:
    /// another server, or another user signed in, starts them over
    /// (`AutoLabeller.adopt`); signing out, or back in as the same user,
    /// keeps them. Labels edited here go with them. Checked at launch, on
    /// signing in, and once a server's rules arrive (an address that
    /// answers, not one half-typed or mistyped).
    func labellingAccountChanged() {
        let server = client?.baseURL.absoluteString ?? serverURL
        let user = histerAccount.map(\.username).flatMap { $0.isEmpty ? nil : $0 }
        if LabellingOwner.changed(fromServer: labelOwner?.server, user: labelOwner?.user, toServer: server, user: user) {
            labelHints = nil
            labelEdits = [:]
            labelAccount += 1
        }
        labelOwner = (server, user ?? labelOwner?.user)
        labeller.adopt(server: server, user: user)
    }

    /// The client for the server, with this device's token and sign-in.
    private func makeClient() -> HisterClient? {
        HisterClient(serverURL: serverURL, token: histerToken, histerSession: histerAccount?.session)
    }

    /// A new credential: a new client, and what came from the old one asked again.
    private func credentialsChanged() {
        client = makeClient()
        roomsGeneration &+= 1
        rulesLoaded = false
        capabilities = nil
        vaultsNextRead = nil
        cardsNextRead = nil
    }

    // MARK: Signing in to Hister (docs/signing-in.md)

    /// This device's own sign-in (Settings → Account → Sign in to Hister):
    /// its Hister session, the sign-in helper's id and who, from the
    /// Keychain (`HisterKeychain`). nil when signed out. Never logged.
    private(set) var histerAccount: HisterAccount.SignedIn? = AppState.storedAccount()

    private static func storedAccount() -> HisterAccount.SignedIn? {
        guard let session = HisterAccount.session(HisterKeychain.session),
            let sid = HisterAccount.sessionID(HisterKeychain.sessionID)
        else { return nil }
        return HisterAccount.SignedIn(session: session, sessionID: sid, username: HisterKeychain.username)
    }

    /// Whether to offer signing in (Settings → Account → Sign in to Hister):
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
        // Answers about a server no longer set are dropped (its check runs anew).
        let generation = clientGeneration
        let offered = await HisterAccount.available(server: server)
        guard generation == clientGeneration else { return }
        if offered != histerSignInOffered { histerSignInOffered = offered }
        let providers = offered ? await HisterAccount.oauthProviders(server: server) : []
        guard generation == clientGeneration else { return }
        if providers != histerOAuthProviders { histerOAuthProviders = providers }
    }

    /// Keeps a sign-in. Nil when kept, else what to tell the person.
    func keepHisterSignIn(_ signedIn: HisterAccount.SignedIn) -> String? {
        guard HisterKeychain.saveSignIn(session: signedIn.session, sessionID: signedIn.sessionID, username: signedIn.username) else {
            return "The Keychain didn't keep the sign-in. Try again."
        }
        let before = histerAccount?.username
        histerAccount = Self.storedAccount()
        if before != signedIn.username { forgetAccountCopies() }
        credentialsChanged()
        labellingAccountChanged()
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
        // What was kept for reading offline was this account's.
        forgetAccountCopies()
        credentialsChanged()
    }

    // MARK: Machiya sign-in

    /// The Machiya sign-in (Settings → Account → Sign in to Machiya): the
    /// token and who it signs in as, from the Keychain (`MachiyaKeychain`,
    /// never UserDefaults), read at launch and after every change.
    private(set) var machiyaToken = MachiyaKeychain.token
    private(set) var machiyaPrincipal = MachiyaKeychain.principal

    /// The sign-in for the room clients: the token, and the rooms it may go
    /// to by origin (Kura and Konbini as set in Settings → Search → Notes, less
    /// Hister's and SearXNG's origins). Hister's and SearXNG's clients never
    /// take it. nil when signed out.
    var machiyaSignIn: MachiyaSignIn? {
        let rooms = Machiya.rooms([searchPage.niwaURL, searchPage.konbiniURL], excluding: [serverURL, searxngURL])
        // Signed in through Hister, the rooms get the helper's id (rooms in
        // Hister sign-in mode refuse the identity file's tokens); else the
        // Machiya token, as before.
        if let account = histerAccount, let signIn = MachiyaSignIn(sessionID: account.sessionID, rooms: rooms) { return signIn }
        // Not signed in: the identity file's token, if any. Never Hister's
        // token: it stays for Hister, and a room in Hister sign-in mode asks
        // you to sign in instead.
        return MachiyaSignIn(token: machiyaToken, rooms: rooms)
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
        // Kura's notes kept for reading offline came with this sign-in.
        OfflineStore.clear()
        SummaryCache.clear()
        HisterClient.clearCache()
        machiyaChanged()
    }

    /// Reads the sign-in again, and Kura's vaults and Konbini's cards with it.
    private func machiyaChanged() {
        roomsGeneration &+= 1
        machiyaToken = MachiyaKeychain.token
        machiyaPrincipal = MachiyaKeychain.principal
        vaultsNextRead = nil
        cardsNextRead = nil
    }

    /// The pills over a list or search: Opened only while Show Opened is on.
    var searchScopes: [SearchScope] {
        let available = SearchScope.allCases.filter {
            switch $0 {
            case .opened: searchPage.showOpened
            case .smallweb: smallweb != nil
            case .files: hasLocalFiles
            case .code: hasCodeDocs
            case .media: media != nil
            // The web's own tabs, while web results are on.
            case .images, .videos, .news: allSearch.webResults
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

    // MARK: Media (docs/media.md)

    /// Each media service's address (Settings → Search → Media): this
    /// device's own, never sent to the account or to Safari's extension. The
    /// tokens are in the Keychain (`MediaKeychain`).
    var mediaAddresses: [MediaService: String] = [:] {
        didSet {
            for service in MediaService.allCases {
                UserDefaults.standard.set(mediaAddresses[service] ?? "", forKey: Self.mediaAddressKey(service))
            }
            rebuildMedia()
        }
    }

    /// Media services switched off here (Settings → Media): their address and
    /// token are kept, but they're not asked.
    var mediaOff: Set<MediaService> = [] {
        didSet {
            UserDefaults.standard.set(mediaOff.map(\.rawValue).sorted(), forKey: Self.mediaOffKey)
            rebuildMedia()
        }
    }
    static let mediaOffKey = "mediaOff"

    /// The media services set up here (an address and a token each); nil
    /// with none, and then there's no Media pill. One client, so each
    /// service's facts (Movary's user, Plex's machine) are asked once.
    private(set) var media: MediaClient?

    static func mediaAddressKey(_ service: MediaService) -> String { "mediaURL.\(service.rawValue)" }

    /// A token typed in Settings: saved to the Keychain (or removed when emptied).
    func setMediaToken(_ token: String, for service: MediaService) {
        guard token.trimmingCharacters(in: .whitespacesAndNewlines) != MediaKeychain.read(service) else { return }
        MediaKeychain.save(token, for: service)
        rebuildMedia()
    }

    private func rebuildMedia() {
        var accounts: [MediaService: MediaAccount] = [:]
        for service in MediaService.allCases where !mediaOff.contains(service) {
            // The Keychain only for a service with an address: at launch,
            // with none set up, no read at all (each is a trip to securityd).
            let base = mediaAddresses[service] ?? ""
            guard !base.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let account = MediaAccount(base: base, token: MediaKeychain.read(service)) { accounts[service] = account }
        }
        media = accounts.isEmpty ? nil : MediaClient(accounts: accounts)
    }

    /// The small-web gateway, while Small Web is on (Settings → Search → Small Web).
    var smallweb: SmallWebClient? {
        searchPage.smallWebTab ? SmallWebClient(serverURL: searchPage.smallwebURL) : nil
    }

    /// A page opened directly in a Gemini app: the gateway fetches and
    /// saves it to Hister, as it does what it shows. Best effort.
    func saveSmallWebPage(_ url: String) async {
        do {
            try await smallweb?.save(url)
        } catch {
            Self.log.notice("Small web page not saved: \(String(describing: error), privacy: .private)")
        }
    }

    var resultsFocusRequests = 0
    /// Bumped by `shiori://settings` (the Safari extension's settings page):
    /// each layout opens its Settings.
    var settingsRequests = 0
    /// The last of them a window acted on: a window opened later (or a view
    /// made after a cold launch) acts only on a newer one.
    var settingsRequestsSeen = 0
    /// Save This Note's Links, asked for by a note's ⋯ menu or a
    /// `shiori://save-links?path=…` / `?folder=…` link (Kura's note view).
    var saveLinksRequest: SaveLinksTarget?
    /// The list last on screen, for Settings → Export & Feed on iOS (the
    /// Mac has them in File, through the `listExport` focused value).
    var shownList: ListExport?
    private var rulesLoaded = false
    /// Why the last rules fetch failed (nil once one succeeds), for the
    /// label picker's Try Again.
    private(set) var rulesFailure: HisterError?

    /// Delete with Undo, and the pages deleted in this session.
    let deletes: PendingDeletes
    /// Labels changed in this session, by page URL.
    private(set) var labelEdits: [String: String] = [:]

    let favicons = FaviconCache()

    /// Konbini's cards, for linking vault notes to their cards.
    private(set) var konbiniCards: [Notes.Card] = [] {
        didSet { noteLinksMemo = [:] }
    }
    /// When the cards may be asked for again: never once they've come
    /// (nil: now). Set before the fetch, so one at a time goes out.
    private var cardsNextRead: Date?

    func loadCardsIfNeeded() async {
        await loadVaultsIfNeeded()
        guard !searchPage.konbiniURL.isEmpty else { return }
        if let next = cardsNextRead, Date.now < next { return }
        cardsNextRead = .distantFuture
        let base = searchPage.konbiniURL, generation = roomsGeneration
        let fetched = await Notes.fetchCards(base: base, signIn: machiyaSignIn)
        guard base == searchPage.konbiniURL, generation == roomsGeneration else {
            // Another Konbini or sign-in meanwhile: this answer isn't its.
            cardsNextRead = nil
            return
        }
        if let cards = fetched {
            konbiniCards = cards
        } else {
            // Konbini didn't answer: asked again in a while, not never.
            cardsNextRead = .now.addingTimeInterval(5 * 60)
        }
    }

    /// Kura's vaults: the default one and the others, for the Notes filter,
    /// another vault's note's place and links, and which vaults are shared
    /// (`Notes.useVaults`). Read again when older than ten minutes, so a
    /// vault made private again counts; a failed read shares none.
    private(set) var kuraVaults: [KuraVault] = [] {
        didSet { noteLinksMemo = [:] }
    }
    /// When the vaults are read again: ten minutes after a read, half a
    /// minute after a failed one (until then every vault counts as
    /// private). Set before the call, so one at a time goes out.
    private var vaultsNextRead: Date?

    func loadVaultsIfNeeded() async {
        guard let kura = notesKura else {
            Notes.useVaults([])
            return
        }
        if let next = vaultsNextRead, Date.now < next { return }
        vaultsNextRead = .now.addingTimeInterval(30)
        let generation = roomsGeneration
        // Another Kura or sign-in while it was out: not this one's answer.
        // Every other vault counts as private until the new one's comes.
        func stale() -> Bool {
            guard notesKura?.baseURL != kura.baseURL || generation != roomsGeneration else { return false }
            Notes.useVaults([])
            vaultsNextRead = nil
            return true
        }
        do {
            let found = try await kura.vaults()
            if stale() { return }
            kuraVaults = found
            Notes.useVaults(found)
            vaultsNextRead = .now.addingTimeInterval(10 * 60)
        } catch {
            if stale() { return }
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
    private(set) var noteSources = NoteSources() {
        didSet { if noteSources != oldValue { noteLinksMemo = [:] } }
    }
    /// `noteLinks` worked out once per note (a row asks for its own several
    /// times a draw), emptied whenever what goes into it changes.
    @ObservationIgnored private var noteLinksMemo: [String: NoteLinks] = [:]

    /// What Search → All reads (how many, and whether the web shows).
    struct AllSearchOptions: Equatable {
        var histerCount = 5
        var vaultCount = 3
        var webResults = true
    }
    private(set) var allSearch = AllSearchOptions()

    /// How every result row looks and what a click on it opens (Result
    /// Style, Click Opens): rows read this, never `searchPage`.
    struct RowStyle: Equatable {
        var resultStyle = "tint"
        var clickOpens = "auto"

        /// Whether a click on a result's card opens the original (else
        /// Shiori's preview): Automatic previews beside a preview pane.
        func clickOpensOriginal(pane: Bool) -> Bool {
            clickOpens == "original" || (clickOpens != "preview" && !pane)
        }
    }
    private(set) var rowStyle = RowStyle()

    /// Copies these out of `searchPage`, only when they changed.
    private func refreshListSettings() {
        let notes = NoteSources(vault: searchPage.obsidianVault, niwaURL: searchPage.niwaURL, konbiniURL: searchPage.konbiniURL)
        if notes != noteSources { noteSources = notes }
        let all = AllSearchOptions(
            histerCount: searchPage.histerCount, vaultCount: searchPage.vaultCount, webResults: searchPage.webResults)
        if all != allSearch { allSearch = all }
        let row = RowStyle(resultStyle: searchPage.resultStyle, clickOpens: searchPage.clickOpens)
        if row != rowStyle { rowStyle = row }
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
        let generation = clientGeneration
        let files = try? await client.search(LocalFiles.query(""), limit: 1)
        guard generation == clientGeneration else { return }
        if let files { hasLocalFiles = files.total > 0 }
        let code = try? await client.search(CodeDocs.query(""), limit: 1)
        guard generation == clientGeneration else { return }
        if let code { hasCodeDocs = code.total > 0 }
    }

    // MARK: Code

    /// Hister holds your repos (code-import, `metadata.source:code`):
    /// the Code pill shows only then. Asked with the files.
    private(set) var hasCodeDocs = false

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
        guard label(of: document) == Notes.label || document.label == Notes.label else { return nil }
        // Read, so a row still redraws when one of them changes.
        let cards = konbiniCards, sources = noteSources, vaults = kuraVaults
        if let known = noteLinksMemo[document.url] { return known }
        guard let links = makeNoteLinks(for: document, cards: cards, sources: sources, vaults: vaults) else { return nil }
        if noteLinksMemo.count > 2000 { noteLinksMemo = [:] }
        noteLinksMemo[document.url] = links
        return links
    }

    private func makeNoteLinks(for document: StoredPage, cards konbiniCards: [Notes.Card], sources noteSources: NoteSources,
                               vaults: [KuraVault]) -> NoteLinks? {
        guard let path = Notes.path(of: document.url, cards: konbiniCards) else { return nil }
        let host = URL(string: document.url)?.host() ?? ""
        let page = URL(string: document.url)
        let crumbs = path.replacing(/\.md$/, with: "").split(separator: "/").joined(separator: " › ")
        // A work vault's note: its own vault's name and Obsidian vault, read
        // in Kura, never a Konbini card.
        if let name = Notes.otherVault(of: document.url) {
            let vault = vaults.first { $0.name == name }
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
        /// Pages the outbox gave up on (refused, too old, out of tries).
        var notSaved: [Outbox.NotSaved] = []
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
        var next = Waiting(outbox: outbox?.status() ?? .init(count: 0, oldest: nil), notSaved: outbox?.notSaved() ?? [])
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
        // A page kept as its link alone is downloaded here first.
        let result = await outbox.drain(using: client, fetch: { try await PageFetcher.fetchPreferringHTTPS($0) })
        isSending = false
        sendStop = switch result {
        case .sent: nil
        case .stopped: .unreachable
        case .signedOut: .signedOut
        }
        refreshWaiting()
    }

    /// Forgets the pages the outbox gave up on (Settings' Clear).
    func clearNotSaved() {
        outbox?.clearNotSaved()
        refreshWaiting()
    }

    enum SendStop: Equatable {
        /// Hister didn't answer, or answered unwell.
        case unreachable
        /// Hister wants this device signed in.
        case signedOut
    }

    /// Why the last Send Now (or foreground send) stopped, if it did.
    private(set) var sendStop: SendStop?

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
        // The delete goes through this app (its guards, its caches), reached
        // without keeping it: set once the rest is.
        let owner = WeakOwner()
        deletes = PendingDeletes(
            send: { (document: StoredPage) async throws(HisterError) -> Void in
                guard let app = owner.app else { throw .unreachable }
                try await app.delete(document)
            },
            isPrivate: { Notes.isPrivateNote($0) },
            undoWindow: Self.undoWindow,
            readerWindow: Self.readerUndoWindow,
            readerRunning: { Self.voiceOverRunning },
            holdBackground: Self.holdBackground)

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
        mediaAddresses = Dictionary(uniqueKeysWithValues: MediaService.allCases.map { ($0, defaults.string(forKey: Self.mediaAddressKey($0)) ?? "") })
        mediaOff = Set((defaults.stringArray(forKey: Self.mediaOffKey) ?? []).compactMap(MediaService.init(rawValue:)))
        // An init's own assignment runs no didSet.
        rebuildMedia()
        owner.app = self
        labellingAccountChanged()
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
        let generation = clientGeneration
        do {
            let fetched = try await client.rules()
            // Another server or credential meanwhile: its own load follows.
            guard generation == clientGeneration else { return }
            rules = fetched
            rulesLoaded = true
            labellingAccountChanged()
            rulesFailure = nil
            // The share sheet's label picker works from this copy.
            SharedSettings.defaults?.set(fetched.labels, forKey: SharedSettings.Key.labels)
            await loadLocalFiles()
        } catch .cancelled {
        } catch {
            guard generation == clientGeneration else { return }
            // Tried again on the next screen that needs them; say why here.
            rulesFailure = error
            Self.log.notice("Rules not loaded: \(error.userMessage, privacy: .private)")
        }
    }

    func label(of document: StoredPage) -> String {
        labelEdits[document.url] ?? document.label
    }

    /// The user's own label (Edit Label): any suggestion waiting for the
    /// page goes, so Label New Pages never writes over it.
    func setLabel(_ label: String, for document: StoredPage) async throws(HisterError) {
        try await setLabel(label, url: document.url)
        labeller.dropWaiting(document.url)
    }

    /// By address: automatic labelling and its Undo hold no StoredPage.
    func setLabel(_ label: String, url: String) async throws(HisterError) {
        guard let client else { throw .unreachable }
        // Hister never has a private vault's note.
        guard HisterGuard.mayLabel(url: url), !(await isWorkNoteNow(url)) else { throw .notFound }
        try await client.setLabel(label, for: url)
        // Bounded: the lists refetch long before this many edits matter.
        if labelEdits.count >= 2000 { labelEdits.removeAll() }
        labelEdits[url] = label
    }

    func delete(_ document: StoredPage) async throws(HisterError) {
        guard let client else { throw .unreachable }
        guard !(await isWorkNoteNow(document.url)), !isLocalFile(document.url) else { throw .notFound }
        try await client.delete(url: document.url)
        OfflineStore.forget(url: document.url)
        SummaryCache.remove(url: document.url)
        Task { await SpotlightIndex.forget(url: document.url) }
    }

    // MARK: Delete with Undo (`deletes`)

    static let undoWindow = Duration.seconds(6)
    /// With VoiceOver on: time to hear the toast and reach its Undo.
    static let readerUndoWindow = Duration.seconds(20)

    static var voiceOverRunning: Bool {
        #if os(iOS)
        UIAccessibility.isVoiceOverRunning
        #else
        NSWorkspace.shared.isVoiceOverEnabled
        #endif
    }

    /// Time to finish a delete sent on the way to the background: iOS
    /// would suspend the app mid-DELETE. Nothing to hold on the Mac.
    private static func holdBackground() -> () -> Void {
        #if os(iOS)
        let time = BackgroundTime()
        time.id = UIApplication.shared.beginBackgroundTask(withName: "Delete") { time.end() }
        return { time.end() }
        #else
        return {}
        #endif
    }

    // MARK: Opened results (Settings → Results → Remember What You Open)

    /// Tells Hister `document` was opened from a search for `query`, so it
    /// ranks it first the next time. Not for the Library's `*`, and quietly
    /// best effort: nothing waits on it.
    func recordOpened(_ document: StoredPage, query: String) {
        recordOpened(url: document.url, title: document.title, query: query)
    }

    func recordOpened(url: String, title: String, query: String) {
        // Never a work note's address or title to Hister.
        // Never a file's: what you open there stays here.
        guard searchPage.rememberOpened, let client, HisterGuard.mayRecordOpened(url: url, query: query) else { return }
        Task {
            // Another vault's note: Kura asked afresh first.
            guard !(await self.isWorkNoteNow(url)) else { return }
            do {
                try await client.recordOpened(url: url, title: title, query: query)
            } catch {
                Self.log.notice("Opened result not recorded: \(String(describing: error), privacy: .private)")
            }
        }
    }

    /// Web results saved since launch by Save Web Results You Open: their
    /// rows show the visited mark before Hister is asked again.
    private(set) var webSavedNow: Set<String> = []

    /// Saves a web result opened from a search for `query`, when Settings
    /// says so (`Saver.saveOpened`: never a page Hister holds). Best effort:
    /// nothing waits on it, and a failure is only logged.
    func saveOpenedWeb(url: String, title: String, query: String) {
        guard searchPage.saveOpenedWeb, let client, !webSavedNow.contains(url),
              HisterGuard.mayRecordOpened(url: url, query: query) else { return }
        let outbox = saveOutbox
        Task {
            let outcome = await Saver.saveOpened(url, title: title, query: query, client: client, outbox: outbox)
            switch outcome {
            case .saved, .alreadyInHister: webSavedNow.insert(url)
            case .queued: webSavedNow.insert(url); refreshWaiting()
            default: Self.log.notice("Opened web result not saved: \(String(describing: outcome), privacy: .private)")
            }
        }
    }

    func forgetOpened(_ url: String, query: String) async throws(HisterError) {
        guard let client else { throw .unreachable }
        try await client.forgetOpened(url: url, query: query)
    }

    /// A real search, not a browse (the Library's `*`, a note list).
    static func remembers(_ query: String) -> Bool { HisterGuard.remembers(query) }

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
    /// Keys whose fetch failed for now, and when: not asked again for a
    /// while (a row appearing again would otherwise ask every time).
    private var failedAt: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 120
    private var inFlight: [String: Task<Fetch, Never>] = [:]

    private enum Fetch {
        case image(PlatformImage)
        /// The server has no usable icon (404, or a refusal such as
        /// Hister's 415 "invalid favicon data"); don't ask again this session.
        case none
        /// Unreachable, a sign-in or a server error; worth a try later.
        case failed
    }

    /// The icon if it's here already, without asking anyone.
    func cached(_ key: String) -> PlatformImage? {
        key.isEmpty ? nil : images.object(forKey: key as NSString)
    }

    func image(for key: String, using client: HisterClient?) async -> PlatformImage? {
        guard !key.isEmpty, let client else { return nil }
        if let image = images.object(forKey: key as NSString) { return image }
        if missing.contains(key) { return nil }
        if let at = failedAt[key], Date.now.timeIntervalSince(at) < Self.retryAfter { return nil }
        let task = inFlight[key] ?? Task { () -> Fetch in
            do {
                let data = try await client.favicon(key: key)
                return PlatformImage(data: data).map(Fetch.image) ?? .none
            } catch HisterError.notFound, HisterError.invalidQuery {
                return .none
            } catch HisterError.server(let status, _) where status < 500 && status != 408 && status != 429 {
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
            if failedAt.count > 2000 { failedAt.removeAll() }
            failedAt[key] = .now
            return nil
        }
    }
}

/// The app, for a sub-model's closure made in `init`, before `self` can be.
private final class WeakOwner {
    weak var app: AppState?
}

#if os(iOS)
/// A background task's time, ended once: when the work is done, or when
/// iOS says the time is up.
private final class BackgroundTime {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif

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
    /// Save a web result you open to Hister (`Saver.saveOpened`). This device's own.
    var saveOpenedWeb = false
    /// The filter bar (site, date, visits…) on search results.
    var searchFilters = true
    /// Meaning-based matches mixed in, where the server has them set up.
    var semanticSearch = false
    /// A run of pages from one site shows its first, then "N more".
    var foldRepeats = true
    /// Pages you opened, marked as opened (lifted into Your Pages, "You
    /// Opened", the Opened pill); off, they're ordinary results, still first.
    /// On by default; a stored choice is kept.
    var showOpened = true
    /// "tint", "solid", "bar" or "none": how your pages, notes and opened pages
    /// stand apart in lists (`ResultBar`).
    var resultStyle = "tint"
    /// Set once Result Style has been put back to Tint (0.5.0).
    static let resultStyleResetKey = "resultStyleTintReset"
    /// What a click on a result's card opens (`SharedSettings.Key.clickOpens`;
    /// rows read it through `AppState.rowStyle`).
    var clickOpens = "auto"
    /// Labels and collections lead the search field's suggestions.
    var labelSuggestions = true
    /// The user's RSS reader, for "Subscribe in RSS Reader" (opened in the browser).
    var newsBlurURL = ""
    /// Obsidian matches vault names exactly. The default is the build's
    /// `SHIORI_OBSIDIAN_VAULT` (local.yml), if a build sets one; empty,
    /// notes link to Kura only until Settings → Search → Notes names one.
    var obsidianVault = ""
    var niwaURL = ""
    var konbiniURL = ""
    /// Where notes come from: "kura", "hister", or "" until the person
    /// picks (`AppState.notesFrom`). This device's own.
    var notesSource = ""
    /// The small-web gateway (Gemini and Gopher search), its tab, and
    /// where a result opens: "gateway" (its HTML page, the default) or
    /// "direct" (the gemini:// link, for an app such as Lagrange).
    var smallwebURL = ""
    var smallWebTab = true
    var smallWebOpen = "gateway"
    /// SearXNG's safe search: "off", "moderate" or "strict" (`SharedSettings.Key.safeSearch`).
    var safeSearch = "off"
    /// How the pills sit when they don't fit: "auto" (they wrap) or
    /// "scroll" (`SharedSettings.Key.pillRow`). This device's own.
    var pillRow = "auto"

    init() {}

    init(from defaults: UserDefaults?, bundle: Bundle = .main) {
        // Kura's build default: SHIORI_KURA_URL, else its older name, SHIORI_NIWA_URL.
        let kura = (bundle.object(forInfoDictionaryKey: "ShioriDefaultKuraURL") as? String) ?? ""
        niwaURL = kura.isEmpty ? ((bundle.object(forInfoDictionaryKey: "ShioriDefaultNiwaURL") as? String) ?? "") : kura
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
        flag(K.saveOpenedWeb, &saveOpenedWeb)
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
        if let v = defaults.string(forKey: K.clickOpens), SharedSettings.clickOpensChoices.contains(v) { clickOpens = v }
        flag(K.labelSuggestions, &labelSuggestions)
        if let v = defaults.string(forKey: K.newsBlurURL) { newsBlurURL = v }
        if let v = defaults.string(forKey: K.obsidianVault), !v.isEmpty { obsidianVault = v }
        if let v = defaults.string(forKey: K.niwaURL) { niwaURL = v }
        if let v = defaults.string(forKey: K.konbiniURL) { konbiniURL = v }
        if let v = defaults.string(forKey: K.notesSource), SharedSettings.notesSources.contains(v) { notesSource = v }
        if let v = defaults.string(forKey: K.smallwebURL), !v.isEmpty { smallwebURL = v }
        flag(K.smallWebTab, &smallWebTab)
        if let v = defaults.string(forKey: K.smallWebOpen), SharedSettings.smallWebOpens.contains(v) { smallWebOpen = v }
        if let v = defaults.string(forKey: K.safeSearch), SharedSettings.safeSearches.contains(v) { safeSearch = v }
        if let v = defaults.string(forKey: K.pillRow), SharedSettings.pillRows.contains(v) { pillRow = v }
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
        defaults.set(saveOpenedWeb, forKey: K.saveOpenedWeb)
        defaults.set(searchFilters, forKey: K.searchFilters)
        defaults.set(semanticSearch, forKey: K.semanticSearch)
        defaults.set(foldRepeats, forKey: K.foldRepeats)
        defaults.set(showOpened, forKey: K.showOpened)
        defaults.set(resultStyle, forKey: K.resultStyle)
        defaults.set(clickOpens, forKey: K.clickOpens)
        defaults.set(labelSuggestions, forKey: K.labelSuggestions)
        defaults.set(newsBlurURL, forKey: K.newsBlurURL)
        defaults.removeObject(forKey: K.pageTextSize)
        defaults.set(obsidianVault, forKey: K.obsidianVault)
        defaults.set(niwaURL, forKey: K.niwaURL)
        defaults.set(konbiniURL, forKey: K.konbiniURL)
        defaults.set(notesSource, forKey: K.notesSource)
        defaults.set(smallwebURL, forKey: K.smallwebURL)
        defaults.set(smallWebTab, forKey: K.smallWebTab)
        defaults.set(smallWebOpen, forKey: K.smallWebOpen)
        defaults.set(safeSearch, forKey: K.safeSearch)
        defaults.set(pillRow, forKey: K.pillRow)
        defaults.removeObject(forKey: K.histerPlacement)
    }
}
