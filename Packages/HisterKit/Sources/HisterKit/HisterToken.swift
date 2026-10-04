import Foundation

/// Hister's access token: the owner's one token per user, sent as
/// `X-Access-Token` by every Hister caller that holds one (the apps, the
/// share extension, Safari's extension through the app). Unset, nothing is
/// sent. Never in a URL, never logged. `S.histerToken` / `S.histerHeaders`
/// in search-core.js are the twins, with the same tests.
public enum HisterToken {
    public static let header = "X-Access-Token"

    /// A token as stored: printable ASCII, no spaces, 8 to 512 characters
    /// (Hister's own are 26); nil otherwise.
    public static func clean(_ raw: String?) -> String? {
        let token = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...512).contains(token.utf8.count), token.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            return nil
        }
        return token
    }
}

/// Follows a redirect only on the same scheme, host and port while the
/// request carries the token; anywhere else the token is dropped first.
final class TokenKeepingRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var next = request
        let from = task.originalRequest?.url
        let to = request.url
        if from?.scheme != to?.scheme || from?.host() != to?.host() || from?.port != to?.port {
            next.setValue(nil, forHTTPHeaderField: HisterToken.header)
        }
        completionHandler(next)
    }
}
