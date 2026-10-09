import Foundation

/// A page's text for a model: Hister's readable HTML (what the preview
/// shows) as plain text, paragraphs kept, markup and scripts gone.
public enum PageText {
    public static func plain(fromHTML html: String) -> String {
        var text = html
        // Whole elements whose text isn't the page's, across lines too ((?s): "." takes a line break).
        for tag in ["script", "style", "noscript", "svg", "template"] {
            text = text.replacingOccurrences(
                of: "(?s)<\(tag)\\b[^>]*>.*?</\(tag)\\s*>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "(?s)<!--.*?-->", with: " ", options: .regularExpression)
        // Block ends and breaks become line breaks, list items bullets.
        text = text.replacingOccurrences(of: "<li\\b[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(
            of: "<(br|/p|/div|/h[1-6]|/li|/tr|/blockquote|/pre|/section|/article|/header|/footer|hr)\\b[^>]*>",
            with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        // Tidy: runs of spaces to one, three or more line breaks to two.
        text = text.replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        // A list's items one to a line.
        text = text.replacingOccurrences(of: "\\n+• ", with: "\n• ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// At most `limit` characters, cut at a paragraph or sentence or word
    /// end near the limit rather than mid-word. Returns the text and
    /// whether anything was cut.
    public static func prefix(_ text: String, limit: Int) -> (text: String, cut: Bool) {
        guard text.count > limit else { return (text, false) }
        let head = String(text.prefix(limit))
        let floor = head.index(head.startIndex, offsetBy: limit * 3 / 4)
        for separator in ["\n", ". ", " "] {
            if let range = head.range(of: separator, options: .backwards), range.lowerBound >= floor {
                // A sentence keeps its full stop.
                let end = separator == ". " ? head.index(after: range.lowerBound) : range.lowerBound
                return (String(head[..<end]).trimmingCharacters(in: .whitespacesAndNewlines), true)
            }
        }
        return (head, true)
    }

    /// Consecutive parts of at most `size` characters, each ending at a
    /// paragraph, sentence or word where one is near.
    public static func chunks(_ text: String, size: Int) -> [String] {
        var parts: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let (part, cut) = prefix(String(rest), limit: size)
            parts.append(part)
            guard cut else { break }
            rest = rest.dropFirst(part.count).drop { $0.isWhitespace || $0.isNewline }
        }
        return parts.filter { !$0.isEmpty }
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while let amp = text[index...].firstIndex(of: "&") {
            out += text[index..<amp]
            if let semi = text[amp...].prefix(10).firstIndex(of: ";") {
                let name = String(text[text.index(after: amp)..<semi])
                if let value = named[name.lowercased()] {
                    out += value
                    index = text.index(after: semi)
                    continue
                }
                if name.hasPrefix("#") {
                    let digits = name.dropFirst()
                    let scalar = digits.first == "x" || digits.first == "X"
                        ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                    if let scalar, let char = Unicode.Scalar(scalar) {
                        out.unicodeScalars.append(char)
                        index = text.index(after: semi)
                        continue
                    }
                }
            }
            out += "&"
            index = text.index(after: amp)
        }
        return out + text[index...]
    }
}
