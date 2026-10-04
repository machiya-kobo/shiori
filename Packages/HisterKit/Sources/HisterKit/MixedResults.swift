/// All: your pages and notes among the web results. `S.mixCounts` and
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

    /// Pages and notes taking turns (a page first), then whichever is left.
    public static func alternate<T>(_ pages: [T], _ notes: [T]) -> [T] {
        var out: [T] = []
        for i in 0..<max(pages.count, notes.count) {
            if i < pages.count { out.append(pages[i]) }
            if i < notes.count { out.append(notes[i]) }
        }
        return out
    }
}
