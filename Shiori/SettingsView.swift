import HisterKit
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import SafariServices
#endif

/// The Safari extension, named after the app (`SHIORI_BUNDLE_PREFIX`).
let extensionBundleIdentifier = ShioriID.app + ".Extension"

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var draft = ""
    @State private var check: ConnectionCheck = .idle
    @State private var searxngDraft = ""
    // Kura's and Konbini's addresses are kept here until Return or leaving
    // the page: the Machiya token goes to them, never to a half-typed host.
    @State private var kuraDraft = ""
    @State private var konbiniDraft = ""

    enum ConnectionCheck: Equatable {
        case idle, checking
        case ok(Int)
        case failed(String)
    }

    /// Settings in pages, in the house's order (Appearance first, then
    /// Shiori's own, Account and About last): an index on iPhone and iPad,
    /// the Settings window's tabs on the Mac. The same pages everywhere.
    enum Page: String, CaseIterable, Identifiable {
        case appearance, search, results, media, safari, ai, feeds, account
        var id: Self { self }
        var title: String {
            switch self {
            case .appearance: "Appearance"
            case .search: "Search"
            case .results: "Results"
            case .media: "Media"
            case .safari: "Safari"
            case .ai: "AI"
            case .feeds: "Feeds & Export"
            case .account: "Account"
            }
        }
        var symbol: String {
            switch self {
            // One shape, so the Mac's tabs read the same size: each a
            // symbol in a circle (Safari's compass is one), AI's sparkles
            // the one open glyph of the same height.
            case .appearance: "circle.lefthalf.filled"
            case .search: "magnifyingglass.circle"
            case .results: "list.bullet.circle"
            case .media: "play.circle"
            case .safari: "safari"
            case .ai: "sparkles"
            case .feeds: "antenna.radiowaves.left.and.right.circle"
            case .account: "person.crop.circle"
            }
        }
        var summary: String {
            switch self {
            case .appearance: "Theme, appearance, text size, app icon"
            case .search: "Hister, pills, the web, Small Web and your notes"
            case .results: "How results look and open, and your history"
            case .media: "Your libraries and what you played"
            case .safari: "The extension, and Shiori's results in Safari"
            case .ai: "Summaries, AI providers and keys; off unless you turn it on"
            case .feeds: "Feeds, NewsBlur, export"
            case .account: "Signing in, waiting pages, about"
            }
        }
    }

    var body: some View {
        #if os(macOS)
        TabView {
            ForEach(Page.allCases) { page in
                self.page(page)
                    .tabItem { Label(page.title, systemImage: page.symbol) }
                    .tag(page)
            }
        }
        .onAppear(perform: loadDrafts)
        .onDisappear(perform: saveDrafts)
        // Opening Settings asks the account for the shared settings.
        .task { await app.syncAccountPrefs(force: true) }
        #else
        List {
            Section {
                ForEach(Page.allCases) { page in
                    NavigationLink {
                        self.page(page)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(page.title).foregroundStyle(palette.text)
                                Text(page.summary)
                                    .textStyle(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                        } icon: {
                            Image(systemName: page.symbol).foregroundStyle(palette.accent)
                        }
                    }
                    .listRowBackground(palette.surface)
                }
            }
        }
        .themedBackground()
        .navigationTitle("Settings")
        .onAppear(perform: loadDrafts)
        .onDisappear(perform: saveDrafts)
        .task { await app.syncAccountPrefs(force: true) }
        #endif
    }

    private func loadDrafts() {
        draft = app.serverURL
        searxngDraft = app.searxngURL
        kuraDraft = app.searchPage.niwaURL
        konbiniDraft = app.searchPage.konbiniURL
    }

    /// The house's text sizes, as Appearance's Text Size offers them.
    static let houseSizes = [("xsmall", "Extra Small"), ("small", "Small"), ("standard", "Standard"), ("large", "Large"), ("xlarge", "Extra Large")]

    /// Where the shared settings stand (the contract's state line).
    private var prefsStateLine: String {
        switch app.prefsState {
        case .notSignedIn: "Sign in to Hister (Settings → Account) and these follow you; until then they stay on this device."
        case .synced: "Signed in: these follow you."
        case .signInNeeded: "Sign in to Hister again (Settings → Account) and these follow you again."
        case .unavailable: "Sign-in is unavailable right now: these stay on this device, and go once it answers."
        }
    }

    private func saveDrafts() {
        save()
        saveSearxng()
        saveRooms()
    }

    private func saveRooms() {
        let kura = kuraDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let konbini = konbiniDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if kura != app.searchPage.niwaURL { app.searchPage.niwaURL = kura }
        if konbini != app.searchPage.konbiniURL { app.searchPage.konbiniURL = konbini }
    }

    @ViewBuilder private func page(_ page: Page) -> some View {
        @Bindable var app = app
        Form {
            switch page {
            case .appearance:
            // The house's first section, as every Machiya app has it: these
            // follow the person to every app and device (AccountPrefs), but
            // this device's own size and the app icon.
            Section {
                Picker("Theme", selection: $app.palette) {
                    ForEach(AppPalette.all) { palette in
                        Text(palette.name).tag(palette)
                    }
                }
                Picker("Mode", selection: $app.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                // The house's five steps (the account's text_size).
                Picker("Text Size", selection: Binding(
                    get: { PrefsSync.toHouse[app.textSize.rawValue] ?? "standard" },
                    set: { app.textSize = TextSize.resolve(PrefsSync.toSize[$0] ?? "system") })) {
                    ForEach(Self.houseSizes, id: \.0) { key, name in
                        Text(name).tag(key)
                    }
                }
                Toggle("Use This Device's Size", isOn: Binding(
                    get: { app.deviceTextSize != nil },
                    set: { app.deviceTextSize = $0 ? app.textSize : nil }))
                if app.deviceTextSize != nil {
                    Picker("This Device's Size", selection: Binding(
                        get: { app.deviceTextSize ?? app.textSize },
                        set: { app.deviceTextSize = $0 })) {
                        ForEach(TextSize.choices) { size in
                            Text(size.label).tag(size)
                        }
                    }
                }
                AppIconPicker()
            } header: {
                Text("Appearance")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Follows you when signed in, except This Device's Size and the app icon.")
                    Text(prefsStateLine)
                }
            }
            .listRowBackground(palette.surface)

            case .search:
            // Hister first: your pages, which everything else searches beside.
            // Its sign-in stays under Account.
            Section {
                SettingsField(label: "Server", text: $draft, prompt: "https://hister.example/", submit: save)
                Button("Test Connection", action: { Task { await checkConnection() } })
                    .disabled(check == .checking || HisterClient(serverURL: draft) == nil)
                connectionStatus
                unencryptedNote(draft)
                ServerStatsRow()
            } header: {
                Text("Hister")
            } footer: {
                Text("Your pages: Shiori searches and saves them here, and the Safari extension follows this address. Sign in under Account.")
            }
            .listRowBackground(palette.surface)

            PillsSection()
                .listRowBackground(palette.surface)

            // Every section the same way: its switch first, then its addresses
            // (SettingsField), then its choices; a footer of a sentence or two.
            Section {
                Toggle("Web Results", isOn: $app.searchPage.webResults)
                SettingsField(label: "SearXNG", text: $searxngDraft, prompt: "https://searxng.example/", submit: saveSearxng)
                unencryptedNote(searxngDraft)
            } header: {
                Text("Web")
            } footer: {
                Text("Your SearXNG: the web results here and in Safari. Thumbnails come only through its image proxy.")
            }
            .listRowBackground(palette.surface)

            Section {
                Toggle("Small Web", isOn: $app.searchPage.smallWebTab)
                if app.searchPage.smallWebTab {
                    SettingsField(label: "Gateway", text: $app.searchPage.smallwebURL, prompt: "https://smallweb.example/")
                    Picker("Open Results", selection: $app.searchPage.smallWebOpen) {
                        Text("Through the Gateway").tag("gateway")
                        Text("In a Gemini App").tag("direct")
                    }
                }
            } header: {
                Text("Small Web")
            } footer: {
                Text("Gemini and Gopher through your small-web gateway, searched when you press Return. Pages you open are saved to Hister.")
            }
            .listRowBackground(palette.surface)

            Section {
                // Where notes come from: shows the one in use (Kura when one
                // is set up, until a choice is made); picking one keeps it.
                Picker("Notes From", selection: Binding(
                    get: { app.notesFrom.rawValue },
                    set: { app.searchPage.notesSource = $0 }
                )) {
                    Text("Kura").tag(NotesSource.kura.rawValue)
                    Text("Hister").tag(NotesSource.hister.rawValue)
                }
                SettingsField(label: "Kura", text: $kuraDraft, prompt: "https://kura.example/", submit: saveRooms)
                UnencryptedNote(address: kuraDraft, carries: "your sign-in and notes")
                SettingsField(label: "Konbini", text: $konbiniDraft, prompt: "https://konbini.example/", submit: saveRooms)
                UnencryptedNote(address: konbiniDraft, carries: "your sign-in and notes")
                SettingsField(label: "Obsidian Vault", text: $app.searchPage.obsidianVault, prompt: "Your vault's name", address: false)
            } header: {
                Text("Notes")
            } footer: {
                Text("Notes open in this Obsidian vault, with their Kura page and Konbini card beside them. From Hister, only your default vault's notes.")
            }
            .listRowBackground(palette.surface)

            case .results:
            Section {
                Picker("Result Style", selection: $app.searchPage.resultStyle) {
                    Text("Tint").tag("tint")
                    Text("Solid").tag("solid")
                    Text("Left Bar").tag("bar")
                    Text("None").tag("none")
                }
                Toggle("Fold Repeated Sites", isOn: $app.searchPage.foldRepeats)
                Toggle("Search Filters", isOn: $app.searchPage.searchFilters)
                if app.capabilities?.semantic == true {
                    Toggle("Meaning-Based Search", isOn: $app.searchPage.semanticSearch)
                }
            } header: {
                Text("Results")
            }
            .listRowBackground(palette.surface)
            .task { await app.loadCapabilitiesIfNeeded() }

            Section {
                Picker(Self.clickOpensTitle, selection: $app.searchPage.clickOpens) {
                    Text("Automatic").tag("auto")
                    Text("The Original").tag("original")
                    Text("Shiori's Preview").tag("preview")
                }
                Toggle("Preview Pane", isOn: $app.searchPage.previewPane)
                // Off: a preview fetches nothing from the page's own sites.
                Toggle("Images in Previews", isOn: $app.searchPage.previewImages)
            } header: {
                Text("Opening")
            } footer: {
                Text(openingFooter)
            }
            .listRowBackground(palette.surface)

            Section {
                Toggle("Recent Searches", isOn: $app.searchPage.searchHistory)
                Button("Clear Recent Searches", role: .destructive) {
                    app.clearRecentSearches()
                }
                .disabled(app.recentSearches.isEmpty)
                Toggle("Remember What You Open", isOn: $app.searchPage.rememberOpened)
                Toggle("Show Opened", isOn: $app.searchPage.showOpened)
            } header: {
                Text("History")
            } footer: {
                Text("Your last \(SharedSettings.recentLimit) searches, from Shiori and from Safari, shown when you tap a search field and kept on this device only. Remember What You Open puts the results you open first next time.")
            }
            .listRowBackground(palette.surface)
            .onAppear { app.reloadRecentSearches() }

            case .media:
            MediaSettingsPage()

            case .safari:
            Section {
                ExtensionSetup()
            } header: {
                Text("Safari Extension")
            }
            .listRowBackground(palette.surface)

            Section {
                Toggle("Search with Shiori", isOn: $app.combinedSearch)
            } header: {
                Text("Search from Safari")
            } footer: {
                Text("Keep DuckDuckGo as Safari's search engine: address-bar searches then open Shiori's results. Bangs like !w still go to DuckDuckGo.")
            }
            .listRowBackground(palette.surface)

            // Shiori Search's own options (Safari's results page and the
            // hosted page); the app's lists don't read them. Not tied to
            // Search with Shiori: the hosted page follows them too.
            Section {
                Toggle("Your Pages in All", isOn: $app.searchPage.histerInGeneral)
                Toggle("Your Notes in All", isOn: $app.searchPage.vaultInGeneral)
                Toggle("Pages Tab", isOn: $app.searchPage.histerTab)
                Toggle("Notes Tab", isOn: $app.searchPage.vaultTab)
                if app.searchPage.webResults {
                    Toggle("Info Box", isOn: $app.searchPage.showInfobox)
                    Toggle("Related Searches", isOn: $app.searchPage.showRelated)
                    Toggle("Thumbnails", isOn: $app.searchPage.showThumbnails)
                }
                Toggle("Labels in Suggestions", isOn: $app.searchPage.labelSuggestions)
            } header: {
                Text("Shiori Search")
            } footer: {
                Text("Safari's results page and the hosted search page: your pages' and notes' top matches lead All, and each has its tab. Info Box, Related Searches and Thumbnails come with Web Results (Settings → Search).")
            }
            .listRowBackground(palette.surface)

            case .ai:
            AISettingsPage()

            case .feeds:
            #if os(iOS)
            // The Mac has these in File.
            if let list = app.shownList {
                ListActionsSection(list: list)
                    .listRowBackground(palette.surface)
            }
            #endif

            FeedsSection()
                .listRowBackground(palette.surface)

            case .account:
            HisterSignInSection()
                .listRowBackground(palette.surface)

            HisterTokenSection()
                .listRowBackground(palette.surface)

            MachiyaSignInSection()
                .listRowBackground(palette.surface)

            WaitingSection()
                .listRowBackground(palette.surface)

            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Link("Hister by Adam Tauber", destination: URL(string: "https://github.com/asciimoo/hister")!)
                Link(
                    "Based on hister-safari by Nick Burns",
                    destination: URL(string: "https://github.com/nburns/hister-safari")!)
                // The source (AGPL-3.0 section 13), when the build names it.
                if let source = SourceLink.url(Bundle.main.object(forInfoDictionaryKey: "ShioriSourceURL") as? String) {
                    Link("View the Source", destination: source)
                }
                Text("Shiori is free software under the \(SourceLink.license).")
                    .textStyle(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
            }
        }
        .formStyle(.grouped)
        .themedBackground()
        .navigationTitle(page.title)
        // A page left saves its fields (the server's and SearXNG's drafts).
        .onDisappear(perform: saveDrafts)
    }

    #if os(macOS)
    static let clickOpensTitle = "Click Opens"
    #else
    static let clickOpensTitle = "Tap Opens"
    #endif

    private var openingFooter: String {
        "\(Self.clickOpensTitle) and Preview Pane stay on this device; a result's menu always has both ways to open it. Off, Images in Previews keeps previews to your Hister."
    }

    private func unencryptedNote(_ address: String) -> some View {
        UnencryptedNote(address: address, carries: "pages and searches")
    }

    @ViewBuilder private var connectionStatus: some View {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
        case .ok(let total):
            Label {
                Text("Connected: \(total.formatted()) pages")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.tint(.green))
            }
            .announces("Connected: \(total.formatted()) pages")
        case .failed(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(palette.danger)
            }
            .announces(message)
        }
    }

    private func saveSearxng() {
        var url = searxngDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty, !url.hasSuffix("/") { url += "/" }
        if url != app.searxngURL { app.searxngURL = url }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != app.serverURL { app.serverURL = trimmed }
    }

    private func checkConnection() async {
        save()
        let checked = draft
        // As the app's own client: the token, and the sign-in's session for
        // the server it belongs to (Hister reads the session first, so a
        // signed-in device checks fine whatever its token).
        let session = checked.trimmingCharacters(in: .whitespacesAndNewlines) == app.serverURL ? app.histerAccount?.session : nil
        guard let client = HisterClient(serverURL: checked, token: app.histerToken, histerSession: session) else { return }
        check = .checking
        let result: ConnectionCheck
        do {
            result = .ok(try await client.search("*", limit: 1).total)
        } catch {
            result = .failed(error.userMessage)
        }
        // An answer about an address that has since been edited isn't news.
        if draft == checked { check = result } else { check = .idle }
    }
}

