import Testing

@testable import HisterKit

/// The same cases as search-core.test.mjs's correctedQuery tests.
struct RespellingTests {
    @Test func editDistanceCountsASwappedPairAsOneEdit() {
        #expect(Respelling.editDistance("rasbperry", "raspberry") == 1)
        #expect(Respelling.editDistance("pythn", "python") == 1)
        #expect(Respelling.editDistance("pi", "pi") == 0)
        #expect(Respelling.editDistance("", "abc") == 3)
    }

    @Test func aRespellingFromTheWebsRelatedSearches() {
        #expect(Respelling.corrected("rasbperry pi", suggestions: ["raspberry pi 5", "raspberry pi price"]) == "raspberry pi")
        #expect(Respelling.corrected("Pythn", suggestions: ["python 3.12 7"]) == "python")
        #expect(Respelling.corrected("pythn docker", suggestions: ["python 3.12 7", "update python docker"]) == "python docker")
        #expect(Respelling.corrected("rust", suggestions: ["python tutorial"]) == nil)
        #expect(Respelling.corrected("go pi", suggestions: ["go pie"]) == nil)
        #expect(Respelling.corrected("raspberry pi", suggestions: ["raspberry pi 5"]) == nil)
        #expect(Respelling.corrected("rasbperry", suggestions: []) == nil)
        #expect(Respelling.corrected("label:books rasbperry", suggestions: ["raspberry"]) == nil)
        #expect(Respelling.corrected("\"rasbperry pi\"", suggestions: ["raspberry pi"]) == nil)
        #expect(Respelling.corrected("", suggestions: ["x"]) == nil)
    }
}

@Suite struct DidYouMeanTests {
    @Test func respellsFromTheWebEvenWhenSomethingWasFound() {
        let orwell = ["george orwell", "george orwell 1984", "george orwell books", "george orwell quotes"]
        #expect(Respelling.didYouMean("george orewell", suggestions: orwell) == "george orwell")
        #expect(Respelling.didYouMean("George  Orewell", suggestions: orwell) == "george orwell")
        let pi = ["raspberry pi imager", "raspberry pi 5", "raspberry pi connect", "raspberry pi 4", "raspberry pie", "raspberrypi", "raspberry pi pico"]
        #expect(Respelling.didYouMean("rapsberrypi", suggestions: pi) == "raspberry pi")
        #expect(Respelling.didYouMean("raspbery pi pico", suggestions: ["raspberry pi pico", "raspberry pi pico pinout", "raspberry pi pico 2"]) == "raspberry pi pico")
        #expect(Respelling.didYouMean("raspberrypi", suggestions: pi) == "raspberry pi")
    }

    @Test func nothingWhenRightTooFarTooShortOrSyntax() {
        let orwell = ["george orwell", "george orwell 1984", "george orwell books", "george orwell quotes"]
        #expect(Respelling.didYouMean("george orwell", suggestions: orwell) == nil)
        #expect(Respelling.didYouMean("orwell essays", suggestions: orwell) == nil)
        #expect(Respelling.didYouMean("rust", suggestions: ["rest", "rust lang"]) == nil)
        #expect(Respelling.didYouMean("label:foo orewell", suggestions: orwell) == nil)
        #expect(Respelling.didYouMean("george orewell", suggestions: []) == nil)
        // Each changed word within its own room, not the whole query's.
        #expect(Respelling.didYouMean("github machiya", suggestions: ["github machine", "github machine learning"]) == nil)
        #expect(Respelling.didYouMean("github machne", suggestions: ["github machine", "github machine learning"]) == "github machine")
        #expect(Respelling.didYouMean("raspberry pi", suggestions: ["raspberry pi 5", "raspberry pi 4", "raspberry pi pico", "raspberrypi"]) == nil)
    }
}

@Suite struct TypeAheadTests {
    @Test func theRestOfTheFirstCandidateThatStartsWithWhatIsTyped() {
        let candidates = ["raspberry pi", "raspberry pi 5", "Rust lang"]
        #expect(Respelling.typeAhead("raspb", candidates: candidates) == "erry pi")
        #expect(Respelling.typeAhead("RASPB", candidates: candidates) == "erry pi")
        #expect(Respelling.typeAhead("raspberry ", candidates: candidates) == "pi")
        #expect(Respelling.typeAhead("rus", candidates: candidates) == "t lang")
        #expect(Respelling.typeAhead("raspberry pi", candidates: candidates) == " 5")
        #expect(Respelling.typeAhead("r", candidates: candidates) == "")
        #expect(Respelling.typeAhead("zebra", candidates: candidates) == "")
        #expect(Respelling.typeAhead("raspberry pi 5", candidates: candidates) == "")
    }
}
