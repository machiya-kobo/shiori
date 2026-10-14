import HisterKit
import ShioriAI
import ShioriAIOnDevice
import SwiftUI

/// Settings → AI (docs/ai.md): the switch, the engines in
/// the order they're tried, their keys and models, and a test for each,
/// then Automatic Labels (with AI on).
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
    @State private var anthropicCheck: Check = .idle
    @State private var openAICheck: Check = .idle
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
            Text("Off until you turn it on. Settings and keys stay on this device.")
        }
        .listRowBackground(palette.surface)
        .onChange(of: app.ai.autoLabel || app.ai.autoCollections) { _, on in
            if on { app.labeller.start(app: app) } else { app.labeller.stop() }
        }
        .onAppear(perform: loadKeys)
        .onDisappear { revealed = [] }
        .onChange(of: app.ai.anthropicModel) { _, _ in anthropicCheck = .idle }
        .onChange(of: app.ai.openAIModel) { _, _ in openAICheck = .idle }
        .onChange(of: anthropicKey) { _, key in keyChanged(key, .anthropic) }
        .onChange(of: openAIKey) { _, key in keyChanged(key, .openAI) }
        .onChange(of: localToken) { _, key in keyChanged(key, .local) }

        // What AI does for you, in one place.
        Section {
            LabeledContent("Summarize", value: "Always")
            LabeledContent("Suggested Labels", value: "Always")
            Toggle("AI Answer", isOn: $app.searchPage.aiAnswer)
            Toggle("Label New Pages", isOn: $app.ai.autoLabel)
            Toggle("Keep Collections Current", isOn: $app.ai.autoCollections)
        } header: {
            Text("Used For")
        } footer: {
            Text(usedForFooter)
        }
        .listRowBackground(palette.surface)

        Section {
            Toggle("Use Apple Intelligence", isOn: $app.ai.appleIntelligence)
            let status = AppleIntelligenceEngine.status
            LabeledContent("Status", value: status.label)
            if status == .available {
                Button("Test Apple Intelligence") { Task { await tryApple() } }
                    .disabled(appleCheck == .checking)
                checkRow(appleCheck)
            }
            Toggle("Use a Local Server", isOn: $app.ai.localEnabled)
            if app.ai.localEnabled {
                SettingsField(label: "Address", text: $app.ai.localURL, prompt: "https://server.example.ts.net/v1")
                UnencryptedNote(address: app.ai.localURL, carries: "your token, pages and questions")
                SettingsField(label: "Model", text: $app.ai.localModel, prompt: "e.g. qwen3", address: false, monospaced: true)
                keyField("Token", prompt: "Optional", text: $localToken, account: .local)
                Button("Test Local Server") { Task { await testLocal() } }
                    .disabled(localCheck == .checking || app.ai.localBaseURL == nil || app.ai.localModel.isEmpty)
                checkRow(localCheck) { app.ai.localModel = $0 }
            }
        } header: {
            Text("Engines, Tried in This Order")
        } footer: {
            Text("Apple Intelligence first, then your local server (an Ollama or LM Studio at its OpenAI-compatible address), then the cloud engine. " + (AppleIntelligenceEngine.status.detail ?? "Apple Intelligence runs on this device."))
        }
        .listRowBackground(palette.surface)

        Section {
            Picker("Use", selection: $app.ai.cloud) {
                ForEach(AISettings.Cloud.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Cloud Engine")
        } footer: {
            Text(cloudFooter)
        }
        .listRowBackground(palette.surface)

        providerSection(.anthropic, title: "Anthropic", keyPrompt: "sk-ant-…", model: $app.ai.anthropicModel,
                        modelPrompt: AISettings.defaultAnthropicModel)
        providerSection(.openAI, title: "OpenAI", keyPrompt: "sk-…", model: $app.ai.openAIModel,
                        modelPrompt: AISettings.defaultOpenAIModel)

        Section {
            Label("Your notes never go to a cloud engine.", systemImage: "lock")
            Label("Keys stay in this device's Keychain.", systemImage: "key")
            Label("Settings stay on this device.", systemImage: "iphone")
        } header: {
            Text("Privacy")
        } footer: {
            Text("Page text goes to a cloud engine only when the engines above can't answer.")
        }
        .listRowBackground(palette.surface)

        // Automatic Labels after the engines it runs on; only with AI on.
        if app.ai.enabled {
            Section {
                if app.ai.autoLabel, app.ai.appleIntelligence {
                    Toggle("Apply Apple Intelligence's Labels", isOn: $app.ai.applyAppleLabels)
                }
                SuggestLabelsButton()
                SuggestCollectionsButton()
                DisclosureGroup {
                    NeverSuggestedGrid()
                        .padding(.vertical, 4)
                } label: {
                    Text(app.ai.neverSuggest.isEmpty ? "Never Suggested: none" : "Never Suggested: \(app.ai.neverSuggest.joined(separator: ", "))")
                        .lineLimit(2)
                }
                LabeledContent("Requests Today", value: "\(requestsToday) of \(AutoLabeller.dailyCloudLimit)")
                // What it has done and learnt: occasional, so folded away.
                if hasLearning {
                    DisclosureGroup("Learning") {
                        learningRows
                    }
                }
            } header: {
                Text("Automatic Labels")
            } footer: {
                Text(autoLabelFooter)
            }
            .listRowBackground(palette.surface)
        }
    }

    /// One provider's block, always shown: its key, model, test and the
    /// result in place; Remove Key when a key is saved.
    @ViewBuilder private func providerSection(
        _ account: AIKeychain.Account, title: String, keyPrompt: String, model: Binding<String>, modelPrompt: String
    ) -> some View {
        Section {
            keyField("API Key", prompt: keyPrompt, text: keyBinding(account), account: account)
            SettingsField(label: "Model", text: model, prompt: modelPrompt, address: false, monospaced: true)
            testRow(account)
            removeKeyButton(account)
        } header: {
            Text(title)
        }
        .listRowBackground(palette.surface)
    }

    private func keyBinding(_ account: AIKeychain.Account) -> Binding<String> {
        switch account {
        case .anthropic: $anthropicKey
        case .openAI: $openAIKey
        case .local: $localToken
        }
    }

    /// Cloud requests made today against the day's cap (Label New Pages
    /// and Keep Collections Current; the summaries and answers on a cloud
    /// engine are not counted).
    private var requestsToday: Int {
        let today = Date().formatted(.iso8601.year().month().day())
        return app.labeller.state.cloudDay == today ? app.labeller.state.cloudCount : 0
    }

    private var usedForFooter: String {
        app.searchPage.webResults
            ? "Summarize and Suggested Labels are in a page's menu and Edit Label. AI Answer waits until opened."
            : "Summarize and Suggested Labels are in a page's menu and Edit Label. AI Answer needs Web Results (Settings → Search)."
    }

    private var trust: LabelTrust { LabelStat.trust(app.labeller.state.stats) }

    private var hasLearning: Bool {
        app.ai.autoLabel || !trust.held.isEmpty || !trust.trustedAtMedium.isEmpty
            || !app.labeller.state.corrections.isEmpty || !app.labeller.state.stats.isEmpty
    }

    /// Automatic Labels' status: what waits, what went on today, the labels
    /// held or trusted sooner, and Forget What It Learnt.
    @ViewBuilder private var learningRows: some View {
        if app.ai.autoLabel {
            LabeledContent("Waiting for You", value: app.labeller.state.pending.count.formatted())
            LabeledContent("Applied Today", value: appliedToday.formatted())
        }
        let stats = trust
        if !stats.held.isEmpty {
            LabeledContent("Held for Review", value: stats.held.sorted().joined(separator: ", "))
        }
        if !stats.trustedAtMedium.isEmpty {
            LabeledContent("Trusted Sooner", value: stats.trustedAtMedium.sorted().joined(separator: ", "))
        }
        if !app.labeller.state.corrections.isEmpty || !app.labeller.state.stats.isEmpty {
            Button("Forget What It Learnt", role: .destructive) { app.labeller.forgetLearning() }
                .tint(palette.danger)
        }
    }

    private var appliedToday: Int {
        app.labeller.state.applied.filter { Calendar.current.isDateInToday($0.at) }.count
    }

    private var autoLabelFooter: String {
        if app.ai.autoLabel, app.ai.appleIntelligence, app.ai.applyAppleLabels {
            return "New pages get Anthropic's sure answer, else Apple Intelligence's, right about 6 times in 10. "
                + "Use it on one device only; every label can be undone."
        }
        let start = if app.ai.cloud != .anthropic {
            "Without Anthropic as the AI provider, new pages' labels wait in Suggested Labels."
        } else {
            "Anthropic's sure answers label new pages; the rest wait in Suggested Labels."
        }
        // Beside Apply Apple Intelligence's Labels: how often it's right.
        if app.ai.autoLabel, app.ai.appleIntelligence {
            return start + " Apple Intelligence's labels are right about 6 times in 10; every label can be undone."
        }
        return start + " Use it on one device only; every change can be undone."
    }

    private var cloudFooter: String {
        switch app.ai.cloud {
        case .none: "None: pages stay on your devices and servers."
        case .anthropic: "Anthropic answers when the engines above can't. Fill in its key below."
        case .openAI: "OpenAI answers when the engines above can't. Fill in its key below."
        }
    }

    @ViewBuilder private func removeKeyButton(_ account: AIKeychain.Account) -> some View {
        if !draft(account).isEmpty {
            Button("Remove Key", role: .destructive) {
                setDraft("", account)
            }
            .tint(palette.danger)
        }
    }

    /// "Test Anthropic" / "Test OpenAI": the provider's saved key and model,
    /// whichever provider is in use. Off while a test runs or no key is set.
    @ViewBuilder private func testRow(_ account: AIKeychain.Account) -> some View {
        let check = account == .anthropic ? anthropicCheck : openAICheck
        Button(account == .anthropic ? "Test Anthropic" : "Test OpenAI") { Task { await testProvider(account) } }
            .disabled(check == .checking || draft(account).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        checkRow(check) { model in
            if account == .anthropic {
                app.ai.anthropicModel = model
                anthropicCheck = .idle
            } else {
                app.ai.openAIModel = model
                openAICheck = .idle
            }
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
                Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.tint(.green))
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
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(palette.tint(.orange))
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
        switch account {
        case .local: localCheck = .idle
        case .anthropic: anthropicCheck = .idle
        case .openAI: openAICheck = .idle
        }
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

    private func testProvider(_ account: AIKeychain.Account) async {
        switch account {
        case .anthropic:
            anthropicCheck = .checking
            anthropicCheck = await run(AnthropicClient(apiKey: AIKeychain.read(.anthropic), model: app.ai.anthropicModel))
        case .openAI:
            openAICheck = .checking
            openAICheck = await run(OpenAICompatibleClient(apiKey: AIKeychain.read(.openAI), model: app.ai.openAIModel))
        case .local:
            break
        }
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
            return .failed(ConnectionTest.plainWords(for: error, provider: engine.provider.displayName, model: engine.model))
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