/// How to switch the extension on, per platform.
struct ExtensionSetup: View {
    var body: some View {
        #if os(iOS)
        Step(number: 1, of: 4, text: "Open Settings → Apps → Safari → Extensions → Shiori and turn it on.")
        Step(number: 2, of: 4, text: "Set All Websites to Allow, so every page you visit can be indexed. Check this again after each update: reinstalling resets it.")
        Step(number: 3, of: 4, text: "Leave Allow in Private Browsing off.")
        Step(number: 4, of: 4, text: "In Safari, tap the Page Menu button at the left of the address bar, then Shiori, to index a page or skip a page or site.")
        #else
        Step(number: 1, of: 4, text: "Open Safari Settings → Extensions and turn on Shiori.")
        Step(number: 2, of: 4, text: "Allow it on every website, so every page you visit can be indexed.")
        Step(number: 3, of: 4, text: "Leave Allow in Private Browsing off.")
        Step(number: 4, of: 4, text: "Click the Shiori toolbar button to index a page or skip a page or site.")
        MacExtensionStatus()
        #endif
    }
}

private struct Step: View {
    let number: Int
    let of: Int
    let text: LocalizedStringKey
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .textStyle(.body, weight: .bold).monospacedDigit()
                .foregroundStyle(palette.accent)
            Text(text)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        // One VoiceOver stop per step, with its place in the list.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(number) of \(of)"))
        .accessibilityValue(Text(text))
    }
}

