import Foundation
import Testing

@testable import ShioriAI

/// A user's conventions come from the build (local.yml); Machiya's own
/// stay in code.
struct BuildDefaultsTests {
    @Test func machiyasNamesAreBuiltIn() {
        #expect(LabelClassifier.notTopics.contains("vault"))
        #expect(CollectionPlanner.reserved.isSuperset(of: ["notes", "pages"]))
    }

    @Test func aBuildsListIsCommaSeparatedAndTrimmed() {
        setenv("SHIORI_TEST_LIST", " alpha, beta ,,gamma ", 1)
        defer { unsetenv("SHIORI_TEST_LIST") }
        #expect(BuildDefaults.list(plistKey: "", environment: "SHIORI_TEST_LIST") == ["alpha", "beta", "gamma"])
        #expect(BuildDefaults.list(plistKey: "", environment: "SHIORI_TEST_UNSET").isEmpty)
    }
}
