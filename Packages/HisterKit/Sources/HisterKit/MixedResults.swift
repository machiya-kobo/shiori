/// All: your pages, notes and media among the web results. `S.mixCounts` and
/// `S.alternate` in search-core.js are the twins, with the same tests.
public enum MixedResults {
    /// How many of yours follow each of `web` web results, `mine` in all,
    /// spread evenly from the first: [1, 0, 1, 0] for 4 and 2, [3, 3] for 2
    /// and 6. With no web results there's no slot: they're the whole list.
    public static func counts(web: Int, mine: Int) -> [Int] {
        let w = max(0, web), m = max(0, mine)
        guard w > 0 else { return [] }
        func ceilDiv(_ a: Int) -> Int { (a + w - 1) / w }
        return (0..<w).map { ceilDiv(($0 + 1) * m) - ceilDiv($0 * m) }
    }

    /// Lists taking turns in order (pages, notes, media: a page first), then whichever are left.
    public static func alternate<T>(_ lists: [T]...) -> [T] {
        var out: [T] = []
        for i in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where i < list.count { out.append(list[i]) }
        }
        return out
    }
}
