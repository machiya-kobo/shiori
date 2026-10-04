import Foundation

/// Settings → AI (docs/ai.md). **Per device**, and not in
/// `SharedSettings.apply`'s whitelist: Safari's results page writes
/// through it, and a page must never be able to turn AI on and send page
/// text to a cloud engine. The API keys are in the Keychain
/// (`AIKeychain`), never here.
nonisolated struct AISettings: Equatable {
    /// The one switch, off until the user turns it on.
    var enabled = false
    /// Apple Intelligence, where the device has it (iOS/macOS 26+).
    var appleIntelligence = true
    /// A model server of the user's own (Ollama, LM Studio): none yet,
    /// so off; the engine is built for when there is one.
    var localEnabled = false
    var localURL = ""
    var localModel = ""
    /// The one cloud engine, tried last.
    var cloud: Cloud = .none
    var anthropicModel = Self.defaultAnthropicModel
    var openAIModel = Self.defaultOpenAIModel
    /// Label New Pages: off until turned on, per device, so it
    /// runs where the user chooses (one device, not every one paying
    /// twice for the same page).
    var autoLabel = false
    /// Apply Apple Intelligence's Labels (the user's choice): its first
    /// choice is applied, not suggested, when the cloud doesn't settle a
    /// page; each can be undone, and a label undone twice is held.
    var applyAppleLabels = false
    /// Labels the AI never uses, applying or suggesting: the user adds
    /// them by hand. Leaving them out of the list also makes the model
    /// choose among the rest. The default is the build's
    /// `SHIORI_AI_NEVER_SUGGEST` (local.yml), if a build sets one, none
    /// in a public build; Settings → AI edits it per device.
    var neverSuggest: [String] = Self.defaultNeverSuggest

    static let defaultNeverSuggest: [String] = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "ShioriDefaultNeverSuggest") as? String ?? ""
        guard !raw.hasPrefix("$(") else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }()
    /// Keep Collections Current: labels in no collection are put
    /// in one (automatically when clear, else asked), and new collections
    /// proposed (always asked). Off until turned on.
    var autoCollections = false

    enum Cloud: String, CaseIterable, Identifiable {
        case none, anthropic, openAI
        var id: Self { self }
        var label: String {
            switch self {
            case .none: "None"
            case .anthropic: "Anthropic"
            case .openAI: "OpenAI"
            }
        }
    }

    /// The default models. Kept in step with ShioriAI's
    /// `AIProvider.defaultModel` (this file compiles into targets that
    /// don't link the package); Test Connection checks them against the
    /// provider's own list.
    static let defaultAnthropicModel = "claude-sonnet-5-5"
    static let defaultOpenAIModel = "gpt-6-luna"

    enum Key {
        static let enabled = "aiEnabled"
        static let appleIntelligence = "aiAppleIntelligence"
        static let localEnabled = "aiLocalEnabled"
        static let localURL = "aiLocalURL"
        static let localModel = "aiLocalModel"
        static let cloud = "aiCloud"
        static let anthropicModel = "aiAnthropicModel"
        static let openAIModel = "aiOpenAIModel"
        static let autoLabel = "aiAutoLabel"
        static let applyAppleLabels = "aiApplyAppleLabels"
        static let neverSuggest = "aiNeverSuggest"
        static let autoCollections = "aiAutoCollections"
        static let all = [
            enabled, appleIntelligence, localEnabled, localURL, localModel, cloud, anthropicModel, openAIModel, autoLabel,
            applyAppleLabels, neverSuggest, autoCollections,
        ]
    }

    init() {}

    init(from defaults: UserDefaults?) {
        guard let defaults else { return }
        func flag(_ key: String, _ value: inout Bool) {
            if defaults.object(forKey: key) != nil { value = defaults.bool(forKey: key) }
        }
        func text(_ key: String, _ value: inout String) {
            if let stored = defaults.string(forKey: key) { value = stored }
        }
        flag(Key.enabled, &enabled)
        flag(Key.appleIntelligence, &appleIntelligence)
        flag(Key.localEnabled, &localEnabled)
        text(Key.localURL, &localURL)
        text(Key.localModel, &localModel)
        if let raw = defaults.string(forKey: Key.cloud), let stored = Cloud(rawValue: raw) { cloud = stored }
        text(Key.anthropicModel, &anthropicModel)
        text(Key.openAIModel, &openAIModel)
        flag(Key.autoLabel, &autoLabel)
        flag(Key.applyAppleLabels, &applyAppleLabels)
        if let stored = defaults.stringArray(forKey: Key.neverSuggest) { neverSuggest = stored }
        flag(Key.autoCollections, &autoCollections)
        // An emptied model field means the default again.
        if anthropicModel.trimmingCharacters(in: .whitespaces).isEmpty { anthropicModel = Self.defaultAnthropicModel }
        if openAIModel.trimmingCharacters(in: .whitespaces).isEmpty { openAIModel = Self.defaultOpenAIModel }
    }

    func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(appleIntelligence, forKey: Key.appleIntelligence)
        defaults.set(localEnabled, forKey: Key.localEnabled)
        defaults.set(localURL, forKey: Key.localURL)
        defaults.set(localModel, forKey: Key.localModel)
        defaults.set(cloud.rawValue, forKey: Key.cloud)
        defaults.set(anthropicModel, forKey: Key.anthropicModel)
        defaults.set(openAIModel, forKey: Key.openAIModel)
        defaults.set(autoLabel, forKey: Key.autoLabel)
        defaults.set(applyAppleLabels, forKey: Key.applyAppleLabels)
        defaults.set(neverSuggest, forKey: Key.neverSuggest)
        defaults.set(autoCollections, forKey: Key.autoCollections)
    }

    /// The local server's address, when it's a usable one.
    var localBaseURL: URL? {
        let trimmed = localURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        return url
    }
}
