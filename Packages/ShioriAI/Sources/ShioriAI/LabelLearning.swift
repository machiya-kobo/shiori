import Foundation

/// A labelled page like the one being classified: the user's own filing is
/// the best guide to theirs (docs/ai.md, "learning from the user").
public struct LabelNeighbour: Sendable, Equatable, Codable {
    public var title: String
    public var host: String
    public var label: String

    public init(title: String, host: String, label: String) {
        self.title = title
        self.host = host
        self.label = label
    }
}

/// The user overruling a suggestion: they chose another label, or undid
/// an automatic one (`chosen` empty). Recent ones go back into the prompt
/// so a mistake isn't repeated.
public struct LabelCorrection: Sendable, Equatable, Codable {
    public var title: String
    public var host: String
    public var suggested: String
    public var chosen: String

    public init(title: String, host: String, suggested: String, chosen: String) {
        self.title = title
        self.host = host
        self.suggested = suggested
        self.chosen = chosen
    }
}

/// How far each label can be trusted, learnt from what the user does with
/// its suggestions and automatic applications.
public struct LabelTrust: Sendable, Equatable {
    /// Labels whose automatic applications the user keeps undoing: never
    /// applied unattended, only suggested.
    public var held: Set<String>
    /// Labels whose suggestions the user always accepts: applied on a
    /// cloud "medium" too.
    public var trustedAtMedium: Set<String>

    public init(held: Set<String> = [], trustedAtMedium: Set<String> = []) {
        self.held = held
        self.trustedAtMedium = trustedAtMedium
    }
}

/// What the user did with one label, over time.
public struct LabelStat: Sendable, Equatable, Codable {
    public var applied = 0
    public var undone = 0
    public var accepted = 0
    public var overridden = 0

    public init(applied: Int = 0, undone: Int = 0, accepted: Int = 0, overridden: Int = 0) {
        self.applied = applied
        self.undone = undone
        self.accepted = accepted
        self.overridden = overridden
    }

    /// Two undos and a third of its automatic applications or more.
    public var isHeld: Bool { undone >= 2 && undone * 3 >= applied }
    /// Five accepted suggestions and never overruled or undone.
    public var isTrustedAtMedium: Bool { accepted >= 5 && overridden == 0 && undone == 0 }

    public static func trust(_ stats: [String: LabelStat]) -> LabelTrust {
        LabelTrust(
            held: Set(stats.filter { $0.value.isHeld }.keys),
            trustedAtMedium: Set(stats.filter { $0.value.isTrustedAtMedium }.keys))
    }
}

public enum NeighbourQuery {
    static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "your", "you", "are", "was", "how", "what", "why",
        "not", "but", "all", "can", "has", "have", "its", "our", "out", "into", "about", "new", "use", "using",
        "www", "com", "org", "net", "http", "https", "html", "page", "home",
    ]

    /// A Hister query for pages sharing any of the title's key words:
    /// `(word|word|…)` is a union in Hister's syntax (plain words are an intersection). Nil when nothing's left.
    public static func terms(from title: String, limit: Int = 6) -> String? {
        var words: [String] = []
        for raw in title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        where raw.count >= 3 && !stopwords.contains(raw) && !words.contains(raw) && raw.rangeOfCharacter(from: .letters) != nil {
            words.append(raw)
        }
        guard !words.isEmpty else { return nil }
        return "(" + words.prefix(limit).joined(separator: "|") + ")"
    }
}
