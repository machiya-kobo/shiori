import Testing

@testable import ShioriAI

@Suite struct LabelPolicyTests {
    func answer(_ labels: [String], new: String? = nil, _ confidence: LabelSuggestion.Confidence, _ provider: AIProvider) -> LabelSuggestion {
        LabelSuggestion(labels: labels, newLabel: new, confidence: confidence, provider: provider)
    }

    @Test func anthropicsHighAnswerIsApplied() {
        let decision = LabelPolicy.decide(cloud: answer(["alpha", "systems"], .high, .anthropic), onDevice: answer(["systems"], .high, .appleIntelligence))
        #expect(decision == .apply(label: "alpha", by: .anthropic, agreed: false))
    }

    @Test func appleIsNeverAppliedAlone() {
        #expect(LabelPolicy.decide(cloud: nil, onDevice: answer(["alpha"], .high, .appleIntelligence)) == .suggest(labels: ["alpha"], newLabel: nil))
    }

    @Test func anUnmeasuredCloudEngineOnlySuggests() {
        let decision = LabelPolicy.decide(cloud: answer(["gamma"], .high, .openAI), onDevice: nil)
        #expect(decision == .suggest(labels: ["gamma"], newLabel: nil))
    }

    @Test func whenBothPickTheSameLabelItIsAppliedWhateverTheConfidence() {
        let decision = LabelPolicy.decide(cloud: answer(["tech", "work"], .low, .anthropic), onDevice: answer(["tech"], .high, .appleIntelligence))
        #expect(decision == .apply(label: "tech", by: .anthropic, agreed: true))
    }

    @Test func belowHighAppleLeadsAndTheCloudsGuessFollows() {
        let decision = LabelPolicy.decide(
            cloud: answer(["vintage-tech", "gamma"], .medium, .anthropic), onDevice: answer(["gamma", "hardware"], .high, .appleIntelligence))
        #expect(decision == .suggest(labels: ["gamma", "vintage-tech"], newLabel: nil))
    }

    @Test func agreementWithAnUnmeasuredEngineOnlySuggests() {
        let decision = LabelPolicy.decide(cloud: answer(["gamma"], .medium, .openAI), onDevice: answer(["gamma"], .low, .appleIntelligence))
        #expect(decision == .suggest(labels: ["gamma"], newLabel: nil))
    }

    @Test func aNewLabelOnlyWhenNothingExistingFits() {
        #expect(
            LabelPolicy.decide(cloud: answer([], new: "home-automation", .medium, .anthropic), onDevice: answer([], .low, .appleIntelligence))
                == .suggest(labels: [], newLabel: "home-automation"))
        #expect(LabelPolicy.decide(cloud: nil, onDevice: answer([], .low, .appleIntelligence)) == .nothing)
        #expect(LabelPolicy.decide(cloud: nil, onDevice: nil) == .nothing)
    }
}

@Suite struct LabelLearningTests {
    func answer(_ labels: [String], _ confidence: LabelSuggestion.Confidence, _ provider: AIProvider) -> LabelSuggestion {
        LabelSuggestion(labels: labels, newLabel: nil, confidence: confidence, provider: provider)
    }

    @Test func aLabelTheUserKeepsUndoingIsOnlySuggested() {
        let trust = LabelStat.trust(["tech": LabelStat(applied: 5, undone: 2)])
        #expect(trust.held == ["tech"])
        let decision = LabelPolicy.decide(cloud: answer(["tech"], .high, .anthropic), onDevice: answer(["tech"], .high, .appleIntelligence), trust: trust)
        #expect(decision == .suggest(labels: ["tech"], newLabel: nil))
    }

    @Test func oneUndoOrARareOneDoesNotHoldALabel() {
        #expect(!LabelStat(applied: 3, undone: 1).isHeld)
        #expect(!LabelStat(applied: 20, undone: 2).isHeld)
    }

    @Test func aLabelAlwaysAcceptedIsAppliedOnMedium() {
        let trust = LabelStat.trust(["alpha": LabelStat(accepted: 5), "gamma": LabelStat(accepted: 9, overridden: 1)])
        #expect(trust.trustedAtMedium == ["alpha"])
        #expect(LabelPolicy.decide(cloud: answer(["alpha"], .medium, .anthropic), onDevice: nil, trust: trust)
            == .apply(label: "alpha", by: .anthropic, agreed: false))
        #expect(LabelPolicy.decide(cloud: answer(["gamma"], .medium, .anthropic), onDevice: nil, trust: trust)
            == .suggest(labels: ["gamma"], newLabel: nil))
        #expect(LabelPolicy.decide(cloud: answer(["alpha"], .low, .anthropic), onDevice: nil, trust: trust)
            == .suggest(labels: ["alpha"], newLabel: nil))
    }

    @Test func aSureAnswerSaysWhetherAppleAgreed() {
        #expect(LabelPolicy.decide(cloud: answer(["alpha"], .high, .anthropic), onDevice: answer(["systems"], .high, .appleIntelligence))
            == .apply(label: "alpha", by: .anthropic, agreed: false))
        #expect(LabelPolicy.decide(cloud: answer(["alpha"], .high, .anthropic), onDevice: answer(["alpha"], .low, .appleIntelligence))
            == .apply(label: "alpha", by: .anthropic, agreed: true))
    }

    @Test func theNeighbourQueryIsAUnionOfTheTitlesKeyWords() {
        #expect(NeighbourQuery.terms(from: "The Sample Project: How to use Containers") == "(sample|project|containers)")
        #expect(NeighbourQuery.terms(from: "the and a") == nil)
        #expect(NeighbourQuery.terms(from: "404 2021") == nil)
    }

    @Test func neighboursAndCorrectionsGoAfterThePage() async throws {
        let engine = JSONEngine(answer: #"{"label":"alpha","second":"none","new_label":"","confidence":"high"}"#)
        _ = try await LabelClassifier(chain: EngineChain([engine])).suggest(
            title: "Jails", url: "https://x.example/", text: "text", choices: [LabelChoice(name: "alpha"), LabelChoice(name: "tech")],
            neighbours: [LabelNeighbour(title: "Sample OS Containers", host: "docs.os.example", label: "alpha"),
                         LabelNeighbour(title: "Not a choice", host: "a.example", label: "work")],
            corrections: [LabelCorrection(title: "Discord", host: "discord.com", suggested: "tech", chosen: "")],
            content: .page)
        let user = try #require(engine.last).user
        #expect(user.contains("</page>\nYour labelled pages most like this one:\n- “Sample OS Containers” (docs.os.example): alpha"))
        #expect(!user.contains("Not a choice"))
        #expect(user.contains("- “Discord” (discord.com): not tech"))
    }
}
