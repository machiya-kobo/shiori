import Testing

@testable import HisterKit

/// "wiki" in a search: the twin of search-core.test.mjs's cases.
struct WikipediaTests {
    func r(_ url: String) -> WebResult {
        WebResult(url: url, title: "", content: "", engines: [], thumbnail: nil, published: nil)
    }

    @Test func wikiAsksForWikipedia() {
        #expect(WikipediaFirst.query("wiki moon phases") == "moon phases")
        #expect(WikipediaFirst.query("moon phases Wikipedia") == "moon phases")
        #expect(WikipediaFirst.query("WIKI  tokyo") == "tokyo")
        #expect(WikipediaFirst.query("wikis tokyo") == nil)
        #expect(WikipediaFirst.query("mediawiki setup") == nil)
        #expect(WikipediaFirst.query("wiki") == nil)
        #expect(WikipediaFirst.query("") == nil)
    }

    @Test func theFirstArticle() {
        let list = [
            r("http://www.stars.example/moon.htm"),
            r("https://www.wikipedia.org/"),
            r("https://en.wikipedia.org/wiki/Main_Page"),
            r("https://en.wikipedia.org/wiki/Special:Search?search=x"),
            r("https://en.wikipedia.org/wiki/Category:Moon"),
            r("https://en.m.wikipedia.org/wiki/Moon"),
            r("https://en.wikipedia.org/wiki/Sun"),
        ]
        #expect(WikipediaFirst.article(in: list) == .init(
            url: "https://en.wikipedia.org/wiki/Moon", title: "Moon", lang: "en", index: 5))
        #expect(WikipediaFirst.article(in: [r("https://en.wikipedia.org/wiki/Special_relativity")])?.title == "Special relativity")
        #expect(WikipediaFirst.article(in: [r("https://en.wikipedia.org/wiki/User_interface")])?.title == "User interface")
        #expect(WikipediaFirst.article(in: [r("https://de.wikipedia.org/wiki/Z%C3%BCrich")])?.title == "Zürich")
        #expect(WikipediaFirst.article(in: [r("https://cards.wiki.example/wiki/Moon")]) == nil)
        #expect(WikipediaFirst.article(in: [r("https://en.wikipedia.org/wiki/Talk:Moon")]) == nil)
        #expect(WikipediaFirst.article(in: [r("https://sw.wikipedia.org/wiki/Faili:Moon.jpg")]) == nil)
        #expect(WikipediaFirst.article(in: [r("https://en.wikipedia.org/wiki/Example:_Subtitle")])?.title == "Example: Subtitle")
        let mixed = [r("https://sw.wikipedia.org/wiki/Paris"), r("https://en.wikipedia.org/wiki/Moon")]
        #expect(WikipediaFirst.article(in: mixed, languages: ["en-US"])?.lang == "en")
        #expect(WikipediaFirst.article(in: mixed, languages: ["fr"])?.lang == "sw")
        #expect(WikipediaFirst.article(in: mixed)?.lang == "sw")
        #expect(WikipediaFirst.article(in: []) == nil)
    }

    @Test func wikipediaFirst() {
        let list = [r("https://a.example/"), r("https://en.wikipedia.org/wiki/Moon"), r("https://b.example/")]
        let article = WikipediaFirst.article(in: list)
        #expect(WikipediaFirst.ordered(list, article: article).map(\.url) == [
            "https://en.wikipedia.org/wiki/Moon", "https://a.example/", "https://b.example/",
        ])
        let found = WebResult(url: "https://en.wikipedia.org/wiki/Tokyo", title: "Tokyo - Wikipedia",
                              content: "Capital of Japan", engines: [], thumbnail: nil, published: nil)
        let other = WikipediaFirst.article(in: [found])
        let out = WikipediaFirst.ordered([r("https://a.example/")], article: other, found: found)
        #expect(out.first == found)
        #expect(out.count == 2)
        #expect(WikipediaFirst.ordered(list, article: nil).count == 3)
    }
}
