import HisterKit
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ShareModel {
    enum Phase: Equatable {
        case loading
        case ready
        case saving
        case done(Saver.Outcome)
        case unusable
    }

    private let context: NSExtensionContext?
    private(set) var input: Saver.Input?
    private(set) var phase: Phase = .loading
    var label = ""
    let labels: [String] = SharedSettings.defaults?.stringArray(forKey: SharedSettings.Key.labels) ?? []

    init(context: NSExtensionContext?) {
        self.context = context
    }

    func load() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        input = await Self.readInput(from: providers)
        phase = input == nil ? .unusable : .ready
    }

    /// The save in flight, so Cancel stops it rather than letting it finish
    /// (or queue) behind the user's back.
    private var saveTask: Task<Saver.Outcome, Never>?

    func save() async {
        guard let input else { return }
        phase = .saving
        let label = label.isEmpty ? nil : label
        let task = Task { await Saver.save(input, label: label, via: "share") }
        saveTask = task
        let outcome = await task.value
        saveTask = nil
        guard outcome != .cancelled else { return }
        phase = .done(outcome)
        if outcome == .saved || outcome == .queued {
            try? await Task.sleep(for: .seconds(1.2))
            finish()
        }
    }

    func finish() {
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        saveTask?.cancel()
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    /// Safari's preprocessing results first (the page itself), then a URL,
    /// then text that is a URL.
    nonisolated private static func readInput(from providers: [NSItemProvider]) async -> Saver.Input? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
            if let input = await loadPage(provider) { return input }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(provider, type: .url) { return Saver.Input(url: url) }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let url = await loadURL(provider, type: .plainText) { return Saver.Input(url: url) }
        }
        return nil
    }

    nonisolated private static func loadPage(_ provider: NSItemProvider) async -> Saver.Input? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) { item, _ in
                let dict = item as? NSDictionary
                let results = dict?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                guard let results, let raw = results["url"] as? String, let url = URL(string: raw) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: Saver.Input(
                        url: url, title: results["title"] as? String, html: results["html"] as? String,
                        text: results["text"] as? String))
            }
        }
    }

    nonisolated private static func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                var url: URL?
                if let u = item as? URL {
                    url = u
                } else if let s = (item as? String) ?? (item as? NSString).map(String.init) {
                    url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if let scheme = url?.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct ShareView: View {
    let model: ShareModel
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .unusable:
                    Text("There's no web page here for Hister to save.")
                default:
                    if let input = model.input {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                if let title = input.title, !title.isEmpty {
                                    Text(title)
                                        .textStyle(.headline)
                                        .foregroundStyle(palette.text)
                                        .lineLimit(2)
                                    Text(input.url.host() ?? input.url.absoluteString)
                                        .textStyle(.caption, design: .monospaced)
                                        .foregroundStyle(palette.secondaryText)
                                } else {
                                    // A bare link: its title arrives when Save downloads it.
                                    Text(input.url.absoluteString)
                                        .textStyle(.callout, design: .monospaced)
                                        .foregroundStyle(palette.text)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                    Section {
                        Picker("Label", selection: $model.label) {
                            Text("None").tag("")
                            ForEach(model.labels, id: \.self) { Text($0).tag($0) }
                        }
                        .disabled(model.phase != .ready)
                    } footer: {
                        Text("A label marks the page as kept. Without one it's saved as visited.")
                    }
                    .listRowBackground(palette.surface)
                    if case .done(let outcome) = model.phase {
                        Section {
                            Label(outcome.message, systemImage: symbol(for: outcome))
                                .foregroundStyle(palette.text)
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            .formStyle(.grouped)
            .themedBackground()
            .navigationTitle("Save to Shiori")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .done = model.phase {
                        Button("Done") { model.finish() }
                    } else {
                        Button("Cancel") { model.cancel() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.phase == .saving {
                        ProgressView()
                    } else if model.phase == .ready {
                        Button("Save") { Task { await model.save() } }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
    }

    private func symbol(for outcome: Saver.Outcome) -> String {
        switch outcome {
        case .saved: "checkmark.circle.fill"
        case .queued: "clock.arrow.circlepath"
        case .rejected, .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}
