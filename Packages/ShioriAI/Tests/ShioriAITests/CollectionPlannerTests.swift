import Foundation
import Testing

@testable import ShioriAI

@Suite struct CollectionPlannerTests {
    @Test func onlyAPureLabelListIsEdited() {
        #expect(AliasValue.labels(in: "label:(alpha-one|alpha-two)") == ["alpha-one", "alpha-two"])
        #expect(AliasValue.labels(in: "label:one") == ["one"])
        #expect(AliasValue.labels(in: "label:(a|b) domain:x.example") == nil)
        #expect(AliasValue.labels(in: "foo OR label:(a|b)") == nil)
        #expect(AliasValue.labels(in: "label:(a||b)") == nil)
    }

    @Test func addingALabelKeepsTheRestInOrder() {
        #expect(AliasValue.adding("budgeting", to: "label:(home|family)") == "label:(home|family|budgeting)")
        #expect(AliasValue.adding("two", to: "label:one") == "label:(one|two)")
        #expect(AliasValue.adding("home", to: "label:(home|family)") == nil)
        #expect(AliasValue.adding("x", to: "label:(a|b) domain:c") == nil)
    }

    @Test func aPlacementIsOnlyEverAnExistingCollection() async throws {
        let engine = JSONEngine(.anthropic, answer: #"{"collection":"@nowhere","confidence":"high"}"#)
        let placement = try await CollectionPlanner(chain: EngineChain([engine])).place(
            LooseLabel(name: "budgeting", examples: ["Savings account basics"]),
            among: [CollectionInfo(keyword: "@household", labels: ["home", "family"])])
        #expect(placement.keyword == nil)
        #expect(try #require(engine.last).system.contains("- @household: home, family"))
    }

    @Test func autoPlacementNeedsTheCloudSureOrBothAgreeing() {
        let sure = CollectionPlacement(keyword: "@household", confidence: .high, provider: .anthropic)
        let unsure = CollectionPlacement(keyword: "@household", confidence: .medium, provider: .anthropic)
        let apple = CollectionPlacement(keyword: "@household", confidence: .high, provider: .appleIntelligence)
        let appleOther = CollectionPlacement(keyword: "@tools", confidence: .high, provider: .appleIntelligence)
        #expect(CollectionPolicy.autoPlace(cloud: sure, onDevice: nil) == "@household")
        #expect(CollectionPolicy.autoPlace(cloud: unsure, onDevice: apple) == "@household")
        #expect(CollectionPolicy.autoPlace(cloud: unsure, onDevice: appleOther) == nil)
        #expect(CollectionPolicy.autoPlace(cloud: nil, onDevice: apple) == nil)
        #expect(CollectionPolicy.ask(cloud: unsure, onDevice: appleOther) == "@tools")
    }

    @Test func proposalsAreCheckedAndAtSignedAndNeverReserved() {
        let json = """
            {"collections":[
              {"name":"Money","labels":["budgeting","home","made-up"]},
              {"name":"pages","labels":["cli","editors"]},
              {"name":"work stuff","labels":["home","meetings"]},
              {"name":"solo","labels":["editors"]}
            ]}
            """
        let proposals = CollectionPlanner.proposals(
            from: json, names: ["budgeting", "home", "cli", "editors", "meetings"], existing: ["@household", "@tools"])
        #expect(proposals == [ProposedCollection(keyword: "@money", labels: ["budgeting", "home"])])
    }

    @Test func fewerThanTwoLooseLabelsProposeNothing() async throws {
        let engine = JSONEngine(.anthropic, answer: #"{"collections":[]}"#)
        let proposals = try await CollectionPlanner(chain: EngineChain([engine])).propose(
            for: [LooseLabel(name: "one")], existing: [])
        #expect(proposals.isEmpty)
        #expect(engine.last == nil)
    }
}
