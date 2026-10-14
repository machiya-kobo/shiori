import HisterKit
import Observation
import SwiftUI

// Media (docs/media.md): your Jellyfin and Plex libraries and what you played
// (Koito for music, Movary for films), one card per item, as the web app and
// the hosted search page show them. Private like a work note: nothing of it
// goes to Hister (no Remember What You Open), a model, a cache, an export or
// a feed, and no preview. A card opens in its service in the browser.

/// One search across the media services set up (`MediaClient`), run on
/// submit only (Return or the pill), as every search in the apps.
@Observable
final class MediaSearchModel {
    let query: String
    private(set) var items: [MediaItem] = []
    /// The services that failed ("Plex didn't answer"): said, not fatal.
    private(set) var failures: [String] = []
    private(set) var phase: ResultsModel.Phase = .idle

    init(query: String) {
        self.query = query
    }

    func load(using client: MediaClient?) async {
        guard let client else {
            phase = .failed(.unreachable)
            return
        }
        if items.isEmpty { phase = .loading }
        let results = await client.search(query)
        guard !Task.isCancelled else { return }
        items = results.items
        failures = results.failures
        phase = .loaded
    }
}

/// The Media pill's search, under the same Sort · Group · Filter bar as
/// the other pills (`MediaControls`).
struct MediaResults: View {
    let query: String

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var model: MediaSearchModel
    @State private var filter = Media.Filter()
    @AppStorage("mediaOrder") private var order = "best"
    @AppStorage("mediaGrouping") private var grouping = ""

    init(query: String) {
        self.query = query
        _model = State(initialValue: MediaSearchModel(query: query))
    }