#if os(macOS)
private struct MacExtensionStatus: View {
    @Environment(\.palette) private var palette
    @State private var enabled: Bool?

    var body: some View {
        ViewThatFits {
            HStack(spacing: 12) { button; status }
            VStack(alignment: .leading, spacing: 8) { button; status }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private var button: some View {
        Button("Open Safari Extensions Settings…") {
            Task {
                try? await SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier)
            }
        }
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder private var status: some View {
        switch enabled {
        case true?:
            Label {
                Text("Turned on")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.tint(.green))
            }
        case false?:
            Label("Turned off", systemImage: "circle")
        case nil:
            EmptyView()
        }
    }

    private func refresh() async {
        let state = try? await SFSafariExtensionManager.stateOfSafariExtension(
            withIdentifier: extensionBundleIdentifier)
        let new = state?.isEnabled
        if let new, enabled != nil, new != enabled {
            AccessibilityNotification.Announcement(new ? "Shiori extension turned on" : "Shiori extension turned off")
                .post()
        }
        enabled = new
    }
}
#endif

extension Bundle {
    var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }
}

/// The app icon: Hister's own, or one of Shiori's Tokyo Night takes. On
/// iOS this is the system's alternate icon. The Mac has no such API, so
/// the Dock icon is swapped while Shiori runs (`MacAppIcon`), and
/// scripts/install-mac.sh builds the chosen icon in for Finder and
/// Launchpad.
private struct AppIconPicker: View {
    private struct Choice: Identifiable {
        let id: String?  // the icon set's name; nil is the default
        let title: String
        let preview: String
    }

