import HisterKit
import ShioriAI
import ShioriAIOnDevice
import SwiftUI

/// Settings → AI (docs/ai.md): the switch, the engines in
/// the order they're tried, their keys and models, and a test for each.
/// Everything here stays on this device.
struct AISettingsPage: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    /// The keys as saved, loaded when the page opens: each field shows its
    /// key masked, the eye shows it, and typing saves it.
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var localToken = ""
    @State private var loaded = false
    @State private var revealed: Set<AIKeychain.Account> = []
    @State private var appleCheck: Check = .idle
    @State private var cloudCheck: Check = .idle
    @State private var localCheck: Check = .idle

    enum Check: Equatable {
        case idle, checking
        case ok(String)
        case failed(String)
        /// The provider doesn't offer the model; the closest it does.
        case otherModels(String, [String])
    }

    var body: some View {
        @Bindable var app = app
        Section {
            Toggle("AI Features", isOn: $app.ai.enabled)
        } footer: {
            Text("Off until you turn it on. Summarize is on a page's ⋯ menu (and its ✦ button on the Mac and iPad). Shiori tries the engines below in order and says which one answered. These settings and keys stay on this device: they're never synced.")
        }
        .listRowBackground(palette.surface)

        Section {
            Toggle("Label New Pages", isOn: $app.ai.autoLabel)
            Toggle("Keep Collections Current", isOn: $app.ai.autoCollections)
            SuggestCollectionsButton()
            if app.ai.autoLabel {
                LabeledContent("Waiting for You", value: app.labeller.state.pending.count.formatted())
                LabeledContent("Applied Today", value: appliedToday.formatted())
            }
            let trust = LabelStat.trust(app.labeller.state.stats)
            if !trust.held.isEmpty {
                LabeledContent("Held for Review", value: trust.held.sorted().joined(separator: ", "))
            }
            if !trust.trustedAtMedium.isEmpty {
                LabeledContent("Trusted Sooner", value: trust.trustedAtMedium.sorted().joined(separator: ", "))
            }
            if !app.labeller.state.corrections.isEmpty || !app.labeller.state.stats.isEmpty {
                Button("Forget What It Learnt", role: .destructive) { app.labeller.forgetLearning() }
                    .tint(palette.danger)
            }
            DisclosureGroup {
                NeverSuggestedGrid()
                    .padding(.vertical, 4)
            } label: {
                Text(app.ai.neverSuggest.isEmpty ? "Never Suggested: none" : "Never Suggested: \(app.ai.neverSuggest.joined(separator: ", "))")
                    .lineLimit(2)
            }
        } header: {
            Text("Automatic Labels")
        } footer: {
            Text(autoLabelFooter)
        }
        .listRowBackground(palette.surface)
        .onChange(of: app.ai.autoLabel || app.ai.autoCollections) { _, on in
            if on { app.labeller.start(app: app) } else { app.labeller.stop() }
        }

        Section {
            Toggle("Use Apple Intelligence", isOn: $app.ai.appleIntelligence)
            let status = AppleIntelligenceEngine.status
            LabeledContent("Status", value: status.label)
            if status == .available {
                Button("Try Apple Intelligence") { Task { await tryApple() } }
                    .disabled(appleCheck == .checking)
                checkRow(appleCheck)
            }
        } header: {
            Text("1 · Apple Intelligence")
        } footer: {
            Text(AppleIntelligenceEngine.status.detail ?? "Runs on this device: nothing leaves it.")
        }
        .listRowBackground(palette.surface)

        Section {
            Toggle("Use a Local Server", isOn: $app.ai.localEnabled)
            if app.ai.localEnabled {
                TextField("Address", text: $app.ai.localURL, prompt: Text("http://server:11434/v1"))
                    .urlField()
                TextField("Model", text: $app.ai.localModel, prompt: Text("e.g. qwen3"))
                    .monospacedField()
                keyField("Token", prompt: "Optional", text: $localToken, account: .local)
                Button("Test Connection") { Task { await testLocal() } }
                    .disabled(localCheck == .checking || app.ai.localBaseURL == nil || app.ai.localModel.isEmpty)
                checkRow(localCheck) { app.ai.localModel = $0 }
            }
        } header: {
            Text("2 · Local Server")
        } footer: {
            Text("An Ollama or LM Studio server of your own, at its OpenAI-compatible address. Pages and notes go only to it.")
        }
        .listRowBackground(palette.surface)

        Section {
            Picker("Provider", selection: $app.ai.cloud) {
                ForEach(AISettings.Cloud.allCases) { Text($0.label).tag($0) }
            }
            switch app.ai.cloud {
            case .none:
                EmptyView()
            case .anthropic:
                keyField("API Key", prompt: "sk-ant-…", text: $anthropicKey, account: .anthropic)
                TextField("Model", text: $app.ai.anthropicModel, prompt: Text(AISettings.defaultAnthropicModel))
                    .monospacedField()
                cloudButtons(.anthropic)
            case .openAI:
                keyField("API Key", prompt: "sk-…", text: $openAIKey, account: .openAI)
                TextField("Model", text: $app.ai.openAIModel, prompt: Text(AISettings.defaultOpenAIModel))
                    .monospacedField()
                cloudButtons(.openAI)
            }
        } header: {
            Text("3 · AI Provider")
        } footer: {
            Text(cloudFooter)
        }
        .listRowBackground(palette.surface)

        .onAppear(perform: loadKeys)
        .onDisappear { revealed = [] }
        .onChange(of: app.ai.cloud) { _, _ in cloudCheck = .idle }
        .onChange(of: anthropicKey) { _, key in keyChanged(key, .anthropic) }
        .onChange(of: openAIKey) { _, key in keyChanged(key, .openAI) }
        .onChange(of: localToken) { _, key in keyChanged(key, .local) }
    }

    private var appliedToday: Int {
        app.labeller.state.applied.filter { Calendar.current.isDateInToday($0.at) }.count
    }

    private var autoLabelFooter: String {
        var text = "New pages without a label are labelled while Shiori is open: Anthropic's sure answers are applied, and every other page waits in Suggested Labels, with Apple Intelligence's suggestion first. Pages you've labelled are never changed; every automatic label can be undone. At most \(AutoLabeller.dailyCloudLimit) Anthropic requests a day."
        if app.ai.cloud != .anthropic {
            text += " Without Anthropic as the AI provider, every page waits for you."
        }
        text += " Turn it on on one device (the Mac is the natural home), so each page is asked about once."
        text += " Never Suggested: labels the AI never applies or suggests, here or in Edit Label (you can still use them yourself)."
        text += " Keep Collections Current puts a label in no collection into one (automatically on the same terms, otherwise asked) and proposes new collections for loose labels that share a theme, always asked. Suggest Collections does the same once, on request, and only asks. It only changes @ collections that are a plain list of labels, and every change can be undone."
        text += " It learns from you: every label you apply becomes an example, a suggestion you overrule or an automatic label you undo is remembered as a correction, a label you undo twice (a third of the time) is held for review, and one whose suggestions you've accepted five times without a miss is trusted sooner."
        return text
    }

    private var cloudFooter: String {
        switch app.ai.cloud {
        case .none:
            "None: pages stay on your devices and servers."
        case .anthropic:
            "When the engines above can't answer, page text goes to Anthropic (api.anthropic.com). Your notes never do. The key stays in this device's Keychain; any Anthropic API key works (the platform console's included)."
        case .openAI:
            "When the engines above can't answer, page text goes to OpenAI (api.openai.com). Your notes never do. The key stays in this device's Keychain."
        }
    }

    @ViewBuilder private func cloudButtons(_ account: AIKeychain.Account) -> some View {
        Button("Test Connection") { Task { await testCloud() } }
            .disabled(cloudCheck == .checking || draft(account).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        checkRow(cloudCheck) { model in
            if app.ai.cloud == .anthropic { app.ai.anthropicModel = model } else { app.ai.openAIModel = model }
            cloudCheck = .idle
        }
        if !draft(account).isEmpty {
            Button("Remove Key", role: .destructive) {
                setDraft("", account)
                cloudCheck = .idle
            }
            .tint(palette.danger)
        }
    }

    /// A key, masked unless its eye is on, the width of its row: a long
    /// key scrolls inside the field instead of running past the edge.
    private func keyField(_ title: String, prompt: String, text: Binding<String>, account: AIKeychain.Account) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Group {
                    if revealed.contains(account) {
                        TextField(title, text: text, prompt: Text(prompt))
                    } else {
                        SecureField(title, text: text, prompt: Text(prompt))
                    }
                }
                .labelsHidden()
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .autocorrectionDisabled()
                .textStyle(.callout, design: .monospaced)
                Button {
                    if revealed.contains(account) { revealed.remove(account) } else { revealed.insert(account) }
                } label: {
                    Image(systemName: revealed.contains(account) ? "eye.slash" : "eye")
                        .contentShape(.interaction, Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.secondaryText)
                .help(revealed.contains(account) ? "Hide key" : "Show key")
                .accessibilityLabel(revealed.contains(account) ? "Hide key" : "Show key")
            }
        }
    }

    /// A test's outcome; for a model the provider doesn't offer, the
    /// closest ones it does, each a tap to use.
    @ViewBuilder private func checkRow(_ check: Check, use: @escaping (String) -> Void = { _ in }) -> some View {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
        case .ok(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failed(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(palette.danger)
            }
        case .otherModels(let message, let nearest):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            ForEach(nearest, id: \.self) { model in
                Button("Use \(model)") { use(model) }
                    .textStyle(.body, design: .monospaced)
            }
        }
    }

    // MARK: Keys

    private func draft(_ account: AIKeychain.Account) -> String {
        switch account {
        case .anthropic: anthropicKey
        case .openAI: openAIKey
        case .local: localToken
        }
    }

    private func setDraft(_ value: String, _ account: AIKeychain.Account) {
        switch account {
        case .anthropic: anthropicKey = value
        case .openAI: openAIKey = value
        case .local: localToken = value
        }
    }

    private func loadKeys() {
        anthropicKey = AIKeychain.read(.anthropic)
        openAIKey = AIKeychain.read(.openAI)
        localToken = AIKeychain.read(.local)
        loaded = true
    }

    /// Saved as typed (an emptied field removes the key). Not before the
    /// page has loaded the saved ones, or loading would save them again.
    private func keyChanged(_ key: String, _ account: AIKeychain.Account) {
        guard loaded, key != AIKeychain.read(account) else { return }
        AIKeychain.save(key, for: account)
        if account == .local { localCheck = .idle } else { cloudCheck = .idle }
    }

    // MARK: Tests

    private func tryApple() async {
        appleCheck = .checking
        let start = Date()
        do {
            _ = try await AppleIntelligenceEngine().respond(to: ConnectionTest.ping)
            appleCheck = .ok("Answered in \(seconds(since: start))")
        } catch {
            appleCheck = .failed(error.localizedDescription)
        }
    }

    private func testCloud() async {
        guard let engine = app.ai.cloudEngine else { return }
        cloudCheck = .checking
        cloudCheck = await run(engine)
    }

    private func testLocal() async {
        guard let engine = app.ai.localEngine else {
            localCheck = .failed("Turn on the local server and give its address and model.")
            return
        }
        localCheck = .checking
        localCheck = await run(engine)
    }

    private func run(_ engine: some AIModelListing) async -> Check {
        do {
            switch try await ConnectionTest.run(engine) {
            case .answered(let model, let seconds):
                return .ok("Connected: \(model) answered in \(seconds.formatted(.number.precision(.fractionLength(1)))) s")
            case .modelNotOffered(let model, let nearest):
                let name = engine.provider.displayName
                return .otherModels(
                    nearest.isEmpty ? "\(name) doesn't offer \(model)." : "\(name) doesn't offer \(model). The closest it has:",
                    nearest)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func seconds(since start: Date) -> String {
        "\(Date().timeIntervalSince(start).formatted(.number.precision(.fractionLength(1)))) s"
    }
}

private extension View {
    func urlField() -> some View {
        self
            .textContentType(.URL)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .textStyle(.body, design: .monospaced)
    }

    func monospacedField() -> some View {
        self
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .textStyle(.body, design: .monospaced)
    }
}


/// Never Suggested as a grid of the labels: several to a row, each a
/// capsule that says at a glance whether it's out (red, ⊘) or in, where a
/// long list of switches left the name far from its switch.
private struct NeverSuggestedGrid: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let labels = app.rules.labels.filter { !LabelClassifier.notTopics.contains($0) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(labels, id: \.self) { label in
                let out = app.ai.neverSuggest.contains(label)
                Button {
                    if out { app.ai.neverSuggest.removeAll { $0 == label } } else { app.ai.neverSuggest.append(label) }
                    app.ai.neverSuggest.sort()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: out ? "nosign" : "circle")
                            .imageScale(.small)
                        Text(label)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(out ? palette.danger : palette.text)
                    .background(out ? palette.danger.opacity(0.15) : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(out ? palette.danger : palette.secondaryText.opacity(0.4), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityValue(out ? "Never suggested" : "Suggested")
                .accessibilityAddTraits(out ? .isSelected : [])
                .help(out ? "Let the AI use \(label)" : "Never let the AI use \(label)")
            }
        }
    }
}
