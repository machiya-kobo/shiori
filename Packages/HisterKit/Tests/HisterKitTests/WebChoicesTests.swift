import Foundation
import Testing

@testable import HisterKit

/// Images, Videos and News choices, on scripts/web-choices-cases.json: the
/// cases search-core's `S.webChoiceRow` and friends are tested against too.
struct WebChoicesTests {
    static func data() throws -> [String: Any] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/web-choices-cases.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    /// A result as the cases write it (SearXNG's own fields).
    static func item(_ raw: Any) -> WebChoices.Item {
        let r = raw as? [String: Any] ?? [:]
        let length: String? = switch r["length"] {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
        return WebChoices.Item(
            url: r["url"] as? String ?? "",
            resolution: r["resolution"] as? String ?? "",
            imgFormat: r["img_format"] as? String ?? "",
            imgSrc: r["img_src"] as? String ?? "",
            length: length,
            published: (r["publishedDate"] as? String).flatMap(SearxClient.date))
    }

    static func params(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(string: "?" + text)?.queryItems ?? [] { out[item.name] = item.value ?? "" }
        return out
    }

    @Test func lengthsSizesValuesAndKeys() throws {
        let data = try Self.data()
        for pair in try #require(data["lengths"] as? [[Any]]) {
            let input: String? = switch pair[0] {
            case let text as String: text
            case let number as NSNumber: number.stringValue
            default: nil
            }
            #expect(WebChoices.lengthSeconds(input) == (pair[1] as? Int), "\(pair)")
        }
        for triple in try #require(data["sizes"] as? [[Any]]) {
            let size = WebChoices.imageSize(resolution: triple[0] as? String ?? "", imgFormat: triple[1] as? String ?? "")
            let want = triple[2] as? [String: Int]
            #expect(size?.w == want?["w"] && size?.h == want?["h"], "\(triple)")
        }
        for triple in try #require(data["values"] as? [[Any]]) {
            let key = try #require(triple[1] as? String)
            #expect(WebChoices.value(key, Self.item(triple[0])) == triple[2] as? String, "\(key) of \(triple[0])")
        }
        for pair in try #require(data["keys"] as? [[String]]) {
            #expect(WebChoices.choiceKey(pair[0]) == pair[1])
        }
    }

    @Test func choicesNarrowAndTheRow() throws {
        let cases = try #require(try Self.data()["cases"] as? [[String: Any]])
        #expect(cases.count > 10)
        for c in cases {
            let category = try #require(c["cat"] as? String)
            let label = "\(category) \(c["params"] ?? "")"
            let items = (c["results"] as? [Any] ?? []).map(Self.item)
            let choices = WebChoices.choices(category, params: Self.params(c["params"] as? String ?? ""))
            let want = c["choices"] as? [String: String] ?? [:]
            #expect(choices.order == want["order"] ?? "", "\(label) order")
            for (key, value) in want where key != "order" { #expect(choices[key] == value, "\(label) \(key)") }
            #expect(WebChoices.narrow(category, items, choices, item: { $0 }).map(\.url) == c["narrow"] as? [String], "\(label) narrow")
            let row = WebChoices.row(category, items, choices)
            let wantRow = c["row"] as? [[String: Any]] ?? []
            #expect(row.map(\.key) == wantRow.map { $0["key"] as? String ?? "" }, "\(label) row keys")
            for (menu, w) in zip(row, wantRow) {
                #expect(menu.name == w["name"] as? String, "\(label) \(menu.key) name")
                let options = (w["choices"] as? [[String]] ?? []).map { WebChoices.Menu.Option(value: $0[0], label: $0[1]) }
                #expect(menu.options == options, "\(label) \(menu.key) options")
            }
        }
    }

    @Test func quotedPhrasesFirst() throws {
        let phrases = try #require(try Self.data()["phrases"] as? [String: Any])
        for pair in try #require(phrases["quoted"] as? [[Any]]) {
            let query = try #require(pair[0] as? String)
            #expect(WebChoices.quotedPhrases(query) == pair[1] as? [String], "\(query)")
        }
        let cases = try #require(phrases["first"] as? [[String: Any]])
        #expect(cases.count >= 3)
        for c in cases {
            let query = try #require(c["q"] as? String)
            let results = try #require(c["results"] as? [[String: String]])
            let order = WebChoices.phrasesFirst(query, results) { r in
                (r["title"] ?? "", r["content"] ?? "", r["url"] ?? "", r["img_src"] ?? "")
            }
            #expect(order.map { $0["url"] ?? "" } == c["order"] as? [String], "\(query)")
        }
    }
}
