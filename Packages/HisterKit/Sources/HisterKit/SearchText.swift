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

    /// A Hister search: the last word a prefix, never the notes (Shiori
    /// reads those from Kura, `Notes.exclusion`), and never the watched
    /// files unless it asks for them (the Files pill, `LocalFiles`).
    public static func forHister(_ text: String) -> String {
        let sent = Notes.excluding(prefixLastWord(text.trimmingCharacters(in: .whitespaces), union: true))
        let words = sent.split(whereSeparator: \.isWhitespace)
        if LocalFiles.asked(in: sent) || words.contains(where: { $0 == LocalFiles.exclusion }) { return sent }
        return "\(sent) \(LocalFiles.exclusion)"
    }
}
