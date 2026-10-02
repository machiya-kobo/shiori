import Foundation
import ShioriAI
import ShioriAIOnDevice

// The label classifier measured against the user's own labelled pages
// (docs/ai.md): automatic labelling is switched on only
// once this clears the bar. Read-only against Hister: it reads rules,
// pages and previews, and never writes a label. Prints counts, rates and
// the misses' titles; page text stays in memory.
//
//   swift run shiori-ai-eval --server https://hister.example/ [--per-label 3]
//       [--engine apple|anthropic|openai] [--model ID]
//
// The cloud engines take their key from ANTHROPIC_API_KEY or OPENAI_API_KEY,
// else from the login keychain: a key of its own for this Mac, stored with
//   security add-generic-password -U -s shiori-ai-eval -a anthropic -w
// (-a openai for OpenAI). Read through `security`, so a rebuilt tool
// doesn't prompt; any process of the user's can read it the same way,
// which is why it's a separate, spend-capped key, not the main one.

/// The key for a provider: the environment's, else this Mac's keychain item.
func apiKey(_ variable: String, account: String) -> String {
    if let key = ProcessInfo.processInfo.environment[variable], !key.isEmpty { return key }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", "shiori-ai-eval", "-a", account, "-w"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return "" }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Options {
    var server = ""
    var perLabel = 3
    var engine = "apple"
    var model: String?
    /// Examples per label and the site's labels (`--no-hints` for the
    /// label names alone, to compare).
    var hints = true
    /// The user's labelled pages most like each one, from a Hister search
    /// (`--no-neighbours` to compare).
    var neighbours = true
    /// Also measure checks that could let answers be applied unattended:
    /// a second run with the labels in reverse order (agreement), and
    /// agreement with the site's most common label.
    var gates = false
    /// Dry run of Label New Pages on pages with no label: what would be
    /// applied and what suggested (Anthropic, then Apple Intelligence).
    /// Writes nothing.
    var unlabelled = 0
    /// Anthropic and Apple Intelligence on the labelled sample: how often
    /// each way of combining them is right.
    var agreement = false
    /// One page, Apple Intelligence (and Anthropic with a key), with each
    /// engine's answer or error in full.
    var url: String?
    /// Dry run of Keep Collections Current: nothing is written.
    var collections = false
    /// AI Answer for these searches (the app's `SearchAnswerer`), from the
    /// web results SearXNG (`--searx`) gives; nothing to do with Hister.
    var answers: [String] = []
    var searx = ""

    init(_ arguments: [String]) {
        var index = 0
        func next() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--server": server = next() ?? ""
            case "--per-label": perLabel = Int(next() ?? "") ?? perLabel
            case "--engine": engine = next() ?? engine
            case "--model": model = next()
            case "--no-hints": hints = false
            case "--no-neighbours": neighbours = false
            case "--gates": gates = true
            case "--unlabelled": unlabelled = Int(next() ?? "") ?? 25
            case "--agreement": agreement = true
            case "--url": url = next()
            case "--collections": collections = true
            case "--answer": if let q = next() { answers.append(q) }
            case "--searx": searx = next() ?? ""
            case "--help", "-h":
                print("swift run shiori-ai-eval --server URL [--per-label 3] [--engine apple|anthropic|openai] [--model ID]")
                exit(0)
            default: break
            }
            index += 1
        }
        if !server.hasSuffix("/") { server += "/" }
    }
}

struct Page {
    let url: String
    let title: String
    let label: String
}

