import Foundation

/// What a search sends, from what was typed. search-core.js's
/// `serverText` / `prefixLastWord` are its twins, with the same tests.
public enum SearchText {
    /// The last word as a prefix ("hist" → "hist*"), as search-as-you-type
    /// does elsewhere: Hister and Kura match whole words, so "hist" finds
    /// nothing that "history" would. Only a
    /// plain word of two or more characters with a letter in it, and not
    /// after a trailing space (the word is finished) or inside a quote.
    ///
    /// `union` (Hister's): the word or its prefix, "(hist|hist*)". Hister's
    /// prefix alone misses most body-text matches of a whole word
    /// ("concurrency*" found 1 page of 45), and its (a|b) is a union, so
    /// this finds everything either does, highlighted. Kura has no (a|b):
    /// it keeps "hist*".
    /// A dangling quote closed: open, it swallowed the exclusions after it
    /// into one phrase, and Hister found nothing. `S.histerText` does the same.
    static func closeQuote(_ text: String) -> String {
        text.filter { $0 == "\"" }.count.isMultiple(of: 2) ? text : text + "\""
    }

    public static func prefixLastWord(_ text: String, union: Bool = false) -> String {
        guard let last = text.last, !last.isWhitespace else { return text }
        guard text.filter({ $0 == "\"" }).count.isMultiple(of: 2) else { return text }
        let start = text.lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? text.startIndex
        let word = text[start...]
        guard word.count >= 2, word.contains(where: \.isLetter),
            word.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return text }
        return union ? text[..<start] + "(\(word)|\(word)*)" : text + "*"
    }

    // MARK: Nogon's operators (v0.21+): AND, OR and NOT, uppercase
    // NOT binds tighter than AND, then OR, and a query an operator leaves
    // without a term fails whole (400). search-core.js's quoteStrayOperators
    // and groupWords are the twins, on scripts/operator-cases.json.

    private static let operators: Set<Substring> = ["AND", "OR", "NOT"]

    /// The words, each with whether it's an operator (outside a quote).
    private static func operatorWords(_ text: String) -> [(word: Substring, op: Bool)] {
        var quoted = false
        return text.split(whereSeparator: \.isWhitespace).map { word in
            let op = !quoted && operators.contains(word)
            if !word.filter({ $0 == "\"" }).count.isMultiple(of: 2) { quoted.toggle() }
            return (word, op)
        }
    }

    /// A stray AND, OR or NOT quoted, so it's searched as a word: one with
    /// no term to join or negate ("AND", "rock AND", "NOT OR x") fails the
    /// whole search. Unchanged, spaces and all, when nothing is stray.
    public static func quoteStrayOperators(_ text: String) -> String {
        let words = operatorWords(text)
        func isOp(_ i: Int, _ names: Set<Substring>) -> Bool {
            words.indices.contains(i) && words[i].op && names.contains(words[i].word)
        }
        var changed = false
        let out = words.indices.map { i -> String in
            let (word, op) = words[i]
            guard op else { return String(word) }
            let last = i == words.count - 1
            let stray = word == "NOT"
                ? last || isOp(i + 1, ["AND", "OR"])
                : i == 0 || last || isOp(i - 1, operators) || isOp(i + 1, ["AND", "OR"])
            if stray { changed = true }
            return stray ? "\"\(word)\"" : String(word)
        }
        return changed ? out.joined(separator: " ") : text
    }

    /// The words in parentheses when an OR joins them, so a term added after
    /// them (the notes' exclusion, a label, a filter) applies to all: "a OR
    /// b -label:vault" is "a OR (b -label:vault)", which lets a's notes in.
    public static func groupWords(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        var depth = 0
        var quoted = false
        var or = false
        for (word, op) in operatorWords(t) {
            if op, word == "OR", depth == 0 { or = true }
            for ch in word {
                if ch == "\"" { quoted.toggle() }
                else if !quoted, ch == "(" { depth += 1 }
                else if !quoted, ch == ")" { depth = max(0, depth - 1) }
            }
        }
        return or ? "(\(t))" : t
    }

    /// Typed words as Nogon takes them: a dangling quote closed, stray
    /// operators quoted, the last word a prefix (`prefix`), grouped.
    public static func histerWords(_ text: String, prefix: Bool = true) -> String {
        let t = quoteStrayOperators(closeQuote(text.trimmingCharacters(in: .whitespaces)))
        return groupWords(prefix ? prefixLastWord(t, union: true) : t)
    }

    /// A Hister search: the last word a prefix, never the notes (Shiori
    /// reads those from Kura, `Notes.exclusion`), and never the watched
    /// files unless it asks for them (the Files pill, `LocalFiles`).
    public static func forHister(_ text: String) -> String {
        var sent = Notes.excluding(histerWords(text))
        let words = sent.split(whereSeparator: \.isWhitespace)
        if !LocalFiles.asked(in: sent), !words.contains(where: { $0 == LocalFiles.exclusion }) { sent += " \(LocalFiles.exclusion)" }
        // Never the code (code-import's) unless it asks: the Code pill.
        if !CodeDocs.asked(in: sent), !words.contains(where: { $0 == CodeDocs.exclusion }) { sent += " \(CodeDocs.exclusion)" }
        return sent
    }
}
