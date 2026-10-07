import HisterKit
import SwiftUI

/// A collection's own symbol and colour, so arts, games and tech don't all
/// wear the same stack: from a word in its name where one fits, else one
/// picked by the name, in the label chip colour the name hashes to (the
/// web app and the search page use the same table, `S.collectionIcon`).
enum CollectionIcon {
    /// A collection's name as shown: Hister's alias keyword without its
    /// "@" (the aliases are "@lanterns", "@kyoto"…, so a plain word in a search
    /// stays a word: an alias replaces its keyword anywhere in a query).
    static func title(for name: String) -> String {
        name.hasPrefix("@") ? String(name.dropFirst()) : name
    }

    private static let byWord: [(words: [String], symbol: String)] = [
        (["retro", "vintage"], "clock.arrow.circlepath"),
        (["unix", "linux", "bsd", "terminal", "shell"], "apple.terminal"),
        (["smallweb", "small-web", "indieweb", "web"], "globe"),
        (["gear", "hardware", "tools"], "wrench.and.screwdriver"),
        (["culture"], "theatermasks"),
        (["homelab"], "server.rack"),
        (["art", "design", "draw", "paint"], "paintpalette"),
        (["game", "gaming", "play"], "gamecontroller"),
        (["k8s", "kube", "cluster", "infra", "ops"], "helm"),
        (["kept", "keep", "saved", "save", "star", "fav"], "bookmark"),
        (["life", "home", "family", "garden"], "leaf"),
        (["tech", "code", "dev", "program", "software", "computer"], "cpu"),
        (["book", "read", "library"], "books.vertical"),
        (["music", "audio", "song"], "music.note"),
        (["food", "recipe", "cook"], "fork.knife"),
        (["travel", "trip"], "airplane"),
        (["work", "job", "career"], "briefcase"),
        (["news"], "newspaper"),
        (["film", "movie", "tv", "video"], "film"),
        (["health", "fit", "sport"], "heart"),
        (["money", "finance", "budget"], "dollarsign.circle"),
        (["photo", "camera"], "camera"),
        (["science", "research"], "atom"),
        (["server", "selfhost", "homelab"], "server.rack"),
        (["security", "privacy"], "lock.shield"),
    ]
    private static let spare = ["square.stack", "tray.2", "archivebox", "folder", "shippingbox", "square.grid.2x2"]

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if let match = byWord.first(where: { $0.words.contains { lower.contains($0) } }) { return match.symbol }
        let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return spare[Int(hash % UInt32(spare.count))]
    }
}

/// A collection's row: its symbol in its colour, then its name.
struct CollectionLabel: View {
    let name: String
    @Environment(\.palette) private var palette

    var body: some View {
        Label {
            Text(CollectionIcon.title(for: name))
        } icon: {
            RowIcon(symbol: CollectionIcon.symbol(for: name), color: palette.chipColor(for: name))
        }
    }
}

/// A list row's icon, every symbol in the same square: a wide one
/// (culture's masks, games' controller) drawn at its natural size started
/// further left than a narrow one, and the sidebar's icons read as a
/// wobbly edge. The web app's `.nav-icon` matches.
struct RowIcon: View {
    let symbol: String
    var color: Color?
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 17
    @Environment(\.macTextScale) private var macScale

    var body: some View {
        let image = Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .frame(width: size * macScale, height: size * macScale)
        if let color {
            image.foregroundStyle(color)
        } else {
            // The sidebar's own tint, white on the selected row.
            image
        }
    }
}

/// A colour dot in the same square as `RowIcon`, so labels line up with
/// the rows above them.
struct RowDot: View {
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 17
    @Environment(\.macTextScale) private var macScale

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9 * macScale, height: 9 * macScale)
            .frame(width: size * macScale, height: size * macScale)
    }
}
