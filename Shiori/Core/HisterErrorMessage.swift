import HisterKit

extension HisterError {
    /// A sentence for alerts and empty states.
    var userMessage: String {
        switch self {
        case .unreachable:
            "The server didn't answer. Check your network or VPN and the server address in Settings, then try again."
        case .untrusted:
            "The server's certificate isn't trusted, so Shiori didn't send anything. Check the server's HTTPS setup."
        case .plainHTTP:
            "This address uses http://, and Shiori needs https://."
        case .previewUnavailable:
            "This page's preview couldn't be shown."
        case .invalidQuery(let message):
            message.isEmpty ? "Hister couldn't read that query." : message
        case .notFound:
            "Hister no longer has this page."
        case .unexpectedMatchCount(let n):
            "That would have deleted \(n) pages, so nothing was deleted."
        case .server(let status, let message):
            message.isEmpty ? "The server answered \(status)." : "The server answered \(status): \(message)"
        case .badResponse:
            "The server's reply didn't make sense."
        case .cancelled:
            "Cancelled."
        case .rejected(let rejection):
            rejection.reason
        case .signedOut:
            "Hister wants you to sign in: sign in again in Settings → Account (or check the access token there)."
        }
    }
}
