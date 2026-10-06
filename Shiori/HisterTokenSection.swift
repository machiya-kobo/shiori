import HisterKit
import SwiftUI

/// Settings → Account → Safari Extension Token: Hister's token for this
/// device, when the server has users. It's Safari's extension's credential:
/// an extension can't send the sign-in's session (no `Cookie` header), so
/// it asks the app for this token. The app itself carries it beside the
/// sign-in (Hister reads the session first) and leans on it only when
/// signed out. Hister keeps one token per user (making a new one breaks
/// every device at once), so it's pasted from where it's kept, not made
/// here. The Keychain holds it (`HisterKeychain`). Never shown back.
struct HisterTokenSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var entry = ""
    @State private var problem: String?

    var body: some View {
        Section {
            LabeledContent("Token") {
                SecureField(
                    "Token", text: $entry,
                    prompt: Text(app.histerToken.isEmpty ? "Not Set" : "Saved"))
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
                    .onSubmit(save)
            }
            HStack {
                Button(app.histerToken.isEmpty ? "Save Token" : "Replace Token", action: save)
                    .disabled(HisterToken.clean(entry) == nil)
                Spacer()
                if !app.histerToken.isEmpty {
                    Button("Remove", role: .destructive) {
                        entry = ""
                        problem = app.setHisterToken("")
                    }
                    .tint(palette.danger)
                }
            }
            .buttonStyle(.borderless)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .textStyle(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        } header: {
            Text("Safari Extension Token")
        } footer: {
            Text("Only when your Hister has users: Safari's extension saves pages with your Hister token, pasted here. It stays in this device's Keychain and goes only to your Hister.")
        }
    }

    private func save() {
        guard HisterToken.clean(entry) != nil else { return }
        problem = app.setHisterToken(entry)
        if problem == nil { entry = "" }
    }
}
