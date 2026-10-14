import Foundation
import Testing

@testable import HisterKit

struct SnippetTests {
    @Test func marksBecomeHighlightedRuns() {
        let snippet = Snippet(html: "… many <mark>concurrency</mark> topics in <mark>Go</mark>.")
        #expect(snippet.runs == [
            .init("… many ", highlighted: false),
            .init("concurrency", highlighted: true),
            .init(" topics in ", highlighted: false),
            .init("Go", highlighted: true),
            .init(".", highlighted: false),
        ])
    }

    @Test func entitiesAreDecodedAndOtherTagsDropped() {
        let snippet = Snippet(html: "<p>A &amp; B &lt;tag&gt; &#8212; &#x2026; <b>bold</b></p>")
        #expect(snippet.plainText == "A & B <tag> — … bold ")
    }

    @Test func whitespaceCollapses() {
        #expect(Snippet(html: "a\n\n   b\tc").plainText == "a b c")
    }

    @Test func anUnclosedTagIsKeptAsText() {
        #expect(Snippet(html: "a < b").plainText == "a < b")
    }

    @Test func unknownEntitiesStay() {
        #expect(Snippet(html: "R&D &bogus; &").plainText == "R&D &bogus; &")
    }
}

struct RulesTests {
    let rules = Rules(aliases: [
        "@gamma": "label:(tomato|banana|cherry)",
        "@beta": "label:cherry",
        "saved": "label:(tomato|banana|cherry|apple|misc)",
        "@alpha": "label:apple",
        "mine": "label:misc",
        "@toot": "metadata.type:toot",
    ])

    @Test func labelsAreEveryLabelTheAliasesName() {
        #expect(rules.labels == ["apple", "banana", "cherry", "misc", "tomato"])
    }

    @Test func collectionsAreAtAliasesThatNameSomeLabels() {
        // Not the plain "saved" or "mine" (the user's own queries), nor
        // "@toot" (no labels).
        #expect(rules.collections.map(\.name) == ["@alpha", "@beta", "@gamma"])
        #expect(rules.collections.last?.labels == ["banana", "cherry", "tomato"])
        #expect(Rules.isCollectionKeyword("@alpha"))
        #expect(!Rules.isCollectionKeyword("saved"))
        #expect(!Rules.isCollectionKeyword("@"))
    }

    @Test func anAtAliasNamingEveryLabelIsNoCollection() {
        let all = Rules(aliases: ["@all": "label:(tomato|apple)", "@gamma": "label:tomato"])
        #expect(all.collections.map(\.name) == ["@gamma"])
    }

    @Test func aLabelKnowsItsCollections() {
        #expect(rules.collections(containing: "cherry") == ["@beta", "@gamma"])
        #expect(rules.collections(containing: "misc").isEmpty)
        #expect(rules.ungroupedLabels == ["misc"])
    }

    @Test func aSingleAliasIsStillACollection() {
        let one = Rules(aliases: ["@gamma": "label:(tomato|banana)"])
        #expect(one.collections.map(\.name) == ["@gamma"])
        #expect(one.ungroupedLabels.isEmpty)
    }
}

struct QuerySuggestionTests {
    let rules = Rules(aliases: [
        "tools": "label:(tools|hardware)",
        "cloud": "label:kubernetes",
    ])

    @Test func aliasesAndOperatorsCompleteTheLastWord() {
        let s = QuerySuggestions.suggest(for: "rust to", rules: rules)
        #expect(s.map(\.completion) == ["rust tools "])
        let ops = QuerySuggestions.suggest(for: "dom", rules: rules)
        #expect(ops.map(\.completion) == ["domain:"])
    }

    @Test func labelValuesCompleteFromTheAliases() {
        let s = QuerySuggestions.suggest(for: "go label:h", rules: rules)
        #expect(s.map(\.completion) == ["go label:hardware "])
    }

    @Test func nothingAfterASpaceOrForACompleteWord() {
        #expect(QuerySuggestions.suggest(for: "tools ", rules: rules).isEmpty)
        #expect(QuerySuggestions.suggest(for: "tools", rules: rules).isEmpty)
        #expect(QuerySuggestions.suggest(for: "", rules: rules).isEmpty)
    }
}