    var body: some View {
        content
            .task(id: query) { await model.load(using: app.media) }
            .topBar { MediaControls(order: $order, grouping: $grouping, filter: $filter, items: model.items) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
        case .failed:
            MediaNotSetUp()
        case .loaded:
            let items = Media.sort(Media.filter(model.items, filter, now: Int(Date().timeIntervalSince1970)), order)
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("No Media Found", systemImage: "music.note.list")
                } description: {
                    Text(model.failures.isEmpty ? "Nothing in your media matches “\(query)”." : model.failures.joined(separator: " · "))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
            } else if items.isEmpty {
                ContentUnavailableView(
                    "Nothing Matches These Filters", systemImage: "line.3.horizontal.decrease",
                    description: Text("Clear a filter to see more."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
            } else {
                List {
                    if !model.failures.isEmpty { MediaFailuresRow(failures: model.failures) }
                    let groups = Media.groups(items, grouping, offsetMinutes: TimeZone.current.secondsFromGMT() / 60)
                    ForEach(groups, id: \.title) { group in
                        if group.title.isEmpty {
                            ForEach(group.items) { MediaItemRow(item: $0) }
                        } else {
                            Section {
                                ForEach(group.items) { MediaItemRow(item: $0) }
                            } header: {
                                Text(group.title)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .themedBackground()
            }
        }
    }
}

/// Media's bar, the other pills' Sort · Group · Filter: Sort (Best Match on
/// a search, Newest, Oldest, Most Played, Top Rated, Title, Year, Recently
/// Added; browsing, the top lists' period in a submenu), Group (Shelves when
/// browsing, No Groups, Day, Month, Kind, Played), and Filter, a sheet with a
/// count beside every choice (Date, Kind, Played, Rating, Service), with
/// chips to remove each and Clear.
struct MediaControls: View {
    @Binding var order: String
    @Binding var grouping: String
    var period: Binding<String>? = nil
    @Binding var filter: Media.Filter
    /// Every item before the filters, for the sheet's counts.
    let items: [MediaItem]
    /// Browsing: no Best Match, and Shelves first among the groups.
    var browsing = false

    @Environment(\.palette) private var palette
    @State private var filtering = false

    static let periods = [("week", "This Week"), ("month", "This Month"), ("year", "This Year"), ("all_time", "All Time")]
    private var orders: [(String, String)] { browsing ? Media.orders.filter { $0.0 != "best" } : Media.orders }
    private var groupings: [(String, String)] { browsing ? [("shelves", "Shelves")] + Media.groupings : Media.groupings }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                sortMenu
                groupMenu
                Button {
                    filtering = true
                } label: {
                    Label(filter.isEmpty ? "Filter" : "Filtered", systemImage: filter.isEmpty
                        ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .quietControl(active: !filter.isEmpty)
                .help("Filter")
                .accessibilityLabel(filter.isEmpty ? "Filter" : "Filter, filters on")
                ForEach(Media.filters, id: \.key) { section in
                    if let value = filter[section.key], let name = section.choices.first(where: { $0.0 == value })?.1 {
                        chip(name) { filter[section.key] = nil }
                    }
                }
                if !filter.isEmpty {
                    Button("Clear") { filter = Media.Filter() }
                        .buttonStyle(.borderless)
                        .textStyle(.subheadline)
                }
            }
            .padding(.horizontal)
            // Level with the Code pill's first row under the pills (it sat 3 points lower).
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .fadesOverflow()
        .endsTopBar()
        .sheet(isPresented: $filtering) { MediaFilterSheet(filter: $filter, items: items) }
    }

    private var sortMenu: some View {
        let name = orders.first { $0.0 == order }?.1 ?? orders[0].1
        return Menu {
            Picker("Sort", selection: $order) {
                ForEach(orders, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.inline)
            // Browsing: the period of Top Artists, Albums and Tracks, in a
            // submenu that names it: four bare periods under the sorts read
            // as Group's Day and Month.
            if let period {
                Divider()
                Menu("Top Lists: \(Self.periods.first { $0.0 == period.wrappedValue }?.1 ?? "This Month")") {
                    Picker("Top Lists", selection: period) {
                        ForEach(Self.periods, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            Label(name, systemImage: "arrow.up.arrow.down")
        }
        .quietControl()
        .help("Sort")
        .accessibilityLabel("Sort: \(name)")
    }

    /// Day and Month follow when you played: choosing one sorts Newest (unless Oldest), as on the other pills.
    private var groupMenu: some View {
        let name = groupings.first { $0.0 == grouping }?.1 ?? "No Groups"
        return Menu {
            Picker("Group", selection: Binding(get: { grouping }, set: { new in
                grouping = new
                if new == "day" || new == "month", order != "oldest" { order = "newest" }
            })) {
                ForEach(groupings, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(grouping.isEmpty ? "Group" : name, systemImage: "rectangle.3.group")
        }
        .quietControl(active: !grouping.isEmpty && grouping != "shelves")
        .help("Group")
        .accessibilityLabel("Group: \(name)")
    }

    private func chip(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.accent.opacity(0.35))
        .foregroundStyle(palette.text)
        .accessibilityLabel("\(text), remove filter")
        .help("Remove this filter")
    }
}

/// Media's Filter, as the other pills' sheet: Date, Kind, Played, Rating and
/// Service, each choice with how many it keeps (the other filters held); a
/// tap applies it or takes it off.
struct MediaFilterSheet: View {
    @Binding var filter: Media.Filter
    let items: [MediaItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        let counts = Media.facets(items, filter, now: Int(Date().timeIntervalSince1970))
        NavigationStack {
            List {
                ForEach(Media.filters, id: \.key) { section in
                    Section(section.title) {
                        row(section.key == "date" ? "Any Time" : "Any", count: nil, on: filter[section.key] == nil) { filter[section.key] = nil }
                        ForEach(section.choices, id: \.0) { value, name in
                            row(name, count: counts[section.key]?[value], on: filter[section.key] == value) {
                                filter[section.key] = filter[section.key] == value ? nil : value
                            }
                        }
                    }
                }
            }
            .themedBackground()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Filter")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !filter.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") { filter = Media.Filter() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 520)
        #endif
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, count: Int?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let count {
                    Text(count.formatted())
                        .foregroundStyle(palette.secondaryText)
                        .monospacedDigit()
                }
                if on {
                    Image(systemName: "checkmark")
                        .foregroundStyle(palette.accent)
                        .accessibilityLabel("Applied")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.surface)
    }
}

/// With no media service set up (the pill isn't offered then; a search
/// left from before can still land here).
struct MediaNotSetUp: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Media Set Up", systemImage: "music.note.tv")
        } description: {
            Text("Add Jellyfin, Plex, Koito or Movary in Settings → Media.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
    }
}

struct MediaFailuresRow: View {
    let failures: [String]
    @Environment(\.palette) private var palette

    var body: some View {
        Text(failures.joined(separator: " · "))
            .textStyle(.footnote)
            .foregroundStyle(palette.secondaryText)
            .listRowBackground(palette.background)
    }
}

/// One card: its art, the title, what it is, when you played it, your
/// stars and the others' ratings. A tap opens it in its service (films and
/// TV in Plex first, music in Koito; `Media.places`); its menu has every place.
struct MediaItemRow: View {
    let item: MediaItem

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    private var places: (href: String, places: [Media.Place]) { Media.places(item) }

    var body: some View {
        let places = places
        Button {
            if let url = SafeHref.url(places.href) { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                MediaArt(item: item)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .textStyle(.headline)
                        .foregroundStyle(palette.accent)
                        .lineLimit(2)
                    Text(Media.subtitle(item))
                        .textStyle(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                    if !playedLine.characters.isEmpty {
                        Text(playedLine)
                            .textStyle(.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(ResultBar(kind: .media, palette: palette, style: app.rowStyle.resultStyle))
        .resultSeparator(app.rowStyle.resultStyle)
        .help(places.places.first.map { "Open in \($0.name)" } ?? "")
        .contextMenu {
            ForEach(places.places, id: \.key) { place in
                if let url = SafeHref.url(place.url) {
                    Button("Open in \(place.name)") { openURL(url) }
                }
            }
            if let url = SafeHref.url(places.href) {
                Divider()
                Button("Copy Link", systemImage: "link") { Pasteboard.copy(url) }
            }
        }
    }

    /// "Played 3× · Last Mar 6, 2014 · ★★★★½ · RT 93%": your stars in yellow, as the web pages'.
    private var playedLine: AttributedString {
        var parts: [AttributedString] = []
        let played = Media.playedLine(item, offsetMinutes: TimeZone.current.secondsFromGMT() / 60)
        if !played.isEmpty { parts.append(AttributedString(played)) }
        let stars = Media.stars(item.rating.map(Double.init))
        if !stars.isEmpty {
            var s = AttributedString(stars)
            s.foregroundColor = palette.tint(.yellow)
            parts.append(s)
        }
        let outside = Media.outsideLine(item)
        if !outside.isEmpty { parts.append(AttributedString(outside)) }
        var out = AttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 { out += AttributedString(" · ") }
            out += part
        }
        return out
    }
}

/// A card's art: an album's cover square, a film's or show's poster 2:3,
/// fetched by `MediaClient.imageData` (the services and TMDB only; Plex's
/// token in a header), only with Settings → Results → Images in Previews on.
struct MediaArt: View {
    let item: MediaItem

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var image: Image?

    private var poster: Bool { ["film", "show", "episode", "collection", "other"].contains(item.kind) }
    private var symbol: String {
        switch item.kind {
        case "film", "collection", "other": "film"
        case "show", "episode": "tv"
        case "artist": "music.mic"
        case "album": "square.stack"
        default: "music.note"
        }
    }

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.surface)
            }
        }
        .frame(width: poster ? 40 : 48, height: poster ? 60 : 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: item.image) { image = await load() }
    }

    private func load() async -> Image? {
        guard app.searchPage.previewImages, !item.image.isEmpty, let client = app.media else { return nil }
        if let cached = MediaArtCache.shared.object(forKey: item.image as NSString) { return Image(platformImage: cached) }
        guard let data = await client.imageData(item.image), let platform = PlatformImage(data: data) else { return nil }
        MediaArtCache.shared.setObject(platform, forKey: item.image as NSString)
        return Image(platformImage: platform)
    }
}

/// The art seen this session, in memory only (never written to the device).
@MainActor
enum MediaArtCache {
    static let shared: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 300
        return cache
    }()
}

/// All's Your Media: the top five under a heading in the Media pill's
/// purple, its count leading to the pill.
struct MediaAllSection: View {
    let model: MediaSearchModel
    let showScope: (SearchScope) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            Button {
                showScope(.media)
            } label: {
                HStack(spacing: 8) {
                    Text("Your Media")
                        .textStyle(.subheadline, weight: .semibold)
                    Spacer()
                    Text("\(model.items.count) \(model.items.count == 1 ? "result" : "results") ›")
                        .textStyle(.footnote)
                }
                .foregroundStyle(palette.tint(SearchScope.media.tint))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(palette.surface.overlay(palette.tint(SearchScope.media.tint).opacity(0.12)))
            ForEach(model.items.prefix(5)) { MediaItemRow(item: $0) }
        }
    }
}

/// The Media pill before a search: what's playing, what you played and
/// watched lately, your top artists, albums and tracks for a period, your
/// watchlist and what's new in your libraries.
struct MediaShelvesView: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @AppStorage("mediaTopPeriod") private var period = "month"
    @AppStorage("mediaBrowseOrder") private var order = "newest"
    @AppStorage("mediaBrowseGrouping") private var grouping = "shelves"
    @State private var shelves: MediaShelves?
    @State private var filter = Media.Filter()

    /// Everything the shelves hold, one card per item (Recently Listened's listens merged with the top lists' counts).
    private var everything: [MediaItem] {
        guard let s = shelves else { return [] }
        return Media.merge([s.added, s.nowPlaying, s.listens, s.watched, s.artists, s.albums, s.tracks, s.watchlist])
    }

    var body: some View {
        Group {
            if app.media == nil {
                MediaNotSetUp()
            } else if let shelves {
                list(shelves)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
            }
        }
        .task(id: period) { await load() }
        .pullToRefresh { await load() }
        .topBar { MediaControls(order: $order, grouping: $grouping, period: $period, filter: $filter, items: everything, browsing: true) }
    }

    private func load() async {
        guard let client = app.media else { return }
        let fresh = await client.browse(period: period)
        guard !Task.isCancelled else { return }
        shelves = fresh
    }

    @ViewBuilder private func list(_ s: MediaShelves) -> some View {
        let empty = [s.nowPlaying, s.listens, s.watched, s.artists, s.albums, s.tracks, s.watchlist, s.added].allSatisfy(\.isEmpty)
        if empty {
            ContentUnavailableView {
                Label("Nothing Here Yet", systemImage: "music.note.tv")
            } description: {
                Text(s.failures.isEmpty ? "What you play and watch shows up here." : s.failures.joined(separator: " · "))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedBackground()
        } else {
            List {
                if !s.failures.isEmpty { MediaFailuresRow(failures: s.failures) }
                if grouping != "shelves" {
                    let now = Int(Date().timeIntervalSince1970)
                    let groups = Media.groups(Media.sort(Media.filter(everything, filter, now: now), order), grouping,
                                              offsetMinutes: TimeZone.current.secondsFromGMT() / 60)
                    ForEach(groups, id: \.title) { group in
                        if group.title.isEmpty {
                            ForEach(group.items) { MediaItemRow(item: $0) }
                        } else {
                            Section { ForEach(group.items) { MediaItemRow(item: $0) } } header: { Text(group.title) }
                        }
                    }
                } else {
                shelf("Now Playing", s.nowPlaying)
                shelf("Recently Listened", s.listens)
                shelf("Recently Watched", s.watched)
                shelf("Top Artists", s.artists)
                shelf("Top Albums", s.albums)
                shelf("Top Tracks", s.tracks)
                shelf("Watchlist", s.watchlist)
                shelf("Recently Added", s.added)
                }
            }
            .listStyle(.plain)
            .themedBackground()
        }
    }

    @ViewBuilder private func shelf(_ title: String, _ all: [MediaItem]) -> some View {
        let items = Media.filter(all, filter, now: Int(Date().timeIntervalSince1970))
        if !items.isEmpty {
            Section {
                ForEach(items) { MediaItemRow(item: $0) }
            } header: {
                Text(title)
            }
        }
    }
}

/// Settings → Media: one section per service, each its address, its token
/// and Test Connection. A service counts once it has both; tokens go to the
/// Keychain as typed (masked unless the eye is on), addresses on Return, on
/// Test Connection or when the page is left. Each wants a token of its own
/// for Shiori: a Jellyfin user's access token, a Plex device token, Koito's
/// API key, a Movary token.
struct MediaSettingsPage: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var addresses: [MediaService: String] = [:]
    @State private var tokens: [MediaService: String] = [:]
    @State private var revealed: Set<MediaService> = []
    @State private var checks: [MediaService: MediaClient.Check] = [:]
    @State private var checking: Set<MediaService> = []
    @State private var loaded = false

    /// The libraries first, then the histories, as the cards weigh them.
    static let order: [MediaService] = [.jellyfin, .plex, .koito, .movary]
    static let prompts: [MediaService: String] = [
        .jellyfin: "https://jellyfin.example/", .plex: "https://plex.example:32400/",
        .koito: "https://koito.example/", .movary: "https://movary.example/",
    ]
    static let tokenNames: [MediaService: String] = [.jellyfin: "Access Token", .plex: "Token", .koito: "API Key", .movary: "Token"]
    static let roles: [MediaService: String] = [
        .jellyfin: "Your library. A user of its own for Shiori, not an admin: Jellyfin's API keys are admin keys.",
        .plex: "Your library, and what you watched on TV. A device token for Shiori, revocable under Authorized Devices.",
        .koito: "What you played: music. An API key for Shiori.",
        .movary: "What you watched: films, and your ratings. A token for Shiori.",
    ]

    var body: some View {
        Section {
            Text("Your libraries and what you played, on the Media pill. Shiori only reads them, and tokens stay in this device's Keychain.")
                .textStyle(.callout)
                .foregroundStyle(palette.secondaryText)
        }
        .listRowBackground(palette.surface)
        .onAppear(perform: load)
        .onDisappear(perform: saveAddresses)
        ForEach(Self.order, id: \.self) { service in
            Section {
                // Its switch first, as every Settings section: off keeps the
                // address and token, and the service isn't asked.
                Toggle(service.name, isOn: Binding(
                    get: { !app.mediaOff.contains(service) },
                    set: { on in
                        if on { app.mediaOff.remove(service) } else { app.mediaOff.insert(service) }
                    }))
                if !app.mediaOff.contains(service) {
                    SettingsField(label: "Address", text: address(service), prompt: Self.prompts[service] ?? "",
                                  spoken: "\(service.name) Address", submit: saveAddresses)
                    UnencryptedNote(address: addresses[service] ?? "", carries: "your token and what you played")
                    tokenField(service)
                    checkRow(service)
                }
            } header: {
                Text(service.name)
            } footer: {
                Text(Self.roles[service] ?? "")
            }
            .listRowBackground(palette.surface)
        }
    }

    private func load() {
        guard !loaded else { return }
        addresses = app.mediaAddresses
        tokens = Dictionary(uniqueKeysWithValues: MediaService.allCases.map { ($0, MediaKeychain.read($0)) })
        loaded = true
    }

    private func saveAddresses() {
        guard loaded else { return }
        var cleaned = app.mediaAddresses
        for (service, value) in addresses { cleaned[service] = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if cleaned != app.mediaAddresses { app.mediaAddresses = cleaned }
    }

    private func address(_ service: MediaService) -> Binding<String> {
        Binding(get: { addresses[service] ?? "" }, set: {
            addresses[service] = $0
            checks[service] = nil
        })
    }

    /// Test Connection, and what it found, on one row.
    private func checkRow(_ service: MediaService) -> some View {
        let account = MediaAccount(base: addresses[service] ?? "", token: tokens[service] ?? "")
        return HStack(spacing: 10) {
            Button("Test Connection") { test(service) }
                .disabled(account == nil || checking.contains(service))
            if checking.contains(service) {
                ProgressView().controlSize(.small)
            } else if let check = checks[service] {
                Label(text(check, service), systemImage: works(check) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .textStyle(.callout)
                    .foregroundStyle(works(check) ? palette.tint(.green) : palette.danger)
                    .lineLimit(2)
            } else if account == nil {
                Text((addresses[service] ?? "").isEmpty ? "Not set up" : "Needs a token")
                    .textStyle(.callout)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func works(_ check: MediaClient.Check) -> Bool {
        if case .works = check { return true }
        return false
    }

    private func text(_ check: MediaClient.Check, _ service: MediaService) -> String {
        switch check {
        case .works(let what): "Works · \(what)"
        case .refused: "\(service.name) refused this token"
        case .unreachable: "No answer: check the address and your network"
        case .unexpected(let status): "That doesn't answer as \(service.name) does" + (status.map { " (HTTP \($0))" } ?? "")
        }
    }

    private func test(_ service: MediaService) {
        saveAddresses()
        guard let account = MediaAccount(base: addresses[service] ?? "", token: tokens[service] ?? "") else { return }
        checking.insert(service)
        checks[service] = nil
        Task {
            let result = await MediaClient(accounts: [service: account]).check(service)
            checks[service] = result
            checking.remove(service)
        }
    }

    /// A token, masked unless its eye is on, saved as typed (an emptied field removes it).
    private func tokenField(_ service: MediaService) -> some View {
        let text = Binding(
            get: { tokens[service] ?? "" },
            set: {
                tokens[service] = $0
                checks[service] = nil
                if loaded { app.setMediaToken($0, for: service) }
            })
        let title = "\(service.name) \(Self.tokenNames[service] ?? "Token")"
        return LabeledContent(Self.tokenNames[service] ?? "Token") {
            HStack(spacing: 8) {
                Group {
                    if revealed.contains(service) {
                        TextField(title, text: text, prompt: Text("Required"))
                    } else {
                        SecureField(title, text: text, prompt: Text("Required"))
                    }
                }
                .labelsHidden()
                // "Plex Token", not "Token": two services call it that.
                .accessibilityLabel(title)
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .autocorrectionDisabled()
                .textStyle(.callout, design: .monospaced)
                Button {
                    if revealed.contains(service) { revealed.remove(service) } else { revealed.insert(service) }
                } label: {
                    Image(systemName: revealed.contains(service) ? "eye.slash" : "eye")
                        .contentShape(.interaction, Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
                .help(revealed.contains(service) ? "Hide Token" : "Show Token")
                .accessibilityLabel(revealed.contains(service) ? "Hide \(title)" : "Show \(title)")
            }
        }
    }
}
