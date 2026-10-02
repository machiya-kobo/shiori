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

    enum ConnectionCheck: Equatable {
        case idle, checking
        case ok(Int)
        case failed(String)
    }

    /// Settings in pages (it was one list of eighteen sections): an index on iPhone and iPad, the Settings
    /// window's tabs on the Mac. The same pages everywhere.
    enum Page: String, CaseIterable, Identifiable {
        case general, server, search, preview, notes, safari, ai, feeds
        var id: Self { self }
        var title: String {
            switch self {
            case .general: "General"
            case .server: "Server"
            case .search: "Search"
            case .preview: "Preview"
            case .notes: "Notes"
            case .safari: "Safari"
            case .ai: "AI"
            case .feeds: "Feeds & Export"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .server: "server.rack"
            case .search: "magnifyingglass"
            case .preview: "doc.text.magnifyingglass"
            case .notes: "note.text"
            case .safari: "safari"
            case .ai: "sparkles"
            case .feeds: "dot.radiowaves.up.forward"
            }
        }
        var summary: String {
            switch self {
            case .general: "Theme, text size, app icon, about"
            case .server: "Hister and waiting pages"
            case .search: "SearXNG, Search from Safari, and what searches show"
            case .preview: "The preview pane and its images"
            case .notes: "Obsidian, Kura and Konbini, and signing in to Machiya"
            case .safari: "The Safari extension"
            case .ai: "Summaries, AI providers and keys; off unless you turn it on"
            case .feeds: "Feeds, NewsBlur, export"
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
        #endif
    }

    private func loadDrafts() {
        draft = app.serverURL
        searxngDraft = app.searxngURL
    }

    private func saveDrafts() {
        save()
        saveSearxng()
    }

    @ViewBuilder private func page(_ page: Page) -> some View {
        @Bindable var app = app
        Form {
            switch page {
            case .general:
            Section("Appearance") {
                Picker("Theme", selection: $app.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                Picker("Text Size", selection: $app.textSize) {
                    ForEach(TextSize.choices) { size in
                        Text(size.label).tag(size)
                    }
                }
                AppIconPicker()
            }
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
                Text("Shiori is free software under the \(SourceLink.licence).")
                    .textStyle(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
            case .server:
            Section {
                TextField("Server", text: $draft, prompt: Text("https://hister.example/"))
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .textStyle(.body, design: .monospaced)
                    .onSubmit(save)
                Button("Check Connection", action: { Task { await checkConnection() } })
                    .disabled(check == .checking || HisterClient(serverURL: draft) == nil)
                connectionStatus
                unencryptedNote(draft)
                ServerStatsRow()
            } header: {
                Text("Hister Server")
            } footer: {
                Text("Shiori talks only to this server. The Safari extension follows this address too.")
            }
            .listRowBackground(palette.surface)

            WaitingSection()
                .listRowBackground(palette.surface)
            case .search:
            // SearXNG and Search from Safari first (they were under Safari,
            // though the web results everywhere use SearXNG).
            Section {
                TextField("SearXNG", text: $searxngDraft, prompt: Text("https://searxng.example/"))
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .textStyle(.body, design: .monospaced)
                    .onSubmit(saveSearxng)
                unencryptedNote(searxngDraft)
            } header: {
                Text("Web Search")
            } footer: {
                Text("Your SearXNG: the web results in Shiori and in Safari's results. Thumbnails come only through its image proxy.")
            }
            .listRowBackground(palette.surface)

            Section {
                Toggle("Search with Shiori", isOn: $app.combinedSearch)
            } header: {
                Text("Search from Safari")
            } footer: {
                Text("Keep DuckDuckGo as Safari's search engine. Searches from the address bar then open Shiori's results: your pages and notes, then the web from SearXNG. Bangs like !w still go to DuckDuckGo, and when SearXNG can't be reached you land on DuckDuckGo as usual.")
            }
            .listRowBackground(palette.surface)

            Section {
                Toggle("Remember What You Open", isOn: $app.searchPage.rememberOpened)
                Toggle("Show Opened", isOn: $app.searchPage.showOpened)
                Picker("Result Style", selection: $app.searchPage.resultStyle) {
                    Text("Tint").tag("tint")
                    Text("Solid").tag("solid")
                    Text("Left Bar").tag("bar")
                    Text("None").tag("none")
                }
                Toggle("Search Filters", isOn: $app.searchPage.searchFilters)
                Toggle("Fold Repeated Sites", isOn: $app.searchPage.foldRepeats)
                Toggle("Labels in Search Page Suggestions", isOn: $app.searchPage.labelSuggestions)
                if app.capabilities?.semantic == true {
                    Toggle("Meaning-Based Search", isOn: $app.searchPage.semanticSearch)
                }
            } header: {
                Text("Searching")
            } footer: {
                Text(searchingFooter)
            }
            .listRowBackground(palette.surface)
            .task { await app.loadCapabilitiesIfNeeded() }

            Section {
                Toggle("Recent Searches", isOn: $app.searchPage.searchHistory)
                Button("Clear Recent Searches", role: .destructive) {
                    app.clearRecentSearches()
                }
                .disabled(app.recentSearches.isEmpty)
            } header: {
                Text("Search History")
            } footer: {
                Text("Your last \(SharedSettings.recentLimit) searches, from Shiori and from Safari, shown when you tap a search field. Kept on this device only.")
            }
            .listRowBackground(palette.surface)
            .onAppear { app.reloadRecentSearches() }

            Section("Results") {
                Toggle("Web Results", isOn: $app.searchPage.webResults)
                Toggle("Info Box", isOn: $app.searchPage.showInfobox)
                    .disabled(!app.searchPage.webResults)
                Toggle("Related Searches", isOn: $app.searchPage.showRelated)
                    .disabled(!app.searchPage.webResults)
                // Shiori's search page, hosted, and the web app: an
                // answer from the web results, only when opened.
                Toggle("AI Answer", isOn: $app.searchPage.aiAnswer)
                    .disabled(!app.searchPage.webResults)
                Toggle("Thumbnails", isOn: $app.searchPage.showThumbnails)
                    .disabled(!app.searchPage.webResults)
            }
            .disabled(!app.combinedSearch)
            .listRowBackground(palette.surface)

            Section {
                Toggle("Small Web Tab", isOn: $app.searchPage.smallWebTab)
                Picker("Open Results", selection: $app.searchPage.smallWebOpen) {
                    Text("Through the Gateway").tag("gateway")
                    Text("In a Gemini App").tag("direct")
                }
                .disabled(!app.searchPage.smallWebTab)
                LabeledContent("Gateway") {
                    TextField("Gateway", text: $app.searchPage.smallwebURL, prompt: Text("https://smallweb.example/"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textStyle(.body, design: .monospaced)
                }
                .disabled(!app.searchPage.smallWebTab)
            } header: {
                Text("Small Web")
            } footer: {
                Text("Gemini and Gopher search (TLGS, Kennedy, Veronica-2) through your small-web gateway, run when you press Return. Pages read through the gateway are saved to Hister; one opened in a Gemini app such as Lagrange is saved too, if the gateway can fetch it. Without an app for the link, it opens through the gateway.")
            }
            .listRowBackground(palette.surface)

            Section {
                Toggle("In All", isOn: $app.searchPage.histerInGeneral)
                Toggle("Pages Tab", isOn: $app.searchPage.histerTab)
            } header: {
                Text("Your Pages")
            } footer: {
                Text("Pages from Hister: their top matches at the top of All, and the full search on the Pages tab.")
            }
            .disabled(!app.combinedSearch)
            .listRowBackground(palette.surface)

            Section {
                Toggle("In All", isOn: $app.searchPage.vaultInGeneral)
                Toggle("Notes Tab", isOn: $app.searchPage.vaultTab)
            } header: {
                Text("Your Notes")
            } footer: {
                Text("Notes from your Obsidian vault, found by Kura (Settings → Notes).")
            }
            .disabled(!app.combinedSearch)
            .listRowBackground(palette.surface)

            case .preview:
            Section {
                Toggle("Preview Pane", isOn: $app.searchPage.previewPane)
                // Off: a preview fetches nothing from the page's own sites.
                Toggle("Images in Previews", isOn: $app.searchPage.previewImages)
            } footer: {
                Text("Preview Pane shows a page beside the results (Mac and iPad, and Safari's results in a wide window). Images in Previews loads a page's own pictures, the one request that goes to its site; off, a preview reaches only your Hister.")
            }
            .listRowBackground(palette.surface)
            case .notes:
            Section {
                // Each field in a labelled row with its own label hidden: a
                // Mac Form shows a TextField's label as well (it read twice).
                LabeledContent("Obsidian Vault") {
                    TextField("Obsidian Vault", text: $app.searchPage.obsidianVault, prompt: Text("Your vault's name"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                LabeledContent("Kura") {
                    TextField("Kura", text: $app.searchPage.niwaURL, prompt: Text("https://kura.example/"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textStyle(.body, design: .monospaced)
                }
                LabeledContent("Konbini") {
                    TextField("Konbini", text: $app.searchPage.konbiniURL, prompt: Text("https://konbini.example/"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textStyle(.body, design: .monospaced)
                }
            } header: {
                Text("Notes")
            } footer: {
                Text("A note opens in this Obsidian vault; its Kura page (the vault's reader) and Konbini card are linked beside it, in Shiori and in Safari's results.")
            }
            .listRowBackground(palette.surface)

            MachiyaSignInSection()
                .listRowBackground(palette.surface)

            case .safari:
            Section {
                ExtensionSetup()
            } header: {
                Text("Safari Extension")
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
            }
        }
        .formStyle(.grouped)
        .themedBackground()
        .navigationTitle(page.title)
        // A page left saves its fields (the server's and SearXNG's drafts).
        .onDisappear(perform: saveDrafts)
    }

    private var searchingFooter: String {
        var text = "Remember What You Open tells Hister which result you opened for a search, so it comes first next time, in Shiori and in Safari's results. Show Opened shows those pages (first in Your Pages, and the Opened list); off, they're left out. Result Style sets how your pages, notes and opened pages stand apart: a tinted card, a bar down the edge, or nothing. Search Filters adds date, site and visit filters above results. Fold Repeated Sites shows the first of several pages in a row from one site, then “N more”. Labels in Search Page Suggestions lists matching labels and collections first as you type in Shiori (Safari's results page); Shiori's own search fields suggest nothing, and your recent searches are in the sidebar. A label's tag on a result shows all its pages."
        if app.capabilities?.semantic != true {
            text += " Meaning-based search appears here once it's set up on the server."
        }
        return text
    }

    /// An http:// address sends pages and searches unencrypted (only a
    /// VPN would cover them): said plainly, beside the address.
    @ViewBuilder private func unencryptedNote(_ address: String) -> some View {
        if address.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://") {
            Label("Not encrypted: pages and searches go as plain HTTP. Use https:// if the server has it.",
                  systemImage: "lock.open")
                .textStyle(.footnote)
                .foregroundStyle(palette.secondaryText)
        }
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
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failed(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(palette.danger)
            }
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
        guard let client = HisterClient(serverURL: checked) else { return }
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
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
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
                if app.sendStopped, !app.isSending {
                    Label("Hister didn't answer, so these are still waiting. They'll go when it's reachable.",
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
            TextField("NewsBlur", text: $draft, prompt: Text("https://newsblur.example/"))
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .textStyle(.body, design: .monospaced)
                .onSubmit(save)
            FeedButtons(feed: app.feedURL(query: "*", title: "New Pages", source: .all))
            Button("Export Collections as OPML…", systemImage: "list.bullet.rectangle") { opml = makeOPML() }
                .disabled(app.client == nil || (app.rules.aliases.isEmpty && app.rules.labels.isEmpty))
        } header: {
            Text("Feeds")
        } footer: {
            Text("Every search, collection and label has a feed: Export & Feed above for the list you were on (File on the Mac), or a collection's menu. OPML subscribes NewsBlur to all of them at once (NewsBlur → Import). Feeds other than New Pages come from your server's feed service.")
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
