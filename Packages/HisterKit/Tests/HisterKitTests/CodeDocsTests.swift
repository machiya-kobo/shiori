import Foundation
import Testing

@testable import HisterKit

/// The same cases as search-core.test.mjs's "Code" test.
struct CodeDocsTests {
    @Test func codeIsLeftOutOfEveryOtherQuery() {
        #expect(SearchText.forHister("kura") == "(kura|kura*) -label:vault -metadata.source:vault -type:local -metadata.source:code")
        #expect(SearchText.forHister(CodeDocs.query("tag page")) == "metadata.source:code tag (page|page*) -label:vault -metadata.source:vault -type:local")
        #expect(SearchText.forHister(SearchText.forHister("x")) == SearchText.forHister("x"))
        #expect(OpenedEntry(id: 1, url: "https://a.example/", title: "A", query: SearchText.forHister("kura"), added: .now).typedQuery == "kura")
    }

    @Test func filtersAreMetadataTermsBeforeTheWords() {
        #expect(CodeDocs.query("") == "metadata.source:code *")
        #expect(CodeDocs.query("fix", filters: .init(kind: .pr, open: true)) == "metadata.source:code metadata.code_kind:pr metadata.code_state:open fix")
        #expect(CodeDocs.query("", filters: .init(kind: .docs)) == "metadata.source:code metadata.code_kind:(readme|doc) *")
        #expect(CodeDocs.query("", filters: .init(host: "Git Hub")) == "metadata.source:code *")
        #expect(CodeDocs.query("x", filters: .init(host: "forgejo", repo: "Machiya-Kobo/Kura", privateOnly: true))
            == "metadata.source:code metadata.code_host:forgejo metadata.code_repo:machiya_kobo__kura metadata.code_private:true x")
        #expect(CodeDocs.repoKey("machiya-kobo/kura") == "machiya_kobo__kura")
    }

    @Test func aRowsFactsComeFromItsMetadata() throws {
        let json = #"{"total":1,"documents":[{"url":"https://github.example/o/r/pull/3","title":"Fix","metadata":{"source":"code","code_kind":"pr","code_host":"github","code_repo":"o__r","code_repo_name":"o/r","code_state":"merged","code_private":"true","code_number":3}},{"url":"https://a.example/","metadata":{"source":"shiori"}},{"url":"https://b.example/"}]}"#
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))
        let pages = (response.documents ?? []).map(\.document)
        #expect(pages[0].code == CodeInfo(kind: "pr", host: "github", repo: "o__r", repoName: "o/r", state: "merged", isPrivate: true, number: "3"))
        #expect(pages[1].code == nil)
        #expect(pages[2].code == nil)
    }

    @Test func rowsNameTheirForge() {
        #expect(CodeDocs.hostName("forgejo") == "Forgejo")
        #expect(CodeDocs.hostName("github") == "GitHub")
        #expect(CodeDocs.hostName("gitea") == "gitea")
        #expect(CodeDocs.hosts.map(\.key) == ["forgejo", "github"])
        #expect(CodeDocs.query("", filters: .init(host: "github")) == "metadata.source:code metadata.code_host:github *")
    }

    @Test func theRepoNote() {
        #expect(CodeDocs.notePath(repoName: "machiya-kobo/kura") == "Repos/kura.git.md")
        #expect(CodeDocs.notePath(repoName: "o/a b") == nil)
        #expect(CodeDocs.notePath(repoName: "../x") == "Repos/x.git.md")
    }

    @Test func codeAliasesAreNoCollections() {
        #expect(Rules.namesTheVault("metadata.source:code"))
        #expect(!Rules.namesTheVault("label:(a|b)"))
    }
}

struct CodeFoldTests {
    @Test func codeNeverFoldsBySite() {
        let pages = (1...4).map { n in
            var p = StoredPage(url: "https://github.example.com/o/r/issues/\(n)", title: "\(n)", domain: "github.example.com", label: "",
                               added: .now, updated: .now, faviconKey: "", snippetHTML: "")
            p.code = CodeInfo(kind: "issue")
            return p
        }
        #expect(SiteRuns.items(pages).count == 4)
    }
}
