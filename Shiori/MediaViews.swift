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

/// The Media pill's search: Kind, Never Played and Rating over the list.
struct MediaResults: View {
    let query: String

    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var model: MediaSearchModel
    @State private var filter = Media.Filter()

    init(query: String) {
        self.query = query
        _model = State(initialValue: MediaSearchModel(query: query))
    }

    var body: some View {
        content
            .task(id: query) { await model.load(using: app.media) }
            .topBar { MediaFilterBar(filter: $filter) }
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
            let items = Media.filter(model.items, filter)
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
                    ForEach(items) { MediaItemRow(item: $0) }
                }
                .listStyle(.plain)
                .themedBackground()
            }
        }
    }
}

/// Kind, Never Played and Rating, in one line under the pills, as the Code pill's filters.
struct MediaFilterBar: View {
    @Binding var filter: Media.Filter

    static let kinds = [("films", "Films"), ("tv", "TV"), ("music", "Music"), ("other", "Other")]
    static let ratings = [("loved", "4★+"), ("liked", "3★+"), ("any", "Any Rating"), ("unrated", "Unrated")]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                Menu {
                    Picker("Kind", selection: $filter.kind) {
                        Text("All Kinds").tag(String?.none)
                        ForEach(Self.kinds, id: \.0) { Text($0.1).tag(String?.some($0.0)) }
                    }
                } label: {
                    Label(Self.kinds.first { $0.0 == filter.kind }?.1 ?? "All Kinds", systemImage: "square.stack")
                }
                .quietControl(active: filter.kind != nil)
                Button {
                    filter.played = filter.played == nil ? "never" : nil
                } label: {
                    Label("Never Played", systemImage: filter.played != nil ? "checkmark.circle.fill" : "circle")
                }
                .quietControl(active: filter.played != nil)
                Menu {
                    Picker("Rating", selection: $filter.rated) {
                        Text("All Ratings").tag(String?.none)
                        ForEach(Self.ratings, id: \.0) { Text($0.1).tag(String?.some($0.0)) }
                    }
                } label: {
                    Label(Self.ratings.first { $0.0 == filter.rated }?.1 ?? "Rating", systemImage: "star")
                }
                .quietControl(active: filter.rated != nil)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal)
        }
        .fadesOverflow()
        .padding(.vertical, 2)
    }
}

/// With no media service set up (the pill isn't offered then; a search
/// left from before can still land here).
struct MediaNotSetUp: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Media Set Up", systemImage: "music.note.tv")
        } description: {
            Text("Add Jellyfin, Plex, Koito or Movary in Settings → Search → Media.")
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
/// stars and the others' ratings. A tap opens it in its service (Koito or
/// Movary first, then Jellyfin, then Plex); its menu has every place.
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
    @State private var shelves: MediaShelves?
    @State private var loading = false

    static let periods = [("week", "Week"), ("month", "Month"), ("year", "Year"), ("all_time", "All Time")]

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
                shelf("Now Playing", s.nowPlaying)
                shelf("Recently Played", s.listens)
                shelf("Recently Watched", s.watched)
                if !(s.artists.isEmpty && s.albums.isEmpty && s.tracks.isEmpty) {
                    Section {
                        Picker("Period", selection: $period) {
                            ForEach(Self.periods, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(palette.background)
                    } header: {
                        Text("Your Top")
                    }
                }
                shelf("Top Artists", s.artists)
                shelf("Top Albums", s.albums)
                shelf("Top Tracks", s.tracks)
                shelf("Watchlist", s.watchlist)
                shelf("Recently Added", s.added)
            }
            .listStyle(.plain)
            .themedBackground()
        }
    }

    @ViewBuilder private func shelf(_ title: String, _ items: [MediaItem]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { MediaItemRow(item: $0) }
            } header: {
                Text(title)
            }
        }
    }
}

/// Settings → Search → Media: each service's address and token. A service
/// counts once it has both; the tokens go to the Keychain as typed (masked
/// unless the eye is on), the addresses when the page is left or Return
/// is pressed. Each wants a token of its own for Shiori: Koito's API key,
/// a Movary token, a Jellyfin user's access token, a Plex device token.
struct MediaSettingsSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var addresses: [MediaService: String] = [:]
    @State private var tokens: [MediaService: String] = [:]
    @State private var revealed: Set<MediaService> = []
    @State private var loaded = false

    /// The libraries first, then the histories, as the cards weigh them.
    static let order: [MediaService] = [.jellyfin, .plex, .koito, .movary]
    static let prompts: [MediaService: String] = [
        .jellyfin: "https://jellyfin.example/", .plex: "https://plex.example:32400/",
        .koito: "https://koito.example/", .movary: "https://movary.example/",
    ]
    static let tokenNames: [MediaService: String] = [.jellyfin: "Access Token", .plex: "Token", .koito: "API Key", .movary: "Token"]

    var body: some View {
        Section {
            ForEach(Self.order, id: \.self) { service in
                LabeledContent(service.name) {
                    TextField(service.name, text: address(service), prompt: Text(Self.prompts[service] ?? ""))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textStyle(.body, design: .monospaced)
                        .onSubmit(saveAddresses)
                }
                if !(addresses[service] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    tokenField(service)
                }
            }
        } header: {
            Text("Media")
        } footer: {
            Text("Your libraries (Jellyfin, Plex) and what you played (Koito, Movary), on the Media pill. Shiori only reads them. Tokens stay in this device's Keychain.")
        }
        .listRowBackground(palette.surface)
        .onAppear(perform: load)
        .onDisappear(perform: saveAddresses)
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
        Binding(get: { addresses[service] ?? "" }, set: { addresses[service] = $0 })
    }

    /// A token, masked unless its eye is on, saved as typed (an emptied field removes it).
    private func tokenField(_ service: MediaService) -> some View {
        let text = Binding(
            get: { tokens[service] ?? "" },
            set: {
                tokens[service] = $0
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
                // "Plex Token", not "Token": two rows have that label.
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
