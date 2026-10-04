import Foundation
import Testing

@testable import HisterKit

/// Serves canned replies and records requests, per host, so suites that
/// run in parallel (each with its own host) never see each other's.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]
    nonisolated(unsafe) private static var replyHeaders: [String: [String: String]] = [:]

    /// Headers every reply from `host` carries (Set-Cookie, say).
    static func headers(_ host: String, _ fields: [String: String]) {
        lock.withLock { replyHeaders[host] = fields }
    }

    static func handle(_ host: String, _ handler: @escaping Handler) {
        lock.withLock { handlers[host] = handler }
    }

    static func requests(_ host: String) -> [URLRequest] {
        lock.withLock { recorded[host] ?? [] }
    }

    static func reset(_ host: String) {
        lock.withLock {
            recorded[host] = []
            handlers[host] = nil
            replyHeaders[host] = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            request.httpBody = data
        }
        let host = request.url?.host() ?? ""
        let (handler, fields) = Self.lock.withLock { () -> (Handler?, [String: String]?) in
            Self.recorded[host, default: []].append(request)
            return (Self.handlers[host], Self.replyHeaders[host])
        }
        do {
            guard let handler else { throw URLError(.cannotFindHost) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: fields)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct HisterClientTests {
    static let host = "client.example"
    let client: HisterClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = HisterClient(serverURL: "https://\(Self.host)", session: URLSession(configuration: config))!
        StubProtocol.reset(Self.host)
    }

    func stub(_ json: String, status: Int = 200) {
        StubProtocol.handle(Self.host) { _ in (status, Data(json.utf8)) }
    }

    var requests: [URLRequest] { StubProtocol.requests(Self.host) }

    @Test func serverURLGetsATrailingSlashAndMustBeHTTP() {
        #expect(HisterClient(serverURL: "https://h.example")?.baseURL.absoluteString == "https://h.example/")
        #expect(HisterClient(serverURL: " https://h.example/x/ ")?.baseURL.absoluteString == "https://h.example/x/")
        #expect(HisterClient(serverURL: "ftp://h.example") == nil)
        #expect(HisterClient(serverURL: "h.example") == nil)
        #expect(HisterClient(serverURL: "") == nil)
    }

    @Test func searchSendsOriginAndAJSONQuery() async throws {
        stub(#"{"total":1,"documents":[{"url":"https://a.example/","title":"A","domain":"a.example","label":"books","added":100,"updated":200,"favicon_key":"k","text":"x <mark>y</mark>"}],"page_key":"next"}"#)
        let page = try await client.search("y", sort: .newest, pageKey: "p1", limit: 1)
        let request = try #require(requests.first)
        #expect(request.value(forHTTPHeaderField: "Origin") == "hister://")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let query = try JSONSerialization.jsonObject(with: Data(items.first { $0.name == "query" }!.value!.utf8)) as! [String: Any]
        // Notes come from Kura: every Hister query leaves them out.
        #expect(query["text"] as? String == "y -label:vault -metadata.source:vault -type:local")  // one letter: no prefix
        #expect(query["sort"] as? String == "date")
        #expect(query["page_key"] as? String == "p1")
        #expect(query["highlight"] as? String == "HTML")
        #expect(query["limit"] as? Int == 1)
        #expect(page.documents.first?.label == "books")
        #expect(page.documents.first?.updated == Date(timeIntervalSince1970: 200))
        #expect(page.nextPageKey == "next")
    }

    /// A "+" must reach the server as "+", not a space: Hister's page keys
    /// hold them ("Am+MO~"), and so do searches like "c++".
    @Test func plusSignsSurviveTheQueryString() async throws {
        stub(#"{"total":0,"documents":[]}"#)
        _ = try await client.search("c++", pageKey: "[\" Am+MO~\"]")
        let request = try #require(requests.first)
        let raw = try #require(request.url?.absoluteString)
        #expect(!raw.contains("+"))
        #expect(raw.contains("%2B"))
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let query = try JSONSerialization.jsonObject(with: Data(items.first { $0.name == "query" }!.value!.utf8)) as! [String: Any]
        #expect(query["text"] as? String == "c++ -label:vault -metadata.source:vault -type:local")
        #expect(query["page_key"] as? String == "[\" Am+MO~\"]")
    }

    /// A bad certificate is its own error; a name that won't resolve (Tailscale
    /// off) stays unreachable, which the outbox keeps pages for.
    @Test func transportFailuresMapToWhatTheUserCanDo() {
        #expect(HisterError(transport: URLError(.serverCertificateUntrusted)) == .untrusted)
        #expect(HisterError(transport: URLError(.secureConnectionFailed)) == .untrusted)
        #expect(HisterError(transport: URLError(.cannotFindHost)) == .unreachable)
        #expect(HisterError(transport: URLError(.timedOut)) == .unreachable)
    }

    @Test func aShortPageHasNoNextKey() async throws {
        stub(#"{"total":1,"documents":[{"url":"https://a.example/"}],"page_key":"stale"}"#)
        let page = try await client.search("a", limit: 30)
        #expect(page.nextPageKey == nil)
        #expect(page.documents.first?.domain == "a.example")
    }

    @Test func rawControlCharactersInARepliesAreTolerated() async throws {
        stub("{\"total\":1,\"documents\":[{\"url\":\"https://a.example/\",\"text\":\"line\u{01}one\"}]}")
        let page = try await client.search("a")
        #expect(page.documents.count == 1)
    }

    @Test func failuresMapToWhatTheUIShows() async {
        StubProtocol.handle(Self.host) { _ in throw URLError(.cannotFindHost) }
        await #expect(throws: HisterError.unreachable) { try await client.search("a") }
        stub(#"{"error":"invalid regexp"}"#, status: 400)
        await #expect(throws: HisterError.invalidQuery("invalid regexp")) { try await client.search("a") }
        stub("", status: 404)
        await #expect(throws: HisterError.notFound) { try await client.preview(of: "https://a.example/") }
        stub("boom", status: 500)
        await #expect(throws: HisterError.server(status: 500, message: "boom")) { try await client.search("a") }
    }

    @Test func previewReadsDetails() async throws {
        stub(#"{"title":"T","content":"<p>hi</p>","added":1,"updated":2,"details":{"label":"tech","visits":3},"meta":{"author":"","description":"D"}}"#)
        let preview = try await client.preview(of: "https://a.example/")
        #expect(preview.label == "tech")
        #expect(preview.visits == 3)
        #expect(preview.author == nil)
        #expect(preview.summary == "D")
    }

    @Test func setLabelPostsJSON() async throws {
        stub("{}")
        try await client.setLabel("books", for: "https://a.example/")
        let request = try #require(requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/label")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
        #expect(body == ["url": "https://a.example/", "label": "books"])
    }

    @Test func setAliasPostsAForm() async throws {
        stub("")
        try await client.setAlias("@alpha", value: "label:(alpha-one|alpha-two|c+d)")
        let request = try #require(requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/add_alias")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "Origin") == "hister://")
        var form = URLComponents()
        form.percentEncodedQuery = String(decoding: request.httpBody!, as: UTF8.self)
        let fields = Dictionary(uniqueKeysWithValues: (form.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(fields == ["alias-keyword": "@alpha", "alias-value": "label:(alpha-one|alpha-two|c+d)"])
    }

    @Test func deleteAliasPostsItsKeyword() async throws {
        stub("")
        try await client.deleteAlias("@beta")
        let request = try #require(requests.first)
        #expect(request.url?.path() == "/api/delete_alias")
        #expect(String(decoding: request.httpBody!, as: UTF8.self) == "alias=@beta")
    }

    @Test func deleteRunsADryRunAndDeletesOnlyOneMatch() async throws {
        StubProtocol.handle(Self.host) { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            return (200, Data(((body["dry_run"] as? Bool) == true ? #"{"matched":1}"# : #"{"deleted":1}"#).utf8))
        }
        try await client.delete(url: #"https://a.example/"q""#)
        #expect(requests.count == 2)
        let first = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: Any]
        #expect(first["query"] as? String == #"url:"https://a.example/\"q\"""#)
        #expect(first["dry_run"] as? Bool == true)
    }

    @Test func deleteRefusesWhenTheQueryMatchesMoreThanOnePage() async {
        stub(#"{"matched":3}"#)
        await #expect(throws: HisterError.unexpectedMatchCount(3)) { try await client.delete(url: "https://a.example/") }
        #expect(requests.count == 1)
    }

    @Test func rulesExposeAliasesAndTheirLabels() async throws {
        stub(#"{"skip":["x"],"aliases":{"one":"label:birds","two":"label:(cats|dogs)"}}"#)
        let rules = try await client.rules()
        #expect(rules.aliases["one"] == "label:birds")
        #expect(rules.labels == ["birds", "cats", "dogs"])
    }
}
