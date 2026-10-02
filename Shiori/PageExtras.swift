import HisterKit
import SwiftUI

/// An image from a preview, large: pinch or scroll to zoom, and Open in
/// Browser for the original. Only reached with Images in Previews on.
struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.palette) private var palette
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    /// The image itself, without the marker `linkingImages` added.
    private var source: URL {
        guard url.fragment == PreviewPage.imageMarker,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        else { return url }
        components.fragment = nil
        return components.url ?? url
    }

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: source) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoom * pinch)
                            .accessibilityLabel("Image from the page")
                    case .failure:
                        ContentUnavailableView("Image Not Loaded", systemImage: "photo.badge.exclamationmark")
                    default:
                        ProgressView()
                    }
                }
                .frame(minWidth: 280, minHeight: 280)
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 6) }
                )
                .onTapGesture(count: 2) { zoom = zoom > 1 ? 1 : 2.5 }
            }
            .background(palette.background)
            .navigationTitle(source.lastPathComponent)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Open in Browser", systemImage: "safari") { openURL(source) }
                        .help("Open in browser")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }
}

/// A page's stored earlier versions (the server's versioning rules decide
/// which pages keep them), each as what changed.
struct VersionsView: View {
    let title: String
    let versions: [PageVersion]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            List(versions) { version in
                NavigationLink {
                    DiffView(version: version)
                        .navigationTitle(version.created.formatted(date: .abbreviated, time: .shortened))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.created.formatted(date: .abbreviated, time: .shortened))
                            .textStyle(.headline)
                        Text(DiffView.summary(version.textDiff))
                            .textStyle(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .listRowBackground(palette.surface)
            }
            .themedBackground()
            .navigationTitle("Earlier Versions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}

/// A text diff, added lines green, removed ones red.
struct DiffView: View {
    let version: PageVersion
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(version.textDiff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : String(line))
                        .textStyle(.footnote, design: .monospaced)
                        .foregroundStyle(color(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .background(background(for: line))
                        .accessibilityLabel(accessibility(for: line))
                }
            }
            .padding()
            .textSelection(.enabled)
        }
        .background(palette.background)
    }

    private func color(for line: Substring) -> Color {
        line.hasPrefix("+") ? .green : line.hasPrefix("-") ? palette.danger : palette.text
    }

    private func background(for line: Substring) -> Color {
        line.hasPrefix("+") ? Color.green.opacity(0.12) : line.hasPrefix("-") ? palette.danger.opacity(0.12) : .clear
    }

    private func accessibility(for line: Substring) -> String {
        line.hasPrefix("+") ? "Added: \(line.dropFirst())" : line.hasPrefix("-") ? "Removed: \(line.dropFirst())" : String(line)
    }

    /// "12 lines added, 3 removed".
    static func summary(_ diff: String) -> String {
        let lines = diff.split(separator: "\n")
        let added = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let removed = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        return "\(added) \(added == 1 ? "line" : "lines") added, \(removed) removed"
    }
}

/// An image tapped in a preview, for `.sheet(item:)`.
struct EnlargedImage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Set by the Mac and iPad layout: the preview pane can fill the window.
struct PreviewFocus {
    var isOn: Bool
    var toggle: () -> Void
}

extension EnvironmentValues {
    @Entry var previewFocus: PreviewFocus? = nil
}

/// Add a page by its address: then the same Save sheet as a web result
/// (label, and the outbox if Hister is out of reach).
struct AddPageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var address = ""
    @State private var chosen: URL?

    var body: some View {
        if let chosen {
            SaveSheet(input: .init(url: chosen))
        } else {
            NavigationStack {
                Form {
                    Section {
                        TextField("Address", text: $address, prompt: Text("https://example.com/article"))
                            .textContentType(.URL)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .onSubmit(next)
                    } footer: {
                        Text("Shiori downloads the page and saves it to Hister, as the share sheet does.")
                    }
                    .listRowBackground(palette.surface)
                }
                .formStyle(.grouped)
                .themedBackground()
                .navigationTitle("Save Page in Hister")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Next", action: next)
                            .disabled(Self.url(from: address) == nil)
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 200)
            #endif
        }
    }

    private func next() {
        if let url = Self.url(from: address) { chosen = url }
    }

    /// http(s) with a host; "example.com/x" gets https:// added.
    static func url(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.lowercased().hasPrefix("http://"), !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s), url.host()?.contains(".") == true else { return nil }
        return url
    }
}

extension FocusedValues {
    /// The window's search, for the Mac's Search menu.
    @Entry var searchSession: SearchSession?
    /// The list on screen, for File → Export and its feed (the Mac).
    @Entry var listExport: ListExport?
}

/// What can be done with the list on screen: File → Export on the Mac,
/// Settings → Export & Feed on iOS (`listActions`).
struct ListExport {
    var title: String
    var feed: URL?
    /// Nil for a list that can't be exported (Opened: feed only). The Mac:
    /// the list saves the file itself.
    var export: ((Export.Format) -> Void)?
    /// The file, for Settings to save (a sheet can't present the list's
    /// own exporter beneath it).
    var makeFile: ((Export.Format) async throws(HisterError) -> ExportFile)?

    /// Which list this is, to notice another taking its place.
    var id: String { title + "\u{1}" + (feed?.absoluteString ?? "") }
}

extension View {
    /// The list's Export and feed: in File on the Mac, the list last shown
    /// in Settings on iOS (it follows tabs and pushes as they appear).
    func listActions(_ list: ListExport) -> some View {
        modifier(ListActions(list: list))
    }
}

private struct ListActions: ViewModifier {
    let list: ListExport
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        #if os(macOS)
        content.focusedSceneValue(\.listExport, list)
        #else
        content
            .onAppear { app.shownList = list }
            .onChange(of: list.id) { app.shownList = list }
        #endif
    }
}

#if os(macOS)
/// Search → All / Hister / Notes / Web (⌘1–⌘4), and File → Add Page….
struct SearchCommands: Commands {
    let app: AppState
    @FocusedValue(\.searchSession) private var session
    @FocusedValue(\.listExport) private var list

    var body: some Commands {
        CommandMenu("Search") {
            ForEach(Array(app.searchScopes.enumerated()), id: \.element) { index, scope in
                Button("Search \(scope.title)") { session?.scope = scope }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(session == nil)
            }
        }
        CommandGroup(after: .newItem) {
            Button("Add Page…") { app.addPageRequests += 1 }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        // Not everyday actions, so out of the list's own row.
        CommandGroup(replacing: .importExport) {
            Menu("Export List") {
                ForEach(Export.Format.allCases) { format in
                    Button("\(format.title)…") { list?.export?(format) }
                }
            }
            .disabled(list?.export == nil)
            Divider()
            Button("Copy Feed Link") { if let feed = list?.feed { Pasteboard.copy(feed) } }
                .disabled(list?.feed == nil)
            Button("Subscribe in NewsBlur") {
                if let feed = list?.feed, let url = Export.newsBlurSubscribeURL(newsBlur: app.searchPage.newsBlurURL, feed: feed) {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(list?.feed == nil || app.searchPage.newsBlurURL.isEmpty)
        }
    }
}
#endif
