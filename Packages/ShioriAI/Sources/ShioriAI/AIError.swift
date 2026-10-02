import Foundation

/// What went wrong with an engine. Settings' Test Connection shows these;
/// the features log them and move on.
public enum AIError: Error, Equatable, LocalizedError {
    case badURL
    /// The status and the provider's own message, when there was one (a
    /// bare "status 400" hides what the body says is wrong).
    case badStatus(Int, String?)
    case badResponse
    case emptyContent
    /// The engine can't run here now (Apple Intelligence off, the device
    /// not eligible, the model still downloading, no key).
    case unavailable(String)
    /// The model or its safety layer declined to answer.
    case declined(String?)
    /// The request didn't fit the model's context (Apple Intelligence's is
    /// 4K tokens): a shorter one may.
    case tooLong
    /// No engine is switched on for this content.
    case noEngine

    public var errorDescription: String? {
        switch self {
        case .badURL:
            "The address isn't a valid URL."
        case .badStatus(let code, let message):
            if let message, !message.isEmpty {
                "Status \(code): \(message)"
            } else if code == 401 || code == 403 {
                "The API key was refused (\(code))."
            } else {
                "The server answered with status \(code)."
            }
        case .badResponse:
            "The reply wasn't in the expected format."
        case .emptyContent:
            "The model returned nothing."
        case .unavailable(let reason):
            reason
        case .declined(let reason):
            reason.map { "The model declined: \($0)" } ?? "The model declined to answer."
        case .tooLong:
            "The page was too long for the model."
        case .noEngine:
            "No AI engine is switched on for this."
        }
    }
}

/// Whether another engine may try after an error: the ONLY place the
/// lists live. "Couldn't answer" is kept apart from "answered with a
/// problem", so a working on-device model never sits idle behind an
/// unreachable cloud one.
public enum AIReachability {
    public static func mayFallThrough(_ error: Error) -> Bool {
        isTransient(error) || isRejectedCredential(error) || isUnavailableOrDeclined(error)
    }

    /// Couldn't get an answer now: no network, busy, a server fault.
    public static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError { return transientURLCodes.contains(urlError.code) }
        if case AIError.badStatus(let code, _) = error { return code == 408 || code == 429 || (500...599).contains(code) }
        return false
    }

    /// The key was refused: nothing was asked of a model, so another
    /// engine may answer instead (and Settings says the key is wrong).
    public static func isRejectedCredential(_ error: Error) -> Bool {
        if case AIError.badStatus(let code, _) = error { return code == 401 || code == 403 }
        return false
    }

    static func isUnavailableOrDeclined(_ error: Error) -> Bool {
        switch error as? AIError {
        case .unavailable, .declined, .tooLong: true
        default: false
        }
    }

    /// Captive portals fail with `.secureConnectionFailed`, so it's here;
    /// certificate-trust failures aren't (a misconfigured server of the
    /// user's own should be seen, not routed around).
    static let transientURLCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        .secureConnectionFailed,
    ]
}
