import Foundation
import os

/// A reply that didn't decode, logged by where and why: the coding path
/// (field names) and the kind of failure, never a value, which may be a
/// page's text, a note's title or a token. HisterKit keeps a copy.
enum DecodeLog {
    static let log = Logger(subsystem: logSubsystem, category: "ai")

    /// The reply decoded, or nil with the failure logged as `what`.
    static func decode<T: Decodable>(
        _ type: T.Type, from data: Data, what: String, log: Logger = DecodeLog.log
    ) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log.error("\(what, privacy: .public) didn't decode: \(describe(error), privacy: .public)")
            return nil
        }
    }

    /// "missing key results at (top level)", "type mismatch (String) at
    /// vaults[0].name": no value, no underlying message.
    static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return "not decodable" }
        switch error {
        case .typeMismatch(let type, let context): return "type mismatch (\(type)) at \(path(context))"
        case .valueNotFound(let type, let context): return "no value (\(type)) at \(path(context))"
        case .keyNotFound(let key, let context): return "missing key \(key.stringValue) at \(path(context))"
        case .dataCorrupted(let context): return "unreadable at \(path(context))"
        @unknown default: return "not decodable"
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        guard !context.codingPath.isEmpty else { return "(top level)" }
        return context.codingPath.map { key in key.intValue.map { "[\($0)]" } ?? "." + key.stringValue }
            .joined().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
