import Foundation
import ShioriAI

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence as an engine: the one place Shiori imports
/// FoundationModels (the ShioriAI target never does). iOS/macOS 26 and
/// later on an eligible device with Apple Intelligence on; anywhere else
/// it says why and the next engine answers. A target of its own so the
/// app and the accuracy test (`shiori-ai-eval`) run the same code.
public struct AppleIntelligenceEngine: AIEngine {
    public var provider: AIProvider { .appleIntelligence }

    public init() {}

    /// Page text per request, from the model's own context (4K tokens here
    /// even on 27, for instructions, page and answer together): about
    /// 1,000 tokens kept for the instructions and the answer, and 2.5
    /// characters a token, which leaves room for languages that use more.
    public var inputBudget: Int {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            return max(2_000, (SystemLanguageModel.default.contextSize - 1_000) * 5 / 2)
        }
        #endif
        return 6_000
    }

    public enum Status: Equatable, Sendable {
        case available
        case needsNewerSystem
        case notEligible
        case turnedOff
        case notReady

        public var label: String {
            switch self {
            case .available: "Ready"
            case .needsNewerSystem: "Needs iOS 26 or macOS 26"
            case .notEligible: "Not available on this device"
            case .turnedOff: "Off in Settings"
            case .notReady: "Getting ready (downloading)"
            }
        }

        public var detail: String? {
            switch self {
            case .turnedOff: "Turn on Apple Intelligence in the system's Settings to use it here."
            case .notReady: "The model is still downloading; try again later."
            default: nil
            }
        }
    }

    /// Checked before every request: the user can switch Apple
    /// Intelligence off at any time.
    public static var status: Status {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, *) else { return .needsNewerSystem }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .notEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .turnedOff
        case .unavailable(.modelNotReady):
            return .notReady
        case .unavailable:
            return .notEligible
        }
        #else
        return .needsNewerSystem
        #endif
    }

    public func respond(to request: AIRequest) async throws -> String {
        let status = Self.status
        guard status == .available else { throw AIError.unavailable("Apple Intelligence: \(status.label).") }
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, *) else { throw AIError.unavailable("Apple Intelligence needs iOS 26 or macOS 26.") }
        // A fresh session per request: nothing of one page carries into
        // the next. The page text is the prompt; the instructions are
        // Shiori's own (framing it as data), never the page's.
        let session = LanguageModelSession(instructions: request.system)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: request.maxTokens)
        do {
            if let schema = request.schema {
                // Guided generation: the answer can only take the schema's
                // shape (a label from the list), then read as JSON like
                // any engine's.
                guard #available(iOS 26.4, macOS 26.4, *) else {
                    throw AIError.unavailable("Apple Intelligence: structured answers need iOS 26.4 or macOS 26.4.")
                }
                let generationSchema = try GenerationSchema(root: try Self.dynamicSchema(schema, name: "Answer"), dependencies: [])
                let response = try await session.respond(to: request.user, schema: generationSchema, options: options)
                return response.content.jsonString
            }
            let response = try await session.respond(to: request.user, options: options)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIError.emptyContent }
            return text
        } catch let error as AIError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
        #else
        throw AIError.unavailable("Apple Intelligence needs iOS 26 or macOS 26.")
        #endif
    }

    #if canImport(FoundationModels)
    /// The JSON-schema subset Shiori's requests use, as a dynamic schema:
    /// objects of named properties, strings (a choice when there's an
    /// `enum`), and arrays of those.
    @available(iOS 26.4, macOS 26.4, *)
    static func dynamicSchema(_ schema: JSONValue, name: String) throws -> DynamicGenerationSchema {
        guard case .object(let fields) = schema, case .string(let type)? = fields["type"] else {
            throw AIError.unavailable("Apple Intelligence: an unsupported answer shape.")
        }
        let description: String? = if case .string(let text)? = fields["description"] { text } else { nil }
        switch type {
        case "object":
            guard case .object(let properties)? = fields["properties"] else {
                throw AIError.unavailable("Apple Intelligence: an object with no properties.")
            }
            let required: Set<String> =
                if case .array(let names)? = fields["required"] {
                    Set(names.compactMap { if case .string(let n) = $0 { n } else { nil } })
                } else { [] }
            return DynamicGenerationSchema(
                name: name, description: description,
                properties: try properties.keys.sorted().map { key in
                    DynamicGenerationSchema.Property(
                        name: key, description: nil, schema: try dynamicSchema(properties[key]!, name: key),
                        isOptional: !required.contains(key))
                })
        case "string":
            if case .array(let choices)? = fields["enum"] {
                return DynamicGenerationSchema(
                    name: name, description: description,
                    anyOf: choices.compactMap { if case .string(let c) = $0 { c } else { nil } })
            }
            return DynamicGenerationSchema(type: String.self)
        case "array":
            guard let items = fields["items"] else { throw AIError.unavailable("Apple Intelligence: an array with no items.") }
            let maximum: Int? = if case .number(let n)? = fields["maxItems"] { Int(n) } else { nil }
            return DynamicGenerationSchema(arrayOf: try dynamicSchema(items, name: name + "Item"), maximumElements: maximum)
        default:
            throw AIError.unavailable("Apple Intelligence: an unsupported answer type (\(type)).")
        }
    }

    /// The framework's errors as the engine chain reads them: a refusal or
    /// guardrail is "declined", a limit or a missing asset "unavailable";
    /// both let the next engine try. iOS/macOS 27 throw
    /// `LanguageModelError`, 26 threw `GenerationError`: both are read.
    @available(iOS 26, macOS 26, *)
    static func mapped(_ error: Error) -> Error {
        if #available(iOS 27, macOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal:
                return AIError.declined(nil)
            case .contextSizeExceeded:
                return AIError.tooLong
            default:
                return AIError.unavailable("Apple Intelligence: \(error.localizedDescription)")
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                return AIError.declined(nil)
            case .exceededContextWindowSize:
                return AIError.tooLong
            default:
                return AIError.unavailable("Apple Intelligence: \(error.localizedDescription)")
            }
        }
        return AIError.unavailable("Apple Intelligence: \(error.localizedDescription)")
    }
    #endif
}
