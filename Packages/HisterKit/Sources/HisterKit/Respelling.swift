import Foundation

/// A respelling of a search from the web's related searches, for when
/// Hister (which matches words exactly and has no fuzzy search: `word~2`
/// finds the word "2") found nothing. The same rule as search-core.js's
/// `correctedQuery`: every word must be near one of a suggestion's words,
/// two edits for 5+ letters, one for 4, none below. "pyhton tutorial" with
/// "python tutorial pdf" → "python tutorial".
public enum Respelling {
    public static func corrected(_ query: String, suggestions: [String]) -> String? {
        let words = words(of: query)
        guard !words.isEmpty,
            !words.contains(where: { $0.contains(where: ":\"'*~()|".contains) || $0.hasPrefix("-") || $0.hasPrefix("+") })
        else { return nil }
        for suggestion in suggestions {
            let pool = self.words(of: suggestion)
            var used = Set<Int>()
            var out: [String] = []
            for word in words {
                let room = word.count >= 5 ? 2 : word.count == 4 ? 1 : 0
                var best = -1, bestDistance = Int.max
                for (i, candidate) in pool.enumerated() where !used.contains(i) {
                    let d = editDistance(word, candidate)
                    if d < bestDistance { (best, bestDistance) = (i, d) }
                }
                guard best >= 0, bestDistance <= room else { break }
                used.insert(best)
                out.append(pool[best])
            }
            if out.count == words.count, out != words { return out.joined(separator: " ") }
        }
        return nil
    }

    /// "Did you mean …?": a respelling from the web's autocomplete and
    /// related searches, shown even when the search found something
    /// ("george orewell" finds pages; the web quietly fixes it). Each
    /// suggestion's leading words are candidates, compared without spaces,
    /// so "helloworld" meets "hello world". Within one edit (two past ten
    /// letters) of what was typed; the closest wins, then the one most
    /// suggestions start with. The twin of search-core's `didYouMean`, with
    /// the same tests.
    public static func didYouMean(_ query: String, suggestions: [String]) -> String? {
        let typed = words(of: query).joined(separator: " ")
        guard typed.count >= 4, !typed.contains(where: ":\"'*~()|@!".contains),
              !words(of: query).contains(where: { $0.hasPrefix("-") || $0.hasPrefix("+") })
        else { return nil }
        let bare = typed.replacingOccurrences(of: " ", with: "")
        let room = bare.count >= 10 ? 2 : bare.count >= 5 ? 1 : 0
        var counts: [String: Int] = [:]
        var order: [String] = []
        for suggestion in suggestions {
            let parts = words(of: suggestion)
            guard !parts.isEmpty else { continue }
            for n in 1...parts.count {
                let candidate = parts.prefix(n).joined(separator: " ")
                if counts[candidate] == nil { order.append(candidate) }
                counts[candidate, default: 0] += 1
            }
        }
        var best: (candidate: String, distance: Int, count: Int)?
        for candidate in order where candidate != typed {
            let candidateBare = candidate.replacingOccurrences(of: " ", with: "")
            // A completion ("python tutorial" → "python tutorial pdf") or a
            // cut ("python") isn't a respelling.
            if candidateBare != bare, candidateBare.hasPrefix(bare) || bare.hasPrefix(candidateBare) { continue }
            let count = counts[candidate] ?? 0
            let distance = editDistance(bare, candidateBare)
            // Only spacing differs ("helloworld"): worth it when the web agrees.
            if distance > room || (distance == 0 && count < 2) { continue }
            // Word for word, each changed word stays within its own room: two
            // edits in a long query mustn't both land on one short word
            // ("github machiya" isn't "github machine").
            let typedWords = typed.split(separator: " ").map(String.init)
            let candidateWords = candidate.split(separator: " ").map(String.init)
            if typedWords.count == candidateWords.count,
               zip(typedWords, candidateWords).contains(where: { typedWord, candidateWord in
                   editDistance(typedWord, candidateWord) > (typedWord.count >= 10 ? 2 : typedWord.count >= 5 ? 1 : 0)
               }) { continue }
            if best == nil || distance < best!.distance || (distance == best!.distance && count > best!.count) {
                best = (candidate, distance, count)
            }
        }
        return best?.candidate
    }

    /// Type-ahead: the rest of the first candidate that starts with what's
    /// typed, shown grey after the caret (Tab or → takes it). Recent
    /// searches come first, then the web's autocomplete. "" when none fits,
    /// or for fewer than two characters. The twin of search-core's
    /// `typeAhead`, with the same tests.
    public static func typeAhead(_ typed: String, candidates: [String]) -> String {
        guard typed.trimmingCharacters(in: .whitespaces).count >= 2 else { return "" }
        let lower = typed.lowercased()
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            if trimmed.count > typed.count, trimmed.lowercased().hasPrefix(lower) {
                return String(trimmed.dropFirst(typed.count))
            }
        }
        return ""
    }

    /// Edits between two words: insert, delete, change, or swap two neighbours.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty else { return y.count }
        guard !y.isEmpty else { return x.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    private static func words(of text: String) -> [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
