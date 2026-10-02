import Foundation

/// A search snippet as runs of plain text, some of them highlighted.
///
/// Hister returns matching text as HTML with `<mark>` around each hit and
/// entities escaped. Parsing it here keeps HTML out of the result list.
public struct Snippet: Sendable, Hashable {
    public struct Run: Sendable, Hashable {
        public var text: String
        public var highlighted: Bool

        public init(_ text: String, highlighted: Bool) {
            self.text = text
            self.highlighted = highlighted
        }
    }

    public var runs: [Run]

    public var plainText: String { runs.map(\.text).joined() }
    public var isEmpty: Bool { runs.allSatisfy { $0.text.isEmpty } }

    public init(html: String) {
        var runs: [Run] = []
        var highlighted = false
        var buffer = ""
        var rest = Substring(html)

        func flush() {
            let text = Self.collapsingWhitespace(Self.decodingEntities(buffer))
            if !text.isEmpty {
                if let last = runs.last, last.highlighted == highlighted {
                    runs[runs.count - 1].text += text
                } else {
                    runs.append(Run(text, highlighted: highlighted))
                }
            }
            buffer = ""
        }

        while let open = rest.firstIndex(of: "<") {
            buffer += rest[..<open]
            guard let close = rest[open...].firstIndex(of: ">") else {
                buffer += rest[open...]
                rest = ""
                break
            }
            let tag = rest[rest.index(after: open)..<close].lowercased()
            if tag == "mark" || tag.hasPrefix("mark ") {
                flush()
                highlighted = true
            } else if tag == "/mark" {
                flush()
                highlighted = false
            } else if tag.hasPrefix("br") || tag.hasPrefix("/p") || tag.hasPrefix("/div") {
                buffer += " "
            }
            // Any other tag is dropped; its text stays.
            rest = rest[rest.index(after: close)...]
        }
        buffer += rest
        flush()
        self.runs = runs
    }

    static func collapsingWhitespace(_ s: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in s {
            if ch.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Built once, not on every call.
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "hellip": "…", "mdash": "—", "ndash": "–", "rsquo": "’", "lsquo": "‘",
        "rdquo": "”", "ldquo": "“",
    ]

    static func decodingEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = after[..<semi]
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
                } else if name.hasPrefix("#") {
                    replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
                } else {
                    replacement = named[String(name)]
                }
                if let replacement {
                    out += replacement
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        out += rest
        return out
    }
}
