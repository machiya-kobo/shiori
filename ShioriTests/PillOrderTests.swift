import Foundation
import Testing

/// The same cases as search-core.test.mjs's "the pills" test, and the
/// whitelist's handling of the setting.
struct PillOrderTests {
    let temp = TempDefaults()

    @Test func theSettingIsChecked() {
        #expect(PillOrder.clean(["notes", "-web", "all"]) == ["notes", "-web", "all"])
        #expect(PillOrder.clean(["-all", "pages"]) == ["all", "pages"])
        #expect(PillOrder.clean(["notes", "notes"]) == [])
        #expect(PillOrder.clean(["notes", "bogus"]) == [])
        #expect(PillOrder.clean("notes") == [])
        #expect(PillOrder.clean([1]) == [])
    }

    @Test func orderAndVisibility() {
        let available = ["all", "pages", "notes", "web", "smallweb"]
        #expect(PillOrder.ordered(available: available, []) == available)
        #expect(PillOrder.ordered(available: available, ["notes", "-web", "all"]) == ["notes", "all", "pages", "smallweb"])
    }

    @Test func movesAmongASurfacesOwnPills() {
        let among = ["all", "pages", "notes", "web"]
        #expect(Array(PillOrder.changed([], among: among, key: "web", by: -1).prefix(4)) == ["all", "pages", "web", "notes"])
        #expect(Array(PillOrder.changed(["all", "images", "pages"], among: among, key: "pages", by: -1).prefix(3)) == ["pages", "images", "all"])
        #expect(Array(PillOrder.changed([], among: among, key: "all", by: -1).prefix(2)) == ["all", "pages"])
        #expect(PillOrder.changed([], among: among, key: "web", shown: false).contains("-web"))
        #expect(PillOrder.changed([], among: among, key: "all", shown: false).contains("all"))
        #expect(PillOrder.changed([], among: among, key: "web", shown: false).count == PillOrder.keys.count)
    }

    @Test func thePageMaySetItOnlyWhenSound() {
        let defaults = temp.defaults
        SharedSettings.apply(["pills": ["notes", "-web"]], to: defaults)
        #expect(defaults.stringArray(forKey: "pills") == ["notes", "-web"])
        SharedSettings.apply(["pills": ["notes", "evil"]], to: defaults)
        #expect(defaults.stringArray(forKey: "pills") == ["notes", "-web"])
        #expect(SharedSettings.extensionPayload(from: defaults)["pills"] as? [String] == ["notes", "-web"])
        SharedSettings.apply(["pills": [String]()], to: defaults)
        #expect(defaults.stringArray(forKey: "pills") == [])
    }
}
