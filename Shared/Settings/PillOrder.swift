import Foundation

/// The pills over a search or list: their order, and which show, from one
/// per-device setting (`SharedSettings.Key.pills`, shared with Safari's
/// results page). It holds the keys in the person's order, a hidden one
/// with a leading "-"; keys it doesn't name keep their default places
/// after it. All is never hidden. `S.pillSetting` / `S.orderPills` /
/// `S.pillsChanged` in search-core.js are the twins, with the same tests.
nonisolated enum PillOrder {
    static let keys = ["all", "pages", "notes", "web", "images", "videos", "news", "smallweb", "files", "code", "opened"]
    static let names = [
        "all": "All", "pages": "Pages", "notes": "Notes", "web": "Web", "images": "Images", "videos": "Videos",
        "news": "News", "smallweb": "Small Web", "files": "Files", "code": "Code", "opened": "Opened",
    ]

    struct Pill: Equatable {
        let key: String
        var shown: Bool
    }

    /// The setting, checked: known keys, each once, All shown; [] for anything else.
    static func clean(_ raw: Any?) -> [String] {
        guard let items = raw as? [Any], items.count <= keys.count else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        for item in items {
            guard let item = item as? String else { return [] }
            let hidden = item.hasPrefix("-")
            let key = hidden ? String(item.dropFirst()) : item
            guard keys.contains(key), seen.insert(key).inserted else { return [] }
            out.append(hidden && key != "all" ? "-" + key : key)
        }
        return out
    }

    /// Every pill in the setting's order, then the rest in theirs.
    static func list(_ raw: [String]) -> [Pill] {
        let named = clean(raw).map { Pill(key: $0.hasPrefix("-") ? String($0.dropFirst()) : $0, shown: !$0.hasPrefix("-")) }
        let known = Set(named.map(\.key))
        return named + keys.filter { !known.contains($0) }.map { Pill(key: $0, shown: true) }
    }

    /// Of the pills a surface has, those to show, in order.
    static func ordered(available: [String], _ raw: [String]) -> [String] {
        let have = Set(available)
        return list(raw).filter { $0.shown && have.contains($0.key) }.map(\.key)
    }

    /// The setting after moving `key` one place (`by` −1 or 1) among
    /// `among`'s keys, and/or showing or hiding it.
    static func changed(_ raw: [String], among: [String], key: String, by: Int = 0, shown: Bool? = nil) -> [String] {
        var list = list(raw)
        guard let at = list.firstIndex(where: { $0.key == key }) else { return clean(raw) }
        if let shown, key != "all" { list[at].shown = shown }
        if by != 0 {
            let visible = list.indices.filter { among.contains(list[$0].key) }
            if let pos = visible.firstIndex(of: at), visible.indices.contains(pos + by) {
                list.swapAt(at, visible[pos + by])
            }
        }
        return list.map { $0.shown ? $0.key : "-" + $0.key }
    }
}
