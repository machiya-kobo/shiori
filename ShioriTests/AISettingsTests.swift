import Foundation
import Testing

/// Settings → AI stays on this device: off until turned on, and never
/// settable by Safari's results page.
struct AISettingsTests {
    let temp = TempDefaults()
    var defaults: UserDefaults { temp.defaults }

    @Test func offByDefaultWithTheChosenModels() {
        let settings = AISettings(from: defaults)
        #expect(!settings.enabled)
        #expect(settings.cloud == .none)
        #expect(!settings.localEnabled)
        #expect(!settings.autoLabel)
        // The build's SHIORI_AI_NEVER_SUGGEST; none here.
        #expect(settings.neverSuggest == AISettings.defaultNeverSuggest)
        #expect(AISettings.defaultNeverSuggest.isEmpty)
        #expect(settings.anthropicModel == "claude-sonnet-5-5")
        #expect(settings.openAIModel == "gpt-6-luna")
    }

    @Test func savedSettingsComeBack() {
        var settings = AISettings()
        settings.enabled = true
        settings.appleIntelligence = false
        settings.cloud = .anthropic
        settings.anthropicModel = "claude-haiku-4-5"
        settings.localEnabled = true
        settings.localURL = "http://server:11434/v1"
        settings.localModel = "qwen3"
        settings.autoLabel = true
        settings.neverSuggest = []
        settings.save(to: defaults)
        #expect(AISettings(from: defaults) == settings)
    }

    @Test func anEmptiedModelIsTheDefaultAgain() {
        defaults.set("  ", forKey: AISettings.Key.openAIModel)
        #expect(AISettings(from: defaults).openAIModel == AISettings.defaultOpenAIModel)
    }

    @Test func noAIKeyIsTakenFromOutside() {
        // Everything a web page could send.
        let wrote = SharedSettings.apply(
            [
                AISettings.Key.enabled: true,
                AISettings.Key.cloud: "anthropic",
                AISettings.Key.anthropicModel: "anything",
                AISettings.Key.localEnabled: true,
                AISettings.Key.localURL: "http://evil.example/v1",
            ],
            to: defaults)
        #expect(!wrote)
        #expect(AISettings(from: defaults) == AISettings())
    }

    @Test func onlyAnHTTPAddressIsALocalServer() {
        var settings = AISettings()
        settings.localURL = "http://server:11434/v1"
        #expect(settings.localBaseURL?.host() == "server")
        settings.localURL = "server:11434"
        #expect(settings.localBaseURL == nil)
        settings.localURL = "file:///etc/passwd"
        #expect(settings.localBaseURL == nil)
    }
}
