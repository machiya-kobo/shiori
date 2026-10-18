import Foundation
import Testing

@testable import HisterKit

/// One item under several addresses, on scripts/same-item-cases.json
/// (search-core.test.mjs runs the same cases on `S.itemKey`, `S.uniqueItems`
/// and `S.foldMine`).
struct SameItemTests {
    struct Cases: Decodable {
        struct Key: Decodable { let name, a, b: String; let same: Bool }
        struct Unique: Decodable { let name: String; let urls: [String]; let want: [Int] }
        struct Fold: Decodable { let name: String; let web, mine: [String]; let rows: [[Int]]; let rest: [Int] }
        let keys: [Key]
        let unique: [Unique]
        let fold: [Fold]
    }

    let cases: Cases

    init() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/same-item-cases.json")
        cases = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: file))
    }

    @Test func oneKeyForOneItem() {
        #expect(!cases.keys.isEmpty)
        for c in cases.keys {
            #expect((SameItem.key(c.a) == SameItem.key(c.b)) == c.same, "\(c.name)")
        }
    }

    @Test func listedOnceTheFirstKept() {
        for c in cases.unique {
            let got = SameItem.unique(Array(c.urls.enumerated()), url: \.element).map(\.offset)
            #expect(got == c.want, "\(c.name)")
        }
        // A page's seen keys carry over to the next.
        var seen = Set<String>()
        _ = SameItem.unique(["https://www.youtube.com/watch?v=dQw4w9WgXcQ"], seen: &seen) { $0 }
        #expect(SameItem.unique(["https://youtu.be/dQw4w9WgXcQ"], seen: &seen) { $0 }.isEmpty)
    }

    @Test func yourPageInTheWebsPlace() {
        for c in cases.fold {
            let got = SameItem.fold(web: c.web, mine: c.mine)
            #expect(got.rows.map { [$0.web, $0.mine ?? -1] } == c.rows, "\(c.name)")
            #expect(got.rest == c.rest, "\(c.name)")
        }
    }
}
