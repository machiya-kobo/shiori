import HisterKit
import SwiftUI

/// Images, Videos and News: SearXNG's categories, with their own row of
/// choices under the pills (`WebChoices`: an order and filters, as the
/// search page's), drawn from the results already fetched; a choice narrows
/// or reorders them in place, never another web search. Images are a grid
/// with a viewer; Videos and News are rows, as Web's.
struct WebCategoryResults: View {
    let model: WebResultsModel

    @Environment(AppState.self) private var app
    @Environment(SearchSession.self) private var session: SearchSession?
    @Environment(\.palette) private var palette
    /// Without a session (a preview), the choices live here.
    @State private var ownChoices = WebChoices.Choices()
    @State private var viewing: Int?

    private var scope: SearchScope { SearchScope(rawValue: model.category ?? "") ?? .web }
    private var category: String { model.category ?? "" }

    private var choices: WebChoices.Choices {
        session?.webChoices[scope] ?? ownChoices
    }

    private func choose(_ key: String, _ value: String) {
        var next = choices
        next[key] = value
        if let session { session.webChoices[scope] = next } else { ownChoices = next }
    }

    private var shown: [WebResult] {
        WebChoices.narrow(category, model.results, choices, item: \.choiceItem)
    }

    var body: some View {
        content
            .topBar { choicesRow }
    }

    @ViewBuilder private var content: some View {
        let shown = shown
        if shown.isEmpty {
            ContentUnavailableView("Nothing Matches These Filters", systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("Choose Any in a filter to see more."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
        } else if category == "images" {
            ImageGrid(model: model, results: shown, viewing: $viewing)
        } else {
            List {
                EngineHealthRow(names: model.unanswered)
                ForEach(shown) { result in
                    WebItem(result: result, query: model.query, saved: model.saved[result.url])
                        .task { await model.loadMoreIfNeeded(after: result, searx: app.searx, hister: app.client) }
                }
                MoreRow(model: model)
            }
            .listStyle(.plain)
            .themedBackground()
        }
    }

    /// The order, then the filters in one Filter menu (a section each), as
    /// Sort · Group · Filter over your lists and the web app's row: one line,
    /// never cut off at the edge. None when the results don't differ.
    @ViewBuilder private var choicesRow: some View {
        let menus = WebChoices.row(category, model.results.map(\.choiceItem), choices)
        let order = menus.first { $0.key == "order" }
        let filters = menus.filter { $0.key != "order" }
        if !menus.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if let order {
                        let label = Self.label(order, choices[order.key])
                        Menu {
                            picker(order)
                        } label: {
                            Label(label, systemImage: Self.symbol(order.key))
                        }
                        .quietControl(active: !choices[order.key].isEmpty)
                        .help(order.name)
                        .accessibilityLabel("\(order.name): \(label)")
                    }
                    if !filters.isEmpty {
                        let on = filters.filter { !choices[$0.key].isEmpty }
                        let label = on.isEmpty ? "Filter" : on.map { Self.label($0, choices[$0.key]) }.joined(separator: " · ")
                        Menu {
                            ForEach(filters) { menu in
                                Section(menu.name) { picker(menu) }
                            }
                        } label: {
                            Label(label, systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .quietControl(active: !on.isEmpty)
                        .help("Filter")
                        .accessibilityLabel("Filter: \(label)")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .fadesOverflow()
            .endsTopBar()
        }
    }

    private func picker(_ menu: WebChoices.Menu) -> some View {
        Picker(menu.name, selection: Binding(get: { choices[menu.key] }, set: { choose(menu.key, $0) })) {
            ForEach(menu.options, id: \.value) { Text($0.label).tag($0.value) }
        }
        .pickerStyle(.inline)
    }

    /// A choice's name without its count ("Large", not "Large · 12").
    static func label(_ menu: WebChoices.Menu, _ chosen: String) -> String {
        let label = menu.options.first { $0.value == chosen }?.label ?? menu.name
        return label.replacing(/\s·\s\d+$/, with: "")
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case "order": "arrow.up.arrow.down"
        case "size": "arrow.up.left.and.arrow.down.right"
        case "shape": "aspectratio"
        case "format": "photo"
        case "length": "clock"
        default: "globe"
        }
    }
}

/// The next page's spinner, or Try Again when it didn't come (never by itself: each web search counts).
private struct MoreRow: View {
    let model: WebResultsModel
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowBackground(palette.background)
        } else if model.moreFailed {
            ListFailureRow(text: "More didn't load.") {
                Task { await model.retryMore(searx: app.searx, hister: app.client) }
            }
        }
    }
}

/// Images as a grid of their thumbnails (from SearXNG's image proxy only);
/// a tap shows the picture large (`WebImageViewer`).
private struct ImageGrid: View {
    let model: WebResultsModel
    let results: [WebResult]
    @Binding var viewing: Int?
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 112
    @Environment(\.macTextScale) private var macScale

