import Foundation

/// Serves canned replies and records requests, per host (a copy of
/// HisterKit's; the two test bundles don't share code). `nonisolated`:
/// URLSession calls it off the main thread, and the project's default
/// isolation is MainActor.
nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]

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
        }
    }

    /// A session that only reaches these stubs.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
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
        let handler = Self.lock.withLock { () -> Handler? in
            Self.recorded[host, default: []].append(request)
            return Self.handlers[host]
        }
        do {
            guard let handler else { throw URLError(.cannotFindHost) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
