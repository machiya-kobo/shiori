import Testing

@testable import HisterKit

/// The same cases as search-core.test.mjs's "All spreads your pages and notes" test.
struct MixedResultsTests {
    @Test func yoursAreSpreadEvenlyFromTheFirstWebResult() {
        #expect(MixedResults.counts(web: 4, mine: 2) == [1, 0, 1, 0])
        #expect(MixedResults.counts(web: 2, mine: 6) == [3, 3])
        #expect(MixedResults.counts(web: 10, mine: 40) == Array(repeating: 4, count: 10))
        #expect(MixedResults.counts(web: 3, mine: 4) == [2, 1, 1])
        #expect(MixedResults.counts(web: 3, mine: 0) == [0, 0, 0])
        #expect(MixedResults.counts(web: 0, mine: 5) == [])
        #expect(MixedResults.counts(web: 7, mine: 13).reduce(0, +) == 13)
    }

    @Test func pagesAndNotesTakeTurns() {
        #expect(MixedResults.alternate(["p1", "p2", "p3"], ["n1"]) == ["p1", "n1", "p2", "p3"])
        #expect(MixedResults.alternate([String](), ["n1", "n2"]) == ["n1", "n2"])
    }
}