    private let choices = [
        Choice(id: nil, title: "Shiori", preview: "IconPreview-Default"),
        Choice(id: "AppIcon-Light", title: "Light", preview: "IconPreview-Light"),
    ]

    #if os(iOS)
    @State private var current = UIApplication.shared.alternateIconName
    #else
    @State private var current = MacAppIcon.current
    #endif
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App Icon")
            HStack(spacing: 16) {
                ForEach(choices) { choice in
                    Button {
                        select(choice.id)
                    } label: {
                        VStack(spacing: 6) {
                            Image(choice.preview)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .clipShape(.rect(cornerRadius: 13.5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                                        .strokeBorder(palette.accent, lineWidth: current == choice.id ? 3 : 0)
                                }
                            Text(choice.title)
                                .textStyle(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(current == choice.id ? .isSelected : [])
                }
            }
            #if os(macOS)
            Text("The Dock shows it now; Finder and Launchpad after Shiori is next installed.")
                .textStyle(.footnote)
                .foregroundStyle(palette.secondaryText)
            #endif
        }
        .padding(.vertical, 4)
    }

    private func select(_ name: String?) {
        guard name != current else { return }
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                current = name
            } catch {
                current = UIApplication.shared.alternateIconName
            }
        }
        #else
        MacAppIcon.current = name
        current = name
        #endif
    }
}

