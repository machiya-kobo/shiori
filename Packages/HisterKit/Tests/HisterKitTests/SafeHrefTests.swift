import Foundation
import Testing
@testable import HisterKit

/// The same cases as search-core.test.mjs's safeHref test.
struct SafeHrefTests {
    @Test func theWebOpens() {
        #expect(SafeHref.url("https://a.example/x?y=1")?.absoluteString == "https://a.example/x?y=1")
        #expect(SafeHref.url("http://a.example")?.host() == "a.example")
    }

    @Test func nothingElseDoes() {
        for bad in ["javascript://example.com/%0Aalert(document.domain)", "JavaScript:alert(1)", " \tjava\nscript:alert(1)",
                    "data:text/html,<script>alert(1)</script>", "vbscript:x", "file:///etc/passwd", "obsidian://open?vault=x",
                    "", "   ", "not a url"] {
            #expect(SafeHref.url(bad) == nil, "\(bad)")
        }
        #expect(SafeHref.url(nil) == nil)
    }
}
