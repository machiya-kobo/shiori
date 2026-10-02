import Foundation

/// Completions for the word being typed in a Hister query: the server's
/// aliases, `label:` values, and the query operators.
public struct QuerySuggestion: Sendable, Equatable, Identifiable {
    public var id: String { completion }
    /// What the list shows, e.g. `label:books` or `tech`.
    public var title: String
    /// A short explanation, e.g. the alias expansion.
    public var detail: String
    /// The whole query with the current word completed.
    public var completion: String

    public init(title: String, detail: String, completion: String) {
        self.title = title
        self.detail = detail
        self.completion = completion
    }
}

public enum QuerySuggestions {
    /// Operators worth offering, with what they do. Hister matches values
    /// exactly: `domain:` is the whole host, `label:` is case-sensitive,
    /// and a "/" in a value never matches.
    static let operators: [(token: String, detail: String)] = [
        ("label:", "Pages with this topic label"),
        ("domain:", "Exact host, e.g. www.example.com"),
        ("url:", "Match the URL"),
        ("added:>", "Added after a date, e.g. added:>2026-01-01"),
        ("added:<", "Added before a date"),
    ]

    /// `domains`: sites Hister has pages from, most pages first, for `domain:`.
    public static func suggest(for query: String, rules: Rules, domains: [String] = [], limit: Int = 8) -> [QuerySuggestion] {
        let (head, word) = split(query)
        guard !word.isEmpty else { return [] }
        let lowered = word.lowercased()
        var out: [QuerySuggestion] = []

        for field in ["domain:", "-domain:"] where lowered.hasPrefix(field) {
            let prefix = String(lowered.dropFirst(field.count))
            for domain in domains where domain.contains(prefix) && domain != prefix {
                let token = field + domain
                out.append(QuerySuggestion(
                    title: token, detail: field.hasPrefix("-") ? "Leave out this site" : "Site", completion: head + token + " "))
            }
            return Array(out.prefix(limit))
        }

        if lowered.hasPrefix("label:") {
            let prefix = String(word.dropFirst("label:".count))
            for label in rules.labels where label.hasPrefix(prefix) && label != prefix {
                let token = "label:\(label)"
                out.append(QuerySuggestion(title: token, detail: "Label", completion: head + token + " "))
            }
            return Array(out.prefix(limit))
        }

        for (name, expansion) in rules.aliases.sorted(by: { $0.key < $1.key })
        where name.hasPrefix(lowered) && name != lowered {
            out.append(QuerySuggestion(title: name, detail: expansion, completion: head + name + " "))
        }
        for op in operators where op.token.hasPrefix(lowered) && op.token != lowered {
            out.append(QuerySuggestion(title: op.token, detail: op.detail, completion: head + op.token))
        }
        return Array(out.prefix(limit))
    }

    /// The query up to the last word, and the last word being typed.
    static func split(_ query: String) -> (head: String, word: String) {
        guard let last = query.last, !last.isWhitespace else { return (query, "") }
        if let space = query.lastIndex(where: \.isWhitespace) {
            return (String(query[...space]), String(query[query.index(after: space)...]))
        }
        return ("", query)
    }
}