#if os(macOS)
/// The Mac's chosen icon (`macAppIcon` in the app's defaults, which
/// scripts/install-mac.sh also reads), applied to the Dock while running.
enum MacAppIcon {
    static let key = "macAppIcon"

    static var current: String? {
        // A choice whose icon is gone (the Hister icons, removed) counts as
        // the default.
        get { UserDefaults.standard.string(forKey: key).flatMap { NSImage(named: $0) != nil ? $0 : nil } }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            apply()
        }
    }

    /// nil restores whatever icon the installed build carries.
    static func apply() {
        NSApplication.shared.applicationIconImage = current.flatMap { NSImage(named: $0) }
    }
}
#endif

/// Pages saved while Hister was out of reach, and waiting to be sent.
private struct WaitingSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let waiting = app.waiting
        Section {
            LabeledContent("From Safari") {
                Text(describe(waiting.safari, oldest: waiting.safariOldest))
            }
            LabeledContent("Shared and shortcuts") {
                Text(describe(waiting.outbox.count, oldest: waiting.outbox.oldest))
            }
            if waiting.outbox.count > 0 {
                Button(app.isSending ? "Sending…" : "Send Now") {
                    Task { await app.sendWaiting() }
                }
                .disabled(app.isSending)
                if let stop = app.sendStop, !app.isSending {
                    Label(stop == .signedOut
                          ? "Hister wants you signed in, so these are still waiting. They'll go once you sign in."
                          : "Hister didn't answer, so these are still waiting. They'll go when it's reachable.",
                          systemImage: "exclamationmark.triangle")
                        .textStyle(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        } header: {
            Text("Waiting to Send")
        } footer: {
            Text("Pages keep the time you saved them. Safari's go out as you browse once Hister is reachable; the rest when Shiori opens.")
        }
        .onAppear { app.refreshWaiting() }
        if !waiting.notSaved.isEmpty {
            Section {
                ForEach(waiting.notSaved) { page in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title.isEmpty ? (page.url.isEmpty ? "A Page" : page.url) : page.title)
                            .textStyle(.body)
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                        if !page.title.isEmpty, !page.url.isEmpty {
                            Text(page.url)
                                .textStyle(.caption)
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text("\(page.reason) · \(page.date.formatted(.relative(presentation: .named)))")
                            .textStyle(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button("Clear", role: .destructive) { app.clearNotSaved() }
            } header: {
                Text("Not Saved")
            } footer: {
                Text("Waiting pages Shiori gave up on, and why.")
            }
        }
    }

    private func describe(_ count: Int, oldest: Date?) -> String {
        guard count > 0 else { return "Nothing" }
        let pages = count == 1 ? "1 page" : "\(count) pages"
        guard let oldest else { return pages }
        return "\(pages), since \(oldest.formatted(.relative(presentation: .named)))"
    }
}

/// Feeds for NewsBlur: where it is, Hister's feed of new pages, and every
/// collection and label at once as OPML (NewsBlur → Import).
#if os(iOS)
/// The list last on screen, as File → Export List, Copy Feed Link and
/// Subscribe in NewsBlur are on the Mac: occasional, so here rather than
/// in the list's toolbar.
private struct ListActionsSection: View {
    let list: ListExport
    @Environment(\.palette) private var palette
    @State private var file: ExportFile?
    @State private var making: Export.Format?
    @State private var failure: String?

    var body: some View {
        Section {
            if let makeFile = list.makeFile {
                ForEach(Export.Format.allCases) { format in
                    Button {
                        Task { await export(format, with: makeFile) }
                    } label: {
                        HStack {
                            Label("Export as \(format.title)…", systemImage: "square.and.arrow.down")
                            Spacer()
                            if making == format { ProgressView() }
                        }
                    }
                    .disabled(making != nil)
                }
            }
            FeedButtons(feed: list.feed)
        } header: {
            Text("Export & Feed")
        } footer: {
            Text("For \(list.title), the list you were on. An export holds the whole list, not only what's loaded.")
        }
        .fileExporter(
            isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }),
            document: file, contentType: file?.contentType ?? .json, defaultFilename: file?.name
        ) { _ in
            file = nil
        }
        .alert(
            "Couldn't Export",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func export(_ format: Export.Format, with makeFile: (Export.Format) async throws(HisterError) -> ExportFile) async {
        making = format
        defer { making = nil }
        do {
            file = try await makeFile(format)
        } catch {
            failure = error.userMessage
        }
    }
}
#endif

private struct FeedsSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var draft = ""
    @State private var opml: OPMLFile?

    var body: some View {
        @Bindable var app = app
        Section {
            SettingsField(label: "NewsBlur", text: $draft, prompt: "https://newsblur.example/", submit: save)
            FeedButtons(feed: app.feedURL(query: "*", title: "New Pages", source: .all))
            Button("Export Collections as OPML…", systemImage: "list.bullet.rectangle") { opml = makeOPML() }
                .disabled(app.client == nil || (app.rules.aliases.isEmpty && app.rules.labels.isEmpty))
        } header: {
            Text("Feeds")
        } footer: {
            Text("Every search, collection and label has a feed. OPML subscribes NewsBlur to all your collections and labels at once.")
        }
        .onAppear { draft = app.searchPage.newsBlurURL }
        .onDisappear(perform: save)
        .fileExporter(
            isPresented: Binding(get: { opml != nil }, set: { if !$0 { opml = nil } }),
            document: opml, contentType: OPMLFile.type, defaultFilename: "shiori-feeds.opml"
        ) { _ in opml = nil }
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value != app.searchPage.newsBlurURL, value.isEmpty || value.hasPrefix("https://") || value.hasPrefix("http://") {
            app.searchPage.newsBlurURL = value
        }
    }

    private func makeOPML() -> OPMLFile {
        var feeds: [(title: String, url: URL)] = []
        for alias in app.rules.aliases.keys.sorted() {
            let title = CollectionIcon.title(for: alias)
            if let url = app.feedURL(query: alias, title: title) { feeds.append((title: title, url: url)) }
        }
        for label in app.rules.labels {
            if let url = app.feedURL(query: "label:\(label)", title: label) { feeds.append((title: label, url: url)) }
        }
        return OPMLFile(data: Export.opml(title: "Shiori", feeds: feeds))
    }
}

/// An OPML file, for `.fileExporter`.
struct OPMLFile: FileDocument {
    static let type = UTType(filenameExtension: "opml") ?? .xml
    static let readableContentTypes: [UTType] = [type]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The server's totals, beside its address.
struct ServerStatsRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var stats: ServerStats?

    var body: some View {
        Group {
            if let stats {
                LabeledContent("Hister Has") {
                    Text("\(stats.documents.formatted()) pages · \(stats.aliases) collections · \(stats.rules) rules")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .task(id: app.serverURL) {
            guard let client = app.client else { return }
            stats = try? await client.stats()
        }
    }
}

/// An http:// address sends what it carries unencrypted (only a VPN would
/// cover it), a sign-in or token included: said plainly, under the address.
struct UnencryptedNote: View {
    let address: String
    /// What goes there, for the sentence ("pages and searches").
    let carries: String
    @Environment(\.palette) private var palette

    var body: some View {
        if address.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://") {
            Label("Not encrypted: \(carries) go as plain HTTP. Use https:// if the server has it.",
                  systemImage: "lock.open")
                .textStyle(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }
}

/// One settings field, the same everywhere: its label on the left, the
/// value on the right in the callout size, one line (a long value scrolls
/// inside it rather than widening the page), addresses in monospace with
/// the URL keyboard. Settings → Search and Settings → Media use it.
struct SettingsField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var address = true
    /// Monospace for a value that isn't an address (a model's name); addresses always are.
    var monospaced = false
    /// For VoiceOver when several rows share a label ("Plex Address").
    var spoken: String?
    var submit: () -> Void = {}

    var body: some View {
        LabeledContent(label) {
            TextField(spoken ?? label, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .accessibilityLabel(spoken ?? label)
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(address ? .URL : .default)
                #endif
                .textContentType(address ? .URL : nil)
                .textStyle(.callout, design: address || monospaced ? .monospaced : .default)
                .onSubmit(submit)
        }
    }
}