enum Hister {
    static func get(_ server: String, _ path: String, _ query: [URLQueryItem]) async throws -> Any {
        var components = URLComponents(string: server + path)!
        components.queryItems = query
        // `queryItems` leaves a bare "+", which servers read as a space,
        // and Hister's page keys hold "+" (a list stopped after one page
        // until they were escaped).
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.setValue("hister://", forHTTPHeaderField: "Origin")
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// Collections → their labels, from the aliases' `label:(a|b)` values.
    static func collections(_ server: String) async throws -> [String: [String]] {
        let rules = try await get(server, "api/rules", []) as? [String: Any]
        let aliases = rules?["aliases"] as? [String: String] ?? [:]
        var out: [String: [String]] = [:]
        let pattern = try NSRegularExpression(pattern: #"label:\(?([A-Za-z0-9_|.-]+)\)?"#)
        for (name, value) in aliases {
            let range = NSRange(value.startIndex..., in: value)
            let labels = pattern.matches(in: value, range: range).flatMap { match in
                String(value[Range(match.range(at: 1), in: value)!]).split(separator: "|").map(String.init)
            }
            if !labels.isEmpty { out[name] = labels }
        }
        return out
    }

    /// Every page, newest first, with its label.
    static func pages(_ server: String) async throws -> [Page] {
        var pages: [Page] = []
        var key: String?
        for _ in 0..<60 {
            var query: [String: Any] = ["text": "*", "sort": "date", "limit": 100]
            if let key { query["page_key"] = key }
            let json = String(data: try JSONSerialization.data(withJSONObject: query), encoding: .utf8)!
            let reply = try await get(server, "search", [URLQueryItem(name: "query", value: json)]) as? [String: Any]
            for doc in reply?["documents"] as? [[String: Any]] ?? [] {
                pages.append(Page(url: doc["url"] as? String ?? "", title: doc["title"] as? String ?? "", label: doc["label"] as? String ?? ""))
            }
            guard let next = reply?["page_key"] as? String, !next.isEmpty else { break }
            key = next
        }
        return pages
    }

    static func previewText(_ server: String, _ url: String) async throws -> String {
        let reply = try await get(server, "api/preview", [URLQueryItem(name: "url", value: url)]) as? [String: Any]
        return PageText.plain(fromHTML: reply?["content"] as? String ?? "")
    }
}

func engine(_ options: Options) -> any AIEngine {
    switch options.engine {
    case "anthropic":
        return AnthropicClient(apiKey: apiKey("ANTHROPIC_API_KEY", account: "anthropic"), model: options.model ?? AIProvider.anthropic.defaultModel)
    case "openai":
        return OpenAICompatibleClient(apiKey: apiKey("OPENAI_API_KEY", account: "openai"), model: options.model ?? AIProvider.openAI.defaultModel)
    default:
        return AppleIntelligenceEngine()
    }
}

let options = Options(CommandLine.arguments)

// --answer: the AI Answer for a search, as the app makes it, on the chosen
// engine (Apple Intelligence unless --engine says otherwise).
if !options.answers.isEmpty {
    guard options.searx.hasPrefix("http") else {
        print("Give SearXNG for --answer: --searx https://searxng.example/")
        exit(2)
    }
    let base = options.searx.hasSuffix("/") ? options.searx : options.searx + "/"
    let answerer = SearchAnswerer(chain: EngineChain([engine(options)]))
    for query in options.answers {
        var components = URLComponents(string: base + "search")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "format", value: "json")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = (reply?["results"] as? [[String: Any]] ?? []).map {
            (title: $0["title"] as? String ?? "", url: $0["url"] as? String ?? "", snippet: $0["content"] as? String ?? "")
        }
        let started = Date()
        print("== \(query)")
        do {
            let answer = try await answerer.answer(query: query, results: results)
            print(answer.text)
            print("   cites \(answer.cited.map(\.n)) of \(answer.sources.count) · \(answer.provider.displayName) · \(String(format: "%.1f", Date().timeIntervalSince(started))) s\n")
        } catch {
            print("   failed: \(error.localizedDescription)\n")
        }
    }
    exit(0)
}

guard options.server.hasPrefix("http") else {
    print("Give the Hister server: --server https://hister.example/")
    exit(2)
}

let collections = try await Hister.collections(options.server)
let everyLabel = Set(collections.values.flatMap { $0 })
let candidates = everyLabel.subtracting(LabelClassifier.notTopics).sorted()
// A collection that names every label (such as an `everything` alias) says nothing.
let meaningful = collections.filter { Set($0.value) != everyLabel }
let all = try await Hister.pages(options.server)
var perLabel: [String: Int] = [:]
let sample = all.filter { page in
    guard candidates.contains(page.label), !page.url.isEmpty, perLabel[page.label, default: 0] < options.perLabel else { return false }
    perLabel[page.label, default: 0] += 1
    return true
}
// The hints come from pages outside the sample, so no page is shown its
// own label: examples are the newest other titles under each label, and
// a page's site labels leave the page itself out.
let sampled = Set(sample.map(\.url))
func host(_ url: String) -> String { URL(string: url)?.host() ?? "" }
let choices = candidates.map { label in
    LabelChoice(
        name: label, collections: meaningful.filter { $0.value.contains(label) }.keys.sorted(),
        examples: options.hints
            ? Array(all.filter { $0.label == label && !sampled.contains($0.url) && !$0.title.isEmpty }.prefix(2).map(\.title)) : [])
}
/// The labelled pages most like this one, by a union of its title's key
/// words, never the page itself.
func neighbours(for page: Page) async -> [LabelNeighbour] {
    guard options.neighbours, let terms = NeighbourQuery.terms(from: page.title) else { return [] }
    let query = String(data: try! JSONSerialization.data(withJSONObject: ["text": terms, "limit": 30]), encoding: .utf8)!
    guard let reply = try? await Hister.get(options.server, "search", [URLQueryItem(name: "query", value: query)]) as? [String: Any]
    else { return [] }
    return (reply["documents"] as? [[String: Any]] ?? []).compactMap { doc in
        guard let url = doc["url"] as? String, url != page.url, let label = doc["label"] as? String, candidates.contains(label),
              let title = doc["title"] as? String, !title.isEmpty
        else { return nil }
        return LabelNeighbour(title: title, host: host(url), label: label)
    }.prefix(8).map { $0 }
}

func siteLabels(for page: Page) -> [String: Int] {
    guard options.hints else { return [:] }
    var counts: [String: Int] = [:]
    for other in all where other.url != page.url && host(other.url) == host(page.url) && candidates.contains(other.label) {
        counts[other.label, default: 0] += 1
    }
    return counts
}
if options.unlabelled > 0 {
    let noteHosts = ["kura.", "konbini.", "niwa."]
    let pending = all.filter { page in
        page.label.isEmpty && !page.url.isEmpty && !noteHosts.contains { host(page.url).hasPrefix($0) }
    }.prefix(options.unlabelled)
    let cloudEngine = AnthropicClient(
        apiKey: apiKey("ANTHROPIC_API_KEY", account: "anthropic"), model: options.model ?? AIProvider.anthropic.defaultModel)
    print("Dry run of Label New Pages on the newest \(pending.count) unlabelled pages (nothing is written):\n")
    var applied = 0
    var suggested = 0
    for page in pending {
        let text = (try? await Hister.previewText(options.server, page.url)) ?? ""
        var cloud: LabelSuggestion?
        do {
            cloud = try await LabelClassifier(chain: EngineChain([cloudEngine])).suggest(
                title: page.title, url: page.url, text: text, choices: choices, siteLabels: siteLabels(for: page), content: .page)
        } catch {
            print("  (Anthropic: \(error.localizedDescription))")
        }
        var onDevice: LabelSuggestion?
        if case .apply = LabelPolicy.decide(cloud: cloud, onDevice: nil) {} else {
            onDevice = try? await LabelClassifier(chain: EngineChain([AppleIntelligenceEngine()])).suggest(
                title: page.title, url: page.url, text: text, choices: choices, siteLabels: siteLabels(for: page), content: .page)
        }
        let title = String((page.title.isEmpty ? page.url : page.title).prefix(60))
        switch LabelPolicy.decide(cloud: cloud, onDevice: onDevice) {
        case .apply(let label, _, let agreed):
            applied += 1
            print("  APPLY\(agreed ? "+" : " ")   \(label.padding(toLength: 14, withPad: " ", startingAt: 0)) \(title)")
        case .suggest(let labels, let newLabel):
            suggested += 1
            let offer = (labels + (newLabel.map { ["+\($0)"] } ?? [])).joined(separator: " / ")
            print("  suggest  \(offer.padding(toLength: 14, withPad: " ", startingAt: 0)) \(title)")
        case .nothing:
            print("  nothing  \("".padding(toLength: 14, withPad: " ", startingAt: 0)) \(title)")
        }
    }
    print("\n\(applied) would be applied, \(suggested) suggested.")
    exit(0)
}

if options.collections {
    let rules = try await Hister.get(options.server, "api/rules", []) as? [String: Any]
    let aliases = rules?["aliases"] as? [String: String] ?? [:]
    let editable = aliases.compactMap { keyword, value -> CollectionInfo? in
        guard keyword.hasPrefix("@"), let labels = AliasValue.labels(in: value) else { return nil }
        return CollectionInfo(keyword: keyword, labels: labels)
    }.sorted { $0.keyword < $1.keyword }
    let grouped = Set(editable.flatMap(\.labels))
    var inUse: [String: Int] = [:]
    for page in all where !page.label.isEmpty { inUse[page.label, default: 0] += 1 }
    // SHIORI_AI_NEVER_SUGGEST: as the app's Never Suggested.
    let neverSuggest = Set(BuildDefaults.list(plistKey: "", environment: "SHIORI_AI_NEVER_SUGGEST"))
    let loose = inUse.keys.filter { !grouped.contains($0) && !LabelClassifier.notTopics.contains($0) && !neverSuggest.contains($0) }.sorted()
    print("Collections Shiori may edit: \(editable.map(\.keyword).joined(separator: ", "))")
    print("Not editable (kept, or not a plain label list): \(aliases.keys.filter { key in !editable.contains { $0.keyword == key } }.sorted().joined(separator: ", "))")
    print("Labels in no collection: \(loose.map { "\($0) (\(inUse[$0]!))" }.joined(separator: ", "))\n")
    let anthropic = AnthropicClient(apiKey: apiKey("ANTHROPIC_API_KEY", account: "anthropic"), model: options.model ?? AIProvider.anthropic.defaultModel)
    var unplaced: [LooseLabel] = []
    for name in loose {
        let label = LooseLabel(name: name, examples: Array(all.filter { $0.label == name && !$0.title.isEmpty }.prefix(3).map(\.title)))
        let apple = try? await CollectionPlanner(chain: EngineChain([AppleIntelligenceEngine()])).place(label, among: editable)
        let cloud = try? await CollectionPlanner(chain: EngineChain([anthropic])).place(label, among: editable)
        let applePick = apple?.keyword ?? "-"
        let cloudPick = cloud.map { "\($0.keyword ?? "none") (\($0.confidence.rawValue))" } ?? "-"
        if let keyword = CollectionPolicy.autoPlace(cloud: cloud, onDevice: apple) {
            print("  ADD      \(name) → \(keyword)   [Apple \(applePick); Anthropic \(cloudPick)]")
        } else if let keyword = CollectionPolicy.ask(cloud: cloud, onDevice: apple) {
            print("  ask      \(name) → \(keyword)?  [Apple \(applePick); Anthropic \(cloudPick)]")
        } else {
            print("  none fits \(name)")
            unplaced.append(label)
        }
    }
    if unplaced.count >= 2 {
        let proposals = (try? await CollectionPlanner(chain: EngineChain([AppleIntelligenceEngine(), anthropic])).propose(
            for: unplaced, existing: aliases.keys.sorted())) ?? []
        for proposal in proposals { print("  propose  \(proposal.keyword): \(proposal.labels.joined(separator: ", "))") }
    }
    exit(0)
}

if let url = options.url {
    let page = all.first { $0.url == url } ?? Page(url: url, title: "", label: "")
    let text = try await Hister.previewText(options.server, url)
    let site = siteLabels(for: page)
    print("Page: \(page.title) (\(text.count) characters of text; site labels: \(site))")
    print("Excerpt limit \(LabelClassifier.excerptLimit)\n")
    var engines: [any AIEngine] = [AppleIntelligenceEngine()]
    let key = apiKey("ANTHROPIC_API_KEY", account: "anthropic")
    if !key.isEmpty {
        engines.append(AnthropicClient(apiKey: key, model: options.model ?? AIProvider.anthropic.defaultModel))
    }
    for engine in engines {
        do {
            let answer = try await LabelClassifier(chain: EngineChain([engine])).suggest(
                title: page.title, url: url, text: text, choices: choices, siteLabels: site, content: .page)
            print("\(engine.provider.displayName): \(answer.labels) new: \(answer.newLabel ?? "-") confidence: \(answer.confidence.rawValue)")
        } catch {
            print("\(engine.provider.displayName) failed: \(error) — \(error.localizedDescription)")
        }
    }
    exit(0)
}

if options.agreement {
    let anthropic = AnthropicClient(
        apiKey: apiKey("ANTHROPIC_API_KEY", account: "anthropic"), model: options.model ?? AIProvider.anthropic.defaultModel)
    print("Agreement: Anthropic and Apple Intelligence on \(sample.count) labelled pages\n")
    // (Anthropic's confidence, Anthropic right, Apple agrees with it)
    var rows: [(confidence: LabelSuggestion.Confidence, right: Bool, agree: Bool)] = []
    for (index, page) in sample.enumerated() {
        let text = (try? await Hister.previewText(options.server, page.url)) ?? ""
        let site = siteLabels(for: page)
        let similar = await neighbours(for: page)
        guard let cloud = try? await LabelClassifier(chain: EngineChain([anthropic])).suggest(
            title: page.title, url: page.url, text: text, choices: choices, siteLabels: site, neighbours: similar, content: .page),
            let first = cloud.labels.first
        else { continue }
        let apple = try? await LabelClassifier(chain: EngineChain([AppleIntelligenceEngine()])).suggest(
            title: page.title, url: page.url, text: text, choices: choices, siteLabels: site, neighbours: similar, content: .page)
        rows.append((cloud.confidence, first == page.label, apple?.labels.first == first))
        if (index + 1) % 10 == 0 { print("  \(index + 1)/\(sample.count)…") }
    }
    func line(_ name: String, _ picked: [(confidence: LabelSuggestion.Confidence, right: Bool, agree: Bool)]) {
        let right = picked.filter(\.right).count
        print("  \(name): \(percent(right, picked.count)) right, on \(picked.count) pages (\(percent(picked.count, rows.count)) of \(rows.count))")
    }
    print("")
    line("Anthropic high", rows.filter { $0.confidence == .high })
    line("Anthropic medium or low, Apple agrees", rows.filter { $0.confidence != .high && $0.agree })
    line("Anthropic medium or low, Apple differs", rows.filter { $0.confidence != .high && !$0.agree })
    line("Applied if high or both agree", rows.filter { $0.confidence == .high || $0.agree })
    line("Any, both agree", rows.filter(\.agree))
    exit(0)
}

let chosen = engine(options)
print("Engine: \(chosen.provider.displayName)\(options.model.map { " (\($0))" } ?? "")\(options.hints ? ", with examples and site labels" : ", label names only")\(options.neighbours ? " and similar pages" : "")")
print("Labels: \(candidates.count); pages: \(all.count); sample: \(sample.count) (up to \(options.perLabel) per label, newest first)\n")

let classifier = LabelClassifier(chain: EngineChain([chosen]))
var exact = 0
var top2 = 0
var failed = 0
var byConfidence: [LabelSuggestion.Confidence: (count: Int, right: Int)] = [:]
var misses: [(String, String, String)] = []
var newLabels: [String] = []
// For --gates: (right, passed the check) per check.
var selfAgree: [(right: Bool, passed: Bool)] = []
var siteAgree: [(right: Bool, passed: Bool)] = []
var either: [(right: Bool, passed: Bool)] = []
let start = Date()
for (index, page) in sample.enumerated() {
    do {
        let text = try await Hister.previewText(options.server, page.url)
        let suggestion = try await classifier.suggest(
            title: page.title, url: page.url, text: text, choices: choices, siteLabels: siteLabels(for: page),
            neighbours: await neighbours(for: page), content: .page)
        let right = suggestion.labels.first == page.label
        if right { exact += 1 }
        if suggestion.labels.contains(page.label) { top2 += 1 }
        byConfidence[suggestion.confidence, default: (0, 0)].count += 1
        if right { byConfidence[suggestion.confidence, default: (0, 0)].right += 1 }
        if !right {
            misses.append((String(page.title.prefix(60)), page.label, suggestion.labels.first ?? "new: \(suggestion.newLabel ?? "-")"))
        }
        if let newLabel = suggestion.newLabel { newLabels.append(newLabel) }
        if options.gates, let first = suggestion.labels.first {
            let again = try? await classifier.suggest(
                title: page.title, url: page.url, text: text, choices: Array(choices.reversed()),
                siteLabels: siteLabels(for: page), content: .page)
            let agrees = again?.labels.first == first
            let majority = siteLabels(for: page).max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
            let siteSays = majority == first
            selfAgree.append((right, agrees))
            siteAgree.append((right, siteSays))
            either.append((right, agrees || siteSays))
        }
    } catch {
        failed += 1
        print("  ! \(page.title.prefix(50)): \(error.localizedDescription)")
    }
    if (index + 1) % 10 == 0 { print("  \(index + 1)/\(sample.count)…") }
}

func percent(_ n: Int, _ of: Int) -> String {
    of == 0 ? "-" : "\(Int((Double(n) / Double(of) * 100).rounded()))%"
}
let answered = sample.count - failed
print("\nAnswered \(answered) of \(sample.count) in \(Int(Date().timeIntervalSince(start))) s")
print("Exact: \(exact)/\(answered) (\(percent(exact, answered)));  in the top two: \(top2)/\(answered) (\(percent(top2, answered)))")
for confidence in [LabelSuggestion.Confidence.high, .medium, .low] {
    let bucket = byConfidence[confidence] ?? (0, 0)
    print("  \(confidence.rawValue): \(bucket.count) answers, \(percent(bucket.right, bucket.count)) right")
}
if !newLabels.isEmpty { print("New labels proposed: \(Set(newLabels).sorted().joined(separator: ", "))") }
if options.gates {
    print("\nChecks for unattended labelling (precision when the check passes; coverage of answered pages):")
    for (name, rows) in [("Two runs agree", selfAgree), ("Matches the site's label", siteAgree), ("Either", either)] {
        let passed = rows.filter(\.passed)
        print("  \(name): \(percent(passed.filter(\.right).count, passed.count)) right, on \(passed.count) pages (\(percent(passed.count, rows.count)))")
    }
}
print("\nMisses (title · expected → got):")
for miss in misses.prefix(40) { print("  \(miss.0) · \(miss.1) → \(miss.2)") }
