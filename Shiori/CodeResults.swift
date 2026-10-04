import HisterKit
import SwiftUI

/// The Code pill: the owner's repos in Hister (code-import's repo cards,
/// READMEs and docs, issues, PRs and releases), searched as you type (it's
/// Hister's own index: nothing is spent), never shown anywhere else. Above
/// the list, the kind and Open Only, as metadata terms (`CodeDocs.query`).
struct CodeResults: View {
    let query: String
    /// Newest first when browsing (the Library), best match for a search.
    var sort: SearchSort = .relevance
    @Environment(\.palette) private var palette
    @State private var filters = CodeDocs.Filters()

    var body: some View {
        CodeList(query: query, sort: sort, filters: filters)
            .id(filters)
            .topBar {
                HStack(spacing: 14) {
                    Menu {
                        Picker("Kind", selection: $filters.kind) {
                            Text("Everything").tag(CodeDocs.Kind?.none)
                            ForEach(CodeDocs.Kind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(CodeDocs.Kind?.some(kind))
                            }
                        }
                    } label: {
                        Label(filters.kind?.title ?? "Everything", systemImage: "line.3.horizontal.decrease")
                    }
                    // Which forge: All Hosts, Forgejo or GitHub.
                    Menu {
                        Picker("Host", selection: $filters.host) {
                            Text("All Hosts").tag(String?.none)
                            ForEach(CodeDocs.hosts, id: \.key) { host in
                                Text(host.name).tag(String?.some(host.key))
                            }
                        }
                    } label: {
                        Label(filters.host.map(CodeDocs.hostName) ?? "All Hosts", systemImage: "server.rack")
                    }
                    Toggle("Open Only", isOn: $filters.open)
                        .toggleStyle(.button)
                    Toggle("Private", isOn: $filters.privateOnly)
                        .toggleStyle(.button)
                    Spacer()
                }
                .textStyle(.subheadline)
                .buttonStyle(.borderless)
                .tint(palette.tint(SearchScope.code.tint))
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
    }
}

private struct CodeList: View {
    let query: String
    let filters: CodeDocs.Filters
    @State private var model: ResultsModel

    init(query: String, sort: SearchSort, filters: CodeDocs.Filters) {
        self.query = query
        self.filters = filters
        _model = State(initialValue: ResultsModel(query: CodeDocs.query(query, filters: filters), sort: sort))
    }

    var body: some View {
        ResultsList(model: model, title: query) {
            ContentUnavailableView.search(text: query)
        }
    }
}

extension CodeInfo {
    /// The kind's symbol, for a code row.
    var symbol: String {
        switch kind {
        case "repo": "shippingbox"
        case "readme", "doc": "doc.text"
        case "issue": "smallcircle.filled.circle"
        case "pr": "arrow.triangle.pull"
        case "release": "tag"
        default: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// The kind in words, for VoiceOver.
    var kindName: String {
        switch kind {
        case "repo": "Repository"
        case "readme": "README"
        case "doc": "Document"
        case "issue": "Issue"
        case "pr": "Pull request"
        case "release": "Release"
        default: "Code"
        }
    }
}
