import Foundation
import HisterKit
import Testing

/// A defaults suite of its own, gone when the test is. (Nonisolated so
/// its deinit may touch `defaults`; UserDefaults is thread-safe.)
nonisolated final class TempDefaults {
    let name = "shiori.tests." + UUID().uuidString
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

/// The whitelist that stands between Safari's results page (and the
/// server's settings document) and the App Group.
struct SharedSettingsTests {
    let temp = TempDefaults()
    var defaults: UserDefaults { temp.defaults }

    @Test func applyTakesKnownKeysWithTheRightTypeAndValue() {
        let wrote = SharedSettings.apply(
            [
                "showInfobox": true,
                "webResults": "yes",  // a flag must be a Bool
                "histerCount": 7,  // not one of the page counts
                "vaultCount": 10,
                "searxngURL": "ftp://x/",  // http(s) only
                "niwaURL": "https://niwa.example/",
                "theme": "purple",
                "textSize": "large",
                "obsidianVault": "",  // never empty
                "bogus": 1,
            ], to: defaults)
        #expect(wrote)
        #expect(defaults.object(forKey: "showInfobox") as? Bool == true)
        #expect(defaults.object(forKey: "webResults") == nil)
        #expect(defaults.object(forKey: "histerCount") == nil)
        #expect(defaults.object(forKey: "vaultCount") as? Int == 10)
        #expect(defaults.object(forKey: "searxngURL") == nil)
        #expect(defaults.string(forKey: "niwaURL") == "https://niwa.example/")
        #expect(defaults.object(forKey: "theme") == nil)
        #expect(defaults.string(forKey: "textSize") == "large")
        #expect(defaults.object(forKey: "obsidianVault") == nil)
        #expect(defaults.object(forKey: "bogus") == nil)
    }

    @Test func theServerAddressIsNeverTakenFromOutside() {
        SharedSettings.apply(["serverURL": "https://elsewhere.example/"], to: defaults)
        #expect(defaults.object(forKey: SharedSettings.Key.serverURL) == nil)
    }

    @Test func nothingUsableWritesNothing() {
        #expect(!SharedSettings.apply(["bogus": true, "theme": 3], to: defaults))
    }

    @Test func aChangeFromThePageIsKept() {
        SharedSettings.applyFromPage(["theme": "day"], to: defaults)
        #expect(defaults.string(forKey: "theme") == "day")
    }

    @Test func aThemeFromThePageIsOneOfTheRoomsTen() {
        SharedSettings.applyFromPage(["palette": "nord"], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.palette) == "nord")
        SharedSettings.applyFromPage(["palette": "purple"], to: defaults)
        SharedSettings.applyFromPage(["palette": 3], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.palette) == "nord")
        #expect(SharedSettings.extensionPayload(from: defaults)[SharedSettings.Key.palette] as? String == "nord")
        // The extension's list is the app's.
        #expect(SharedSettings.palettes == AppPalette.all.map(\.key))
    }

    @Test func smallWebOpensOnlyWhereItCan() {
        SharedSettings.applyFromPage(["smallWebOpen": "direct", "smallWebTab": false], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.smallWebOpen) == "direct")
        #expect(defaults.object(forKey: SharedSettings.Key.smallWebTab) as? Bool == false)
        SharedSettings.applyFromPage(["smallWebOpen": "somewhere"], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.smallWebOpen) == "direct")
    }

    @Test func notesComeFromKuraOrHisterOnly() {
        SharedSettings.applyFromPage(["notesSource": "hister"], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.notesSource) == "hister")
        SharedSettings.applyFromPage(["notesSource": "somewhere"], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.notesSource) == "hister")
        SharedSettings.applyFromPage(["notesSource": true], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.notesSource) == "hister")
        // "" puts it back to the default (Kura when one is set up).
        SharedSettings.applyFromPage(["notesSource": ""], to: defaults)
        #expect(defaults.string(forKey: SharedSettings.Key.notesSource) == "")
        SharedSettings.applyFromPage(["notesSource": "kura"], to: defaults)
        #expect(SharedSettings.extensionPayload(from: defaults)[SharedSettings.Key.notesSource] as? String == "kura")
    }

    @Test func whereNotesComeFromStaysOnThisDevice() {
        // Never one of the settings that follow the person to the account.
        #expect(PrefsSync.shioriKeys[SharedSettings.Key.notesSource] == nil)
        #expect(PrefsSync.accountValues([SharedSettings.Key.notesSource: "hister"]).isEmpty)
    }

    @Test func turningHistoryOffClearsIt() {
        SharedSettings.recordSearch("rust", in: defaults)
        #expect(SharedSettings.recentSearches(in: defaults) == ["rust"])
        SharedSettings.apply(["searchHistory": false], to: defaults)
        #expect(defaults.stringArray(forKey: SharedSettings.Key.recentSearches) == nil)
        // And while off, nothing is kept.
        SharedSettings.recordSearch("go", in: defaults)
        #expect(SharedSettings.recentSearches(in: defaults).isEmpty)
    }

    @Test func recentSearchesKeepFiveNewestFirstOnceEachWhateverTheCase() {
        for query in ["Rust", " rust ", "a", "b", "c", "d", "e"] {
            SharedSettings.recordSearch(query, in: defaults)
        }
        #expect(SharedSettings.recentSearches(in: defaults) == ["e", "d", "c", "b", "a"])
        SharedSettings.recordSearch("", in: defaults)
        SharedSettings.recordSearch(String(repeating: "x", count: 501), in: defaults)
        #expect(SharedSettings.recentSearches(in: defaults) == ["e", "d", "c", "b", "a"])
        SharedSettings.recordSearch("B", in: defaults)
        #expect(SharedSettings.recentSearches(in: defaults) == ["B", "e", "d", "c", "a"])
    }

    @Test func thePageCanClearTheHistory() {
        SharedSettings.recordSearch("rust", in: defaults)
        SharedSettings.applyFromPage(["clearRecentSearches": true], to: defaults)
        #expect(SharedSettings.recentSearches(in: defaults).isEmpty)
    }

    @Test func theExtensionGetsOnlyWhatTheAppSet() {
        let empty = SharedSettings.extensionPayload(from: defaults)
        #expect(empty.keys.sorted() == [SharedSettings.Key.recentSearches])
        defaults.set(false, forKey: SharedSettings.Key.combinedSearch)
        defaults.set("https://hister.example/", forKey: SharedSettings.Key.serverURL)
        defaults.set(5, forKey: SharedSettings.Key.histerCount)
        let payload = SharedSettings.extensionPayload(from: defaults)
        #expect(payload[SharedSettings.Key.combinedSearch] as? Bool == false)
        #expect(payload[SharedSettings.Key.serverURL] as? String == "https://hister.example/")
        #expect(payload[SharedSettings.Key.histerCount] as? Int == 5)
    }
}
