import Foundation
import Testing
@testable import HisterKit

struct ElsewhereTests {
    let instances = Elsewhere.instances(from: "redlib=https://redlib.example.ts.net/, invidious=https://invidious.example.ts.net,breezewiki=https://bw.example.ts.net/,libmedium=https://libmedium.example.ts.net/,unknown=https://x.example/,nitter=ftp://n.example/")

    private func links(_ url: String) -> [String] {
        Elsewhere.frontends(for: url, instances: instances).map { "\($0.name) \($0.url.absoluteString)" }
    }

    @Test func archivesTakeTheWholeAddress() {
        #expect(Elsewhere.wayback("https://a.example/x?y=1")?.absoluteString == "https://web.archive.org/web/https://a.example/x?y=1")
        #expect(Elsewhere.archiveToday("https://a.example/x?y=1")?.absoluteString == "https://archive.is/newest/https://a.example/x?y=1")
        #expect(Elsewhere.wayback("gemini://a.example/") == nil)
        #expect(Elsewhere.archiveToday("file:///Users/x") == nil)
    }

    @Test func onlyKnownFrontEndsWithAWebAddressCount() {
        #expect(instances.map(\.frontend.key) == ["redlib", "invidious", "breezewiki", "libmedium"])
        #expect(Elsewhere.instances(from: "").isEmpty)
    }

    @Test func redditGoesToRedlib() {
        #expect(links("https://www.reddit.com/r/raspberry_pi/comments/abc/a_title/?sort=new")
            == ["Redlib https://redlib.example.ts.net/r/raspberry_pi/comments/abc/a_title/?sort=new"])
        #expect(links("https://old.reddit.com/r/unix/") == ["Redlib https://redlib.example.ts.net/r/unix/"])
        #expect(links("https://redd.it/abc123") == ["Redlib https://redlib.example.ts.net/comments/abc123"])
    }

    @Test func youTubeGoesToInvidious() {
        #expect(links("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42") == ["Invidious https://invidious.example.ts.net/watch?v=dQw4w9WgXcQ&t=42"])
        #expect(links("https://youtu.be/dQw4w9WgXcQ?t=42") == ["Invidious https://invidious.example.ts.net/watch?v=dQw4w9WgXcQ&t=42"])
        #expect(links("https://www.youtube.com/shorts/abcDEF") == ["Invidious https://invidious.example.ts.net/watch?v=abcDEF"])
        #expect(links("https://www.youtube.com/@channel/videos") == ["Invidious https://invidious.example.ts.net/@channel/videos"])
    }

    @Test func fandomGoesToBreezeWiki() {
        #expect(links("https://zelda.fandom.com/wiki/Link") == ["BreezeWiki https://bw.example.ts.net/zelda/wiki/Link"])
        #expect(links("https://www.fandom.com/") == [])
    }

    @Test func mediumGoesToLibMedium() {
        #expect(links("https://medium.com/@someone/a-post-123abc") == ["LibMedium https://libmedium.example.ts.net/@someone/a-post-123abc"])
    }

    @Test func aFrontEndPageOpensOnItsOwnSiteToo() {
        let original = { (url: String) in Elsewhere.original(of: url, instances: instances).map { "\($0.site) \($0.url.absoluteString)" } }
        #expect(original("https://redlib.example.ts.net/r/unix/comments/abc/a_title/?sort=new") == "Reddit https://www.reddit.com/r/unix/comments/abc/a_title/?sort=new")
        #expect(original("https://invidious.example.ts.net/watch?v=dQw4w9WgXcQ&t=42") == "YouTube https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42")
        #expect(original("https://bw.example.ts.net/zelda/wiki/Link") == "Fandom https://zelda.fandom.com/wiki/Link")
        #expect(original("https://libmedium.example.ts.net/@someone/a-post-123abc") == "Medium https://medium.com/@someone/a-post-123abc")
        #expect(original("https://www.reddit.com/r/unix/") == nil)
        #expect(original("https://redlib.example.ts.net.evil.example/r/unix/") == nil)
        #expect(original("https://bw.example.ts.net/") == nil)
    }

    @Test func otherSitesAndUnconfiguredFrontEndsGetNothing() {
        #expect(links("https://a.example/r/unix/") == [])
        #expect(links("https://reddit.com.evil.example/r/x") == [])
        // Nitter's address wasn't http(s): ignored.
        #expect(links("https://x.com/someone") == [])
        #expect(Elsewhere.frontends(for: "https://www.reddit.com/r/x", instances: []).isEmpty)
    }
}
