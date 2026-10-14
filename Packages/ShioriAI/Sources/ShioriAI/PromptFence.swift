import Foundation

/// Keeps outside text inside its block in a prompt. Shiori's prompts put a
/// page, notes or search results between tags (`<page>…</page>`) and tell
/// the model that what's inside is data; text that wrote those tags itself
/// could close the block early and speak as Shiori. Here the given tags,
/// in any case or spacing, lose their angle brackets (`‹page›`), so only
/// Shiori's own tags delimit the block.
enum PromptFence {
    static func text(_ text: String, tags: [String]) -> String {
        guard !tags.isEmpty, text.contains("<") else { return text }
        let names = Set(tags.map { $0.lowercased() })
        let whole = NSRange(text.startIndex..., in: text)
        var out = text
        // Backwards, so earlier ranges stay put as later ones change.
        for match in tag.matches(in: text, range: whole).reversed() {
            guard let name = Range(match.range(at: 1), in: text), names.contains(text[name].lowercased()),
                  let range = Range(match.range, in: out)
            else { continue }
            out.replaceSubrange(range, with: out[range].replacingOccurrences(of: "<", with: "‹").replacingOccurrences(of: ">", with: "›"))
        }
        return out
    }

    /// Any tag-shaped run, compiled once (three prompts' worth of text per
    /// request went through a fresh regex each time); the name decides.
    private static let tag = try! NSRegularExpression(pattern: #"<\s*/?\s*([A-Za-z][A-Za-z0-9_-]*)\s*>"#)
}