struct ThemeTests {
    @Test func unknownThemeValuesFollowTheSystem() {
        #expect(AppTheme.resolve(nil) == .system)
        #expect(AppTheme.resolve("sepia") == .system)
        #expect(AppTheme.resolve("night") == .night)
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.day.colorScheme == .light)
    }

    @Test func theTenThemesInTheRoomsOrder() {
        #expect(AppPalette.all.map(\.key) == [
            "tokyo-night", "solarized", "nord", "dracula", "catppuccin", "gruvbox", "rose-pine",
            "kanagawa", "everforest", "ayu",
        ])
        #expect(AppPalette.resolve(nil) == .tokyoNight)
        #expect(AppPalette.resolve("purple") == .tokyoNight)
        #expect(AppPalette.resolve("nord").name == "Nord")
        #expect(AppPalette.all.allSatisfy { $0.dark.isDark && !$0.light.isDark })
    }

    /// Every variant of every theme.
    static let variants: [(String, Palette)] = AppPalette.all.flatMap {
        [("\($0.key) dark", $0.dark), ("\($0.key) light", $0.light)]
    }

    @Test(arguments: variants)
    func textColoursMeetWCAGAAOnTheBackgroundAndCards(name: String, palette: Palette) {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { Double((hex >> UInt32($0)) & 0xFF) / 255 }
                .map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        func ratio(_ a: UInt32, _ b: UInt32) -> Double {
            let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
            return (hi + 0.05) / (lo + 0.05)
        }
        /// `tint` laid over `base` at `amount`, as a card's fill.
        func mix(_ tint: UInt32, _ base: UInt32, _ amount: Double) -> UInt32 {
            [16, 8, 0].reduce(UInt32(0)) { out, shift in
                let t = Double((tint >> UInt32(shift)) & 0xFF), b = Double((base >> UInt32(shift)) & 0xFF)
                return out | (UInt32((t * amount + b * (1 - amount)).rounded()) << UInt32(shift))
            }
        }
        let h = palette.hex
        // Lists sit on the background; Settings rows, sheets and cards on
        // the surface; result cards (Result Style → Tint) on the page's or
        // surface's colour tinted in their pill's: Pages blue, Notes orange,
        // Opened slate, Files green, Code red, Small Web teal, Media purple. (Raised is for borders, placeholders and a
        // moment's press, never text.)
        let base = palette.tintsOverSurface ? h.surface : h.background
        let tinted = [Palette.Tint.blue, .orange, .purple, .green, .red, .teal, .slate].map { mix(palette.tintHex($0), base, palette.tintOpacity) }
        for backdrop in [h.background, h.surface] + tinted {
            for colour in [h.text, h.secondaryText, h.accent, h.danger, h.slate] + h.chips {
                #expect(ratio(colour, backdrop) >= 4.5, "\(name): \(Palette.css(colour)) on \(Palette.css(backdrop))")
            }
        }
    }

    /// A pill under the pointer lifts onto its hover fill, its text moved to
    /// the shade that reads there (as the web's `--<pill>-hover`), and the
    /// fill stands apart from the page more than the plain raised shade.
    @Test(arguments: variants)
    func hoveredPillsReadOnTheirHoverFill(name: String, palette: Palette) {
        let h = palette.hex
        for tint in Palette.Tint.allCases {
            let (fill, ink) = palette.pillHoverHex(tint)
            #expect(Palette.contrast(ink, fill) >= 4.5, "\(name) \(tint): \(Palette.css(ink)) on \(Palette.css(fill))")
            #expect(Palette.contrast(fill, h.background) > Palette.contrast(h.raised, h.background), "\(name) \(tint): the fill shows")
        }
        // A colour that already reads is left as it is.
        #expect(Palette.readable(0x000000, on: 0xFFFFFF, lighter: false) == 0x000000)
    }

    @Test func aLabelAlwaysGetsTheSameChipColour() {
        #expect(Palette.night.chipColor(for: "books") == Palette.night.chipColor(for: "books"))
        // Slate (Opened) is no label's: the hash still picks among the eight.
        for (name, palette) in Self.variants {
            #expect(palette.hex.chips.count == 8, "\(name)")
            #expect(!palette.hex.chips.contains(palette.hex.slate), "\(name)")
        }
        #expect(Palette.night.chipHex(for: "books") == Palette.night.hex.chips[Int("books".unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value } % 8)])
    }

    /// The rooms' themes as web/app/palettes.css has them: Opened's slate
    /// and every pill's hover fill and text are the web's (`--opened`,
    /// `--<pill>-hover-bg`, `--<pill>-hover`), twins made by scripts/palettes.mjs.
    /// Tokyo Night's Opened is search.css's, its hover fill and text too in
    /// the dark (whose raised shade the two share).
    @Test func pillColoursAreTheWebsTwins() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var css = try String(contentsOf: root.appendingPathComponent("patches/shiori/search.css"), encoding: .utf8)
        func tokens(_ selector: String) -> [String: UInt32] {
            guard let start = css.range(of: selector + " {"), let end = css.range(of: "}", range: start.upperBound..<css.endIndex) else { return [:] }
            let body = String(css[start.upperBound..<end.lowerBound])
            let pattern = try! NSRegularExpression(pattern: #"--([\w-]+):\s*#([0-9a-fA-F]{6})\b"#)
            var out: [String: UInt32] = [:]
            for m in pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                guard let name = Range(m.range(at: 1), in: body), let value = Range(m.range(at: 2), in: body) else { continue }
                out[String(body[name])] = UInt32(body[value], radix: 16)
            }
            return out
        }
        let night = tokens(":root"), day = tokens(":root[data-theme=\"day\"]")
        #expect(night["opened"] == Palette.night.hex.slate)
        #expect(day["opened"] == Palette.day.hex.slate)
        #expect(night["opened-hover-bg"] == Palette.night.pillHoverHex(.slate).fill)
        #expect(night["opened-hover"] == Palette.night.pillHoverHex(.slate).ink)

        css = try String(contentsOf: root.appendingPathComponent("web/app/palettes.css"), encoding: .utf8)
        let pills: [(String, Palette.Tint)] = [("tab-general", .cyan), ("accent", .blue), ("notes", .orange), ("web", .yellow),
            ("tab-images", .green), ("tab-videos", .red), ("tab-news", .purple), ("smallweb", .teal), ("kept", .green), ("opened", .slate)]
        for theme in AppPalette.generated {
            for (selector, palette) in [(":root[data-palette=\"\(theme.key)\"]", theme.dark), (":root[data-palette=\"\(theme.key)\"][data-theme=\"day\"]", theme.light)] {
                let web = tokens(selector)
                #expect(web["opened"] == palette.hex.slate, "\(selector) --opened")
                for (pill, tint) in pills {
                    let (fill, ink) = palette.pillHoverHex(tint)
                    #expect(web["\(pill)-hover-bg"] == fill, "\(selector) --\(pill)-hover-bg")
                    #expect(web["\(pill)-hover"] == ink, "\(selector) --\(pill)-hover")
                }
            }
        }
    }
}
