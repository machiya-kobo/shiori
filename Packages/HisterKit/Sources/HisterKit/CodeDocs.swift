import Foundation

/// Your repos in Hister (code-import, `metadata.source:code`): repo
/// cards, READMEs and docs, issues, PRs and releases, each at its forge
/// URL. Only the Code pill shows them: every other Hister query leaves them
/// out (`SearchText.forHister`). Metadata values a query matches are single
/// lowercase tokens (Hister can't match "/" in one): `code_repo` is
/// `owner__repo`, `code_private` the STRING "true". search-core.js's
/// `codeQuery` / `codeRepoKey` / `codeInfo` / `codeNotePath` are the twins,
/// with the same tests.
public enum CodeDocs {
    public static let term = "metadata.source:code"
    public static let exclusion = "-metadata.source:code"

    /// The kinds a filter offers; Docs covers READMEs too.
    public enum Kind: String, CaseIterable, Sendable {
        case repo, docs, issue, pr, release
        public var title: String {
            switch self {
            case .repo: "Repos"
            case .docs: "Docs"
            case .issue: "Issues"
            case .pr: "Pull Requests"
            case .release: "Releases"
            }
        }
    }

    public struct Filters: Sendable, Equatable, Hashable {
        public var kind: Kind?
        public var host: String?
        public var open = false
        public var repo: String?
        public var privateOnly = false
        public init(kind: Kind? = nil, host: String? = nil, open: Bool = false, repo: String? = nil, privateOnly: Bool = false) {
            self.kind = kind
            self.host = host
            self.open = open
            self.repo = repo
            self.privateOnly = privateOnly
        }
    }

    /// The forges code-import reads, for the host filter and each row's badge.
    public static let hosts: [(key: String, name: String)] = [("forgejo", "Forgejo"), ("github", "GitHub")]

    /// A host's name for a row ("forgejo" → "Forgejo"); an unknown one as given.
    public static func hostName(_ host: String) -> String {
        hosts.first { $0.key == host }?.name ?? host
    }

    /// A query that asks for code: `metadata.source:code` among its words.
    public static func asked(in text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains { $0 == term }
    }

    /// A repo's key as code-import stores it: owner and repo each lowercase
    /// with every other character "_", joined by "__"; a key already made
    /// stays as it is.
    public static func repoKey(_ name: String) -> String {
        func clean(_ part: Substring) -> String {
            String(part.lowercased().unicodeScalars.map { ("a"..."z").contains($0) || ("0"..."9").contains($0) ? Character($0) : "_" })
        }
        let text = name.trimmingCharacters(in: .whitespaces)
        guard let slash = text.firstIndex(of: "/") else { return clean(text[...]) }
        return clean(text[..<slash]) + "__" + clean(text[text.index(after: slash)...])
    }

    /// The Code pill's query: the term and the filters first, so the last
    /// typed word stays a prefix.
    public static func query(_ typed: String, filters: Filters = Filters()) -> String {
        var terms = [term]
        switch filters.kind {
        case .docs: terms.append("metadata.code_kind:(readme|doc)")
        case .some(let kind): terms.append("metadata.code_kind:\(kind.rawValue)")
        case nil: break
        }
        if let host = filters.host, !host.isEmpty, host.allSatisfy({ ("a"..."z").contains($0) }) {
            terms.append("metadata.code_host:\(host)")
        }
        if filters.open { terms.append("metadata.code_state:open") }
        if let repo = filters.repo, !repo.isEmpty { terms.append("metadata.code_repo:\(repoKey(repo))") }
        if filters.privateOnly { terms.append("metadata.code_private:true") }
        let words = typed.trimmingCharacters(in: .whitespaces)
        return "\(terms.joined(separator: " ")) \(words.isEmpty ? "*" : words)"
    }

    /// The repo's note in the default vault, as Kura's path
    /// (`Repos/<name>.git.md`), or nil.
    public static func notePath(repoName: String) -> String? {
        let name = repoName.split(separator: "/").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
        return "Repos/\(name).git.md"
    }
}

/// What a code row shows, from its metadata.
public struct CodeInfo: Sendable, Equatable, Hashable {
    public var kind: String
    public var host: String
    public var repo: String
    public var repoName: String
    public var state: String
    public var isPrivate: Bool
    public var number: String
    public var tag: String
    public var path: String

    public init(kind: String = "", host: String = "", repo: String = "", repoName: String = "", state: String = "",
                isPrivate: Bool = false, number: String = "", tag: String = "", path: String = "") {
        self.kind = kind
        self.host = host
        self.repo = repo
        self.repoName = repoName
        self.state = state
        self.isPrivate = isPrivate
        self.number = number
        self.tag = tag
        self.path = path
    }
}

/// A document's metadata, leniently: only code's keys, as strings (a number
/// or a boolean read as text); nothing here can fail a search.
struct MetadataWire: Decodable {
    var values: [String: String] = [:]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    static let keys = ["source", "code_kind", "code_host", "code_repo", "code_repo_name", "code_state", "code_private",
                       "code_number", "code_tag", "code_path"]

    init(from decoder: any Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Key.self) else { return }
        for name in Self.keys {
            guard let key = Key(stringValue: name) else { continue }
            if let s = try? c.decode(String.self, forKey: key) { values[name] = s }
            else if let i = try? c.decode(Int.self, forKey: key) { values[name] = String(i) }
            else if let b = try? c.decode(Bool.self, forKey: key) { values[name] = b ? "true" : "false" }
        }
    }

    /// A code document's facts; nil for anything else.
    var code: CodeInfo? {
        guard values["source"] == "code" else { return nil }
        return CodeInfo(
            kind: values["code_kind"] ?? "", host: values["code_host"] ?? "", repo: values["code_repo"] ?? "",
            repoName: values["code_repo_name"] ?? "", state: values["code_state"] ?? "",
            isPrivate: values["code_private"] == "true", number: values["code_number"] ?? "",
            tag: values["code_tag"] ?? "", path: values["code_path"] ?? "")
    }
}
