import Foundation
import HisterKit

/// What the "↑ N New Items" banner counts on a newest-first list: results
/// not on screen that are newer than the newest one shown. Not on screen
/// alone isn't enough: the Library's All holds back the first pages'
/// results it can't place yet (`NewestFirstMerge`), mostly older notes,
/// and those were counted as new on every check, though a reload found
/// nothing new.
enum NewItems {
    static func count(_ candidates: [StoredPage], seen: Set<String>, newestShown: Date?) -> Int {
        candidates.filter { page in
            !seen.contains(page.url) && newestShown.map { page.updated > $0 } ?? true
        }.count
    }
}
