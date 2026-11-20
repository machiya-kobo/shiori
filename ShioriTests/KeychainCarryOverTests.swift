import Foundation
import Testing

/// Nogon's Keychain items were under the service "Hister". These run the carry-over against services of their own,
/// never the app's real items, and remove them afterwards.
@Suite(.serialized) struct KeychainCarryOverTests {
    let service = "shiori.tests.nogon." + UUID().uuidString
    let old = "shiori.tests.hister." + UUID().uuidString

    func clean() {
        for name in ["token", "session"] {
            SharedKeychain.save("", service: service, account: name)
            SharedKeychain.save("", service: old, account: name)
        }
    }

    @Test func anOldItemIsReadAndCarriedOverOnce() {
        defer { clean() }
        #expect(SharedKeychain.save("old-token", service: old, account: "token"))
        // An extension reads it, and leaves it where it is.
        #expect(HisterKeychain.read("token", service: service, oldService: old, carryOver: false) == "old-token")
        #expect(SharedKeychain.read(service: service, account: "token") == "")
        #expect(SharedKeychain.read(service: old, account: "token") == "old-token")
        // The app moves it: kept under the new service, gone from the old.
        #expect(HisterKeychain.read("token", service: service, oldService: old, carryOver: true) == "old-token")
        #expect(SharedKeychain.read(service: service, account: "token") == "old-token")
        #expect(SharedKeychain.read(service: old, account: "token") == "")
        #expect(HisterKeychain.read("token", service: service, oldService: old, carryOver: true) == "old-token")
    }

    @Test func theNewItemWins() {
        defer { clean() }
        SharedKeychain.save("new", service: service, account: "token")
        SharedKeychain.save("stale", service: old, account: "token")
        #expect(HisterKeychain.read("token", service: service, oldService: old, carryOver: true) == "new")
    }

    @Test func aSaveOrASignOutRemovesTheOldItemSoNothingComesBack() {
        defer { clean() }
        SharedKeychain.save("old-session", service: old, account: "session")
        #expect(HisterKeychain.save("", "session", service: service, oldService: old))
        #expect(HisterKeychain.read("session", service: service, oldService: old, carryOver: true) == "")
        SharedKeychain.save("old-token", service: old, account: "token")
        #expect(HisterKeychain.save("fresh", "token", service: service, oldService: old))
        #expect(SharedKeychain.read(service: old, account: "token") == "")
        #expect(HisterKeychain.read("token", service: service, oldService: old, carryOver: true) == "fresh")
    }
}
