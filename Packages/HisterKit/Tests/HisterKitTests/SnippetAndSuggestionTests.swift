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
        // Opened purple, Files green, Code red, Small Web teal. (Raised is for borders, placeholders and a
        // moment's press, never text.)
        let base = palette.tintsOverSurface ? h.surface : h.background
        let tinted = [Palette.Tint.blue, .orange, .purple, .green, .red, .teal].map { mix(h.chips[$0.rawValue], base, palette.tintOpacity) }
        for backdrop in [h.background, h.surface] + tinted {
            for colour in [h.text, h.secondaryText, h.accent, h.danger] + h.chips {
                #expect(ratio(colour, backdrop) >= 4.5, "\(name): \(Palette.css(colour)) on \(Palette.css(backdrop))")
            }
        }
    }

    /// A pill under the pointer lifts onto `raised`, its colour moved to
    /// the shade that reads there (as the web's `--<tint>-raised`).
    @Test(arguments: variants)
    func hoveredPillsReadOnTheRaisedShade(name: String, palette: Palette) {
        for tint in [Palette.Tint.blue, .cyan, .purple, .green, .orange, .red, .yellow, .teal] {
            let ink = palette.tintOnRaisedHex(tint)
            #expect(Palette.contrast(ink, palette.hex.raised) >= 4.5, "\(name) \(tint): \(Palette.css(ink)) on \(Palette.css(palette.hex.raised))")
        }
        // A colour that already reads is left as it is.
        #expect(Palette.readable(0x000000, on: 0xFFFFFF, lighter: false) == 0x000000)
    }

    @Test func aLabelAlwaysGetsTheSameChipColour() {
        #expect(Palette.night.chipColor(for: "books") == Palette.night.chipColor(for: "books"))
    }
}
