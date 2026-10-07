import Foundation

/// Keeps outside text inside its block in a prompt. Shiori's prompts put a
/// page, notes or search results between tags (`<page>…</page>`) and tell
/// the model that what's inside is data; text that wrote those tags itself
/// could close the block early and speak as Shiori. Here the given tags,
/// in any case or spacing, lose their angle brackets (`‹page›`), so only
/// Shiori's own tags delimit the block.
enum PromptFence {
    static func text(_ text: String, tags: [String]) -> String {
        guard !tags.isEmpty else { return text }
        let names = tags.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let pattern = try? Regex("(?i)<\\s*/?\\s*(?:\(names))\\s*>") else { return text }
        return text.replacing(pattern) { match in
            String(text[match.range]).replacingOccurrences(of: "<", with: "‹").replacingOccurrences(of: ">", with: "›")
        }
    }
}
