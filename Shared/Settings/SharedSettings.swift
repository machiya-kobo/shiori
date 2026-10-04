import Foundation

/// Settings the app writes and the Safari extension's native handler reads,
/// through the App Group both belong to.
nonisolated enum SharedSettings {
    /// From Info.plist (`ShioriAppGroup`): "group.<prefix>.shiori" on iOS,
    /// "<TeamID>.<prefix>.shiori" on macOS, where team-prefixed groups need
    /// no provisioning (project.yml, from `SHIORI_BUNDLE_PREFIX`).
    static let appGroup: String = {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "ShioriAppGroup") as? String
        guard let fromPlist, !fromPlist.isEmpty, !fromPlist.hasPrefix("$(") else {
            return "group." + ShioriID.app
        }
        return fromPlist
    }()

    enum Key {
        static let combinedSearch = "combinedSearch"
        static let searxngURL = "searxngURL"
        static let theme = "theme"
        /// The theme (one of the Machiya rooms' ten, `AppPalette`): the app,
        /// the share extension and Safari's pages, which the page's gear may set.
        static let palette = "palette"
        /// Combined search page options (Settings → Search from Safari).
        static let showInfobox = "showInfobox"
        static let showRelated = "showRelated"
        /// The AI answer atop a web search (the hosted pages, on request).
        static let aiAnswer = "aiAnswer"
        static let showThumbnails = "showThumbnails"
        /// Superseded by histerInGeneral; read once to carry an old choice over.
        static let histerPlacement = "histerPlacement"
        static let histerCount = "histerCount"
        static let histerInGeneral = "histerInGeneral"
        static let histerTab = "histerTab"
        static let vaultInGeneral = "vaultInGeneral"
        static let vaultTab = "vaultTab"
        static let vaultCount = "vaultCount"
        static let webResults = "webResults"
        /// Recent searches (the app's and Safari's, one list), shown when
        /// a search field is tapped; off keeps none.
        static let searchHistory = "searchHistory"
        /// A preview beside the results: the Mac and iPad app, and Safari's
        /// results page in a wide window.
        static let previewPane = "previewPane"
        /// Whether previews load the page's own (third-party) images.
        static let previewImages = "previewImages"
        /// Tell Hister which result was opened for a search (it ranks it first).
        static let rememberOpened = "rememberOpened"
        /// The filter bar on search results.
        static let searchFilters = "searchFilters"
        /// Meaning-based search, where the server has it set up.
        static let semanticSearch = "semanticSearch"
        /// Fold a run of pages from one site into its first and "N more".
        static let foldRepeats = "foldRepeats"
        /// Pages you opened, shown: lifted into Your Pages, "You Opened" on
        /// Pages, the Opened pill. Off hides them all.
        static let showOpened = "showOpened"
        /// How your pages, notes and opened pages stand apart in lists:
        /// "tint" (an outlined card in the pill's colour), "solid" (a plain
        /// card), "bar" (a line down the leading edge) or "none".
        static let resultStyle = "resultStyle"
        /// Matching labels and collections at the top of search suggestions.
        static let labelSuggestions = "labelSuggestions"
        /// The user's NewsBlur, for subscribe links.
        static let newsBlurURL = "newsBlurURL"
        /// Text size for the app and the results page alike: "system" or a
        /// Dynamic Type size name (`TextSize` in the app).
        static let textSize = "textSize"
        /// Superseded by textSize.
        static let pageTextSize = "pageTextSize"
        static let recentSearches = "recentSearches"
        /// Where vault notes open: the Obsidian vault's name, and the web
        /// homes of its notes.
        static let obsidianVault = "obsidianVault"
        static let niwaURL = "niwaURL"
        static let konbiniURL = "konbiniURL"
        /// The small-web gateway (Gemini and Gopher search,
        /// docs/smallweb.md), its tab, and where a result opens:
        /// "gateway" (its HTML page) or "direct" (the gemini:// or gopher://
        /// link, for an app such as Lagrange).
        static let smallwebURL = "smallwebURL"
        static let smallWebTab = "smallWebTab"
        static let smallWebOpen = "smallWebOpen"
        /// The pills' order and which show (`PillOrder`).
        static let pills = "pills"
        /// The Hister server, for the share extension and shortcuts.
        static let serverURL = "serverURL"
        /// The server's topic labels, cached for the share sheet's picker.
        static let labels = "labels"
        /// The Safari extension's offline queue, as its background reports it:
        /// ["count": Int, "oldest": unix seconds, "reportedAt": unix seconds].
        static let extensionQueue = "extensionQueue"
    }

    /// Where the share extension and shortcuts queue pages while Hister is
    /// out of reach; the app sends them.
    static var outboxDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Outbox", directoryHint: .isDirectory)
    }

    static let recentLimit = 5
    static let textSizes = ["system", "xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge"]
    static let pageCounts = [3, 5, 10, 20]

    // MARK: What the results page's own Settings may write (`apply`)

    static let flagKeys = [
        Key.combinedSearch, Key.showInfobox, Key.showRelated, Key.showThumbnails, Key.histerInGeneral,
        Key.histerTab, Key.vaultInGeneral, Key.vaultTab, Key.webResults, Key.searchHistory, Key.previewPane,
        Key.previewImages, Key.rememberOpened, Key.searchFilters, Key.semanticSearch, Key.foldRepeats,
        Key.labelSuggestions, Key.aiAnswer, Key.showOpened, Key.smallWebTab,
    ]
    static let countKeys = [Key.histerCount, Key.vaultCount]
    static let urlKeys = [Key.searxngURL, Key.niwaURL, Key.konbiniURL, Key.newsBlurURL, Key.smallwebURL]
    static let resultStyles = ["tint", "solid", "bar", "none"]
    static let smallWebOpens = ["gateway", "direct"]
    /// The rooms' theme keys, `AppPalette.all`'s (here because the Safari
    /// extension doesn't link HisterKit; tests keep the three lists alike).
    static let palettes = [
        "tokyo-night", "solarized", "nord", "dracula", "catppuccin", "gruvbox", "rose-pine", "kanagawa", "everforest", "ayu",
    ]

    /// Writes the values that pass: known keys, the right type, an allowed
    /// value. Anything else is ignored.
    @discardableResult
    static func apply(_ values: [String: Any], to defaults: UserDefaults? = SharedSettings.defaults) -> Bool {
        guard let defaults else { return false }
        var wrote = false
        func set(_ value: Any, _ key: String) {
            defaults.set(value, forKey: key)
            wrote = true
        }
        for key in flagKeys {
            if let value = values[key] as? Bool { set(value, key) }
        }
        for key in countKeys {
            if let value = values[key] as? Int, pageCounts.contains(value) { set(value, key) }
        }
        for key in urlKeys {
            if let value = values[key] as? String, value.isEmpty || value.hasPrefix("https://") || value.hasPrefix("http://") {
                set(value, key)
            }
        }
        if let value = values[Key.obsidianVault] as? String, !value.isEmpty, value.count <= 200 {
            set(value, Key.obsidianVault)
        }
        if let value = values[Key.textSize] as? String, textSizes.contains(value) { set(value, Key.textSize) }
        if let value = values[Key.theme] as? String, ["system", "day", "night"].contains(value) { set(value, Key.theme) }
        if let value = values[Key.palette] as? String, palettes.contains(value) { set(value, Key.palette) }
        if let value = values[Key.resultStyle] as? String, resultStyles.contains(value) { set(value, Key.resultStyle) }
        if let value = values[Key.smallWebOpen] as? String, smallWebOpens.contains(value) { set(value, Key.smallWebOpen) }
        if let value = values[Key.pills] as? [Any], value.isEmpty || !PillOrder.clean(value).isEmpty {
            set(PillOrder.clean(value), Key.pills)
        }
        if values[Key.searchHistory] as? Bool == false { clearRecentSearches(in: defaults) }
        return wrote
    }

    /// Changes made in the results page's own Settings (`{type:
    /// "set-settings", values}`), validated as above.
    static func applyFromPage(_ values: [String: Any], to defaults: UserDefaults? = SharedSettings.defaults) {
        guard let defaults else { return }
        apply(values, to: defaults)
        if values["clearRecentSearches"] as? Bool == true { clearRecentSearches(in: defaults) }
    }

    /// The last few searches, newest first; none while history is off.
    static func recentSearches(in defaults: UserDefaults? = SharedSettings.defaults) -> [String] {
        guard let defaults, historyOn(defaults) else { return [] }
        return Array((defaults.stringArray(forKey: Key.recentSearches) ?? []).prefix(recentLimit))
    }

    /// Moves a search to the top of the list (once, whatever its case).
    static func recordSearch(_ query: String, in defaults: UserDefaults? = SharedSettings.defaults) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let defaults, historyOn(defaults), !query.isEmpty, query.count <= 500 else { return }
        var list = defaults.stringArray(forKey: Key.recentSearches) ?? []
        list.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        list.insert(query, at: 0)
        defaults.set(Array(list.prefix(recentLimit)), forKey: Key.recentSearches)
    }

    static func clearRecentSearches(in defaults: UserDefaults? = SharedSettings.defaults) {
        defaults?.removeObject(forKey: Key.recentSearches)
    }

    private static func historyOn(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Key.searchHistory) == nil || defaults.bool(forKey: Key.searchHistory)
    }

    /// The App Group's defaults, or nil where the group isn't available.
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// What the extension's background asks for (`{type: "settings"}`). Keys
    /// the app never set are left out, so the extension keeps its own
    /// defaults for them.
    static func extensionPayload(from defaults: UserDefaults? = SharedSettings.defaults) -> [String: Any] {
        guard let defaults else { return [:] }
        var payload: [String: Any] = [:]
        if defaults.object(forKey: Key.combinedSearch) != nil {
            payload[Key.combinedSearch] = defaults.bool(forKey: Key.combinedSearch)
        }
        if let url = defaults.string(forKey: Key.searxngURL) { payload[Key.searxngURL] = url }
        if let theme = defaults.string(forKey: Key.theme) { payload[Key.theme] = theme }
        let flags = [
            Key.showInfobox, Key.showRelated, Key.showThumbnails, Key.histerInGeneral, Key.histerTab,
            Key.vaultInGeneral, Key.vaultTab, Key.webResults, Key.searchHistory, Key.previewPane, Key.previewImages,
            Key.rememberOpened, Key.foldRepeats, Key.searchFilters, Key.labelSuggestions, Key.aiAnswer, Key.showOpened, Key.smallWebTab,
        ]
        for key in flags where defaults.object(forKey: key) != nil {
            payload[key] = defaults.bool(forKey: key)
        }
        for key in [Key.histerCount, Key.vaultCount] where defaults.object(forKey: key) != nil {
            payload[key] = defaults.integer(forKey: key)
        }
        // The Hister server too, so the extension follows the app's.
        for key in [
            Key.obsidianVault, Key.niwaURL, Key.konbiniURL, Key.textSize, Key.serverURL, Key.resultStyle,
            Key.smallwebURL, Key.smallWebOpen, Key.palette,
        ] {
            if let value = defaults.string(forKey: key) { payload[key] = value }
        }
        if let pills = defaults.array(forKey: Key.pills) { payload[Key.pills] = PillOrder.clean(pills) }
        payload[Key.recentSearches] = recentSearches(in: defaults)
        return payload
    }
}