    var body: some View {
        ScrollView {
            EngineHealthRow(names: model.unanswered)
                .padding(.horizontal)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tile * macScale), spacing: 8)], spacing: 8) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        viewing = index
                    } label: {
                        // A square cell with the picture filling it, clipped to it: sized by the
                        // picture itself, a tall one ran up over the pills and the choices.
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { ProxiedImage(url: result.thumbnail ?? result.image, points: tile * macScale * 2) }
                            .clipShape(.rect(cornerRadius: 8))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(result.title)
                    .accessibilityHint("Shows the picture")
                    .task { await model.loadMoreIfNeeded(after: result, searx: app.searx, hister: app.client) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            if model.isLoadingMore {
                ProgressView().padding()
            } else if model.moreFailed {
                Button("More didn't load. Try Again") {
                    Task { await model.retryMore(searx: app.searx, hister: app.client) }
                }
                .padding()
            }
        }
        .themedBackground()
        #if os(iOS)
        .fullScreenCover(item: viewingItem) { start in
            WebImageViewer(results: results, index: start.index)
        }
        #else
        .sheet(item: viewingItem) { start in
            WebImageViewer(results: results, index: start.index)
                .frame(minWidth: 640, minHeight: 520)
        }
        #endif
    }

    private struct Start: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private var viewingItem: Binding<Start?> {
        Binding(get: { viewing.map(Start.init) }, set: { viewing = $0?.index })
    }
}

/// One picture large, with what it is and where it's from: Open Image, Visit
/// Page, and the previous and next ones (the buttons, a swipe on iOS, ← and
/// → on the Mac).
private struct WebImageViewer: View {
    let results: [WebResult]
    @State private var index: Int
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.palette) private var palette

    init(results: [WebResult], index: Int) {
        self.results = results
        _index = State(initialValue: index)
    }

    private var result: WebResult { results[min(max(index, 0), results.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(palette.raised))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.text)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal)
            .padding(.top, 8)
            ProxiedImage(url: result.image ?? result.thumbnail, points: 1600, fit: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .id(result.id)
                .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                    guard abs(drag.translation.width) > 2 * abs(drag.translation.height) else { return }
                    step(drag.translation.width < 0 ? 1 : -1)
                })
                .accessibilityLabel(result.title)
            Divider()
            caption
                .padding()
        }
        .themedBackground()
        #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        #endif
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.title)
                .textStyle(.subheadline, weight: .semibold)
                .foregroundStyle(palette.text)
                .lineLimit(2)
            Text(facts)
                .textStyle(.footnote)
                .foregroundStyle(palette.secondaryText)
            HStack(spacing: 18) {
                if let original = result.originalImage {
                    Button("Open Image") { openURL(original) }
                }
                if let page = SafeHref.url(result.url) {
                    Button("Visit Page") { openURL(page) }
                }
                Spacer()
                stepButton("chevron.left", label: "Previous Image", by: -1)
                Text("\(index + 1) of \(results.count)")
                    .textStyle(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText)
                stepButton("chevron.right", label: "Next Image", by: 1)
            }
            .buttonStyle(.borderless)
            .textStyle(.footnote, weight: .semibold)
            .tint(palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Site · size · format, as the search page's viewer says it.
    private var facts: String {
        let size = WebChoices.imageSize(resolution: result.resolution, imgFormat: result.imageFormat).map { "\($0.w) × \($0.h)" }
        let format = result.imageFormat.replacing(/(?i)^image\//, with: "").uppercased()
        return [result.host, size ?? "", format].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func stepButton(_ symbol: String, label: String, by step: Int) -> some View {
        Button {
            self.step(step)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(palette.raised))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.text)
        .disabled(!results.indices.contains(index + step))
        .opacity(results.indices.contains(index + step) ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func step(_ by: Int) {
        guard results.indices.contains(index + by) else { return }
        index += by
    }
}

/// A picture from SearXNG's image proxy (the device never loads images from
/// the engines' own hosts), downloaded once and decoded off the main actor at
/// the size it's drawn (`Thumbnails`); the raised colour until then.
struct ProxiedImage: View {
    let url: URL?
    let points: CGFloat
    var fit = false
    @Environment(\.palette) private var palette
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                if fit { image.resizable().scaledToFit() } else { image.resizable().scaledToFill() }
            } else {
                palette.raised
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await Thumbnails.shared.image(url.absoluteString, points: points) {
                guard let (data, response) = try? await HisterClient.defaultSession.data(from: url),
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false
                else { return nil }
                return data
            }.map(Image.init(platformImage:))
        }
    }
}
