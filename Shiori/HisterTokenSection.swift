import HisterKit
import SwiftUI

/// Settings → Server → Access Token: Hister's token for this device, when
/// the server has users. Hister keeps one token per user (making a new one
/// breaks every device at once), so it's pasted from where it's kept, not
/// made here. The Keychain holds it (`HisterKeychain`); every request to
/// Hister, the share extension's and Safari's extension's too, carries it
/// as `X-Access-Token`. Never shown back.
struct HisterTokenSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var entry = ""
    @State private var problem: String?

    var body: some View {
        Section {
            LabeledContent("Access Token") {
                SecureField(
                    "Access Token", text: $entry,
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
            Text("Access Token")
        } footer: {
            Text("Only when your Hister has users. Paste your Hister user's token: it stays in this device's Keychain and goes only to the server above, Safari's extension included. Remove deletes it here.")
        }
    }

    private func save() {
        guard HisterToken.clean(entry) != nil else { return }
        problem = app.setHisterToken(entry)
        if problem == nil { entry = "" }
    }
}
