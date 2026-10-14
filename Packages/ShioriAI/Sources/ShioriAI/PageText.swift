import Foundation

/// A page's text for a model: Hister's readable HTML (what the preview
/// shows) as plain text, paragraphs kept, markup and scripts gone.
public enum PageText {
    public static func plain(fromHTML html: String) -> String {
        var text = html
        for (pattern, template) in markup { text = pattern.replace(in: text, with: template) }
        text = decodeEntities(text)
        for (pattern, template) in spacing { text = pattern.replace(in: text, with: template) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compiled once: a labelling run converts a page per request, and
    /// `replacingOccurrences(options: .regularExpression)` compiled each of
    /// these on every call.
    private static let markup: [(NSRegularExpression, String)] = {
        // Whole elements whose text isn't the page's, across lines too (dot matches line breaks).
        var rules = ["script", "style", "noscript", "svg", "template"].map {
            (pattern("<\($0)\\b[^>]*>.*?</\($0)\\s*>", [.caseInsensitive, .dotMatchesLineSeparators]), " ")
        }
        rules.append((pattern("<!--.*?-->", [.dotMatchesLineSeparators]), " "))
        // Block ends and breaks become line breaks, list items bullets.
        rules.append((pattern("<li\\b[^>]*>", [.caseInsensitive]), "\n• "))
        rules.append((pattern(
            "<(br|/p|/div|/h[1-6]|/li|/tr|/blockquote|/pre|/section|/article|/header|/footer|hr)\\b[^>]*>",
            [.caseInsensitive]), "\n"))
        rules.append((pattern("<[^>]+>"), ""))
        return rules
    }()

    /// Tidy: runs of spaces to one, three or more line breaks to two, a
    /// list's items one to a line.
    private static let spacing: [(NSRegularExpression, String)] = [
        (pattern("[ \\t\\u00A0]+"), " "),
        (pattern(" *\\n *"), "\n"),
        (pattern("\\n{3,}"), "\n\n"),
        (pattern("\\n+• "), "\n• "),
    ]

    static func pattern(_ text: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: text, options: options)
    }

    /// An engine's budget (characters, at about 2.5 a token) for this text:
    /// smaller for scripts that take a token or so a character (Chinese,
    /// Japanese, Korean, Thai) or about two (Arabic, Hebrew, Devanagari),
    /// which overflowed Apple Intelligence's 4K context at the Latin rate.
    /// Measured on the first few thousand characters.
    public static func budget(_ budget: Int, for text: String) -> Int {
        var weight = 0.0
        var count = 0
        for scalar in text.unicodeScalars.prefix(4_000) where !scalar.properties.isWhitespace {
            count += 1
            switch scalar.value {
            case 0x0E00...0x0EFF, 0x1100...0x11FF, 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x3FFFF:
                weight += 2.5
            case 0x0590...0x08FF, 0x0900...0x0DFF:
                weight += 1.25
            default:
                weight += 1
            }
        }
        guard count > 0 else { return budget }
        return max(1_000, Int(Double(budget) / (weight / Double(count))))
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

extension NSRegularExpression {
    /// Every match replaced with `template` (no `$` references in Shiori's).
    func replace(in text: String, with template: String) -> String {
        stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
