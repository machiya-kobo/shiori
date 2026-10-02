import Foundation
import Testing

@testable import HisterKit

/// The same cases as search-core.test.mjs's suggestion tests.
struct TitleSuggestionsTests {
    @Test func theLastWordAsATitlePrefixThenThePlainWords() {
        #expect(TitleSuggestions.queries(for: "raspberry ze") == ["raspberry title:ze*", "raspberry ze"])
        #expect(TitleSuggestions.queries(for: " Pytho ") == ["title:pytho*", "pytho"])
        #expect(TitleSuggestions.queries(for: "j") == [])
        #expect(TitleSuggestions.queries(for: "label:books") == [])
        #expect(TitleSuggestions.queries(for: "rust -crate") == [])
        #expect(TitleSuggestions.queries(for: "\"exact") == [])
    }

    @Test func aTitleMatchesWhenItHoldsEveryWordIgnoringSpaces() {
        #expect(TitleSuggestions.matches(title: "Raspberry Pi", text: "raspberrypi"))
        #expect(TitleSuggestions.matches(title: "Raspberry Pi Zero V1.3", text: "raspberry ze"))
        #expect(TitleSuggestions.matches(title: "Learn Python 3.12", text: "Pytho"))
        #expect(!TitleSuggestions.matches(title: "Surfing Example Network", text: "raspberrypi"))
        #expect(!TitleSuggestions.matches(title: "Anything", text: "  "))
    }

    @Test func searxAutocompleteDropsTheTypedTextAndKeepsFive() {
        let data = Data(#"["raspberrypi", ["raspberrypi", "raspberry pi", "raspberry pi 5", "a", "b", "c", "d"], [], []]"#.utf8)
        #expect(SearxClient.parseAutocomplete(data, typed: "RaspberryPi ") == ["raspberry pi", "raspberry pi 5", "a", "b", "c"])
        #expect(SearxClient.parseAutocomplete(Data("{}".utf8), typed: "x") == [])
        #expect(SearxClient.parseAutocomplete(Data("not json".utf8), typed: "x") == [])
    }
}

struct LabelSuggestionsTests {
    let rules = Rules(aliases: [
        "@alpha": "label:(alpha-two|alpha-one|mac)",
        "@tools": "label:(hammer|wrench|cli)",
        "saved": "label:(alpha-two|alpha-one|mac|hammer|wrench|cli|books)",
        "@reading": "label:books",
    ])

    @Test func collectionsFirstThenLabelsStartingWithTheWordFirst() {
        let items = LabelSuggestions.items(for: "alpha", rules: rules)
        #expect(items.map(\.query) == ["@alpha", "label:alpha-one", "label:alpha-two"])
        #expect(items.first?.name == "alpha")
        #expect(LabelSuggestions.items(for: "some wr", rules: rules).map(\.query) == ["label:wrench"])
    }

    @Test func nothingForOneLetterOrQuerySyntax() {
        #expect(LabelSuggestions.items(for: "b", rules: rules).isEmpty)
        #expect(LabelSuggestions.items(for: "label:wr", rules: rules).isEmpty)
    }
}
