import Foundation
import os

/// A reply that didn't decode, logged by where and why: the coding path
/// (field names) and the kind of failure, never a value, which may be a
/// page's text, a note's title or a token. ShioriAI keeps a copy.
enum DecodeLog {
    /// The reply decoded, or nil with the failure logged as `what`.
    static func decode<T: Decodable>(
        _ type: T.Type, from data: Data, what: String, log: Logger = HisterClient.log
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

/// An array read element by element: one that doesn't decode is logged
/// (by `DecodeLog`, as `what`) and skipped, and the rest are kept. One bad
/// note shouldn't empty a page of them.
struct Lenient<Element: Decodable>: Decodable {
    var elements: [Element] = []
    /// Every element in the reply, read or skipped (what paging counts).
    var count = 0

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            count += 1
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                HisterClient.log.error("\(String(describing: Element.self), privacy: .public) skipped: \(DecodeLog.describe(error), privacy: .public)")
                // Past it: a failed decode doesn't move the container on.
                _ = try? container.decode(Skipped.self)
            }
        }
    }

    /// Any value at all, read and dropped.
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
