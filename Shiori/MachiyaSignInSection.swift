import HisterKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Settings → Account → Sign in to Machiya: for rooms that run with
/// Machiya's identity file, which want to know who is calling. One field
/// takes a pairing code from `identity pair` (paired against Kura) or a
/// pasted token from `identity token mint`; the token goes to the Keychain
/// (`MachiyaKeychain`) and from there only to Kura and Konbini.
struct MachiyaSignInSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var entry = ""
    @State private var device = Self.defaultDevice
    @State private var working = false
    @State private var problem: String?

    /// The device's name for the room's list (the CLI's pairing entry keeps its own label).
    static var defaultDevice: String {
        #if os(iOS)
        UIDevice.current.model
        #else
        "Mac"
        #endif
    }

    var body: some View {
        Section {
            LabeledContent("Status") {
                Text(Machiya.statusText(token: app.machiyaToken, principal: app.machiyaPrincipal))
                    .foregroundStyle(palette.secondaryText)
            }
            if app.machiyaToken.isEmpty {
                LabeledContent("Code or Token") {
                    SecureField("Code or Token", text: $entry, prompt: Text("ABCD-EFGH or mch_…"))
                        .labelsHidden()
                        .lineLimit(1)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        #endif
                        .autocorrectionDisabled()
                        .textStyle(.callout, design: .monospaced)
                        .onSubmit(signIn)
                }
                LabeledContent("This Device") {
                    TextField("This Device", text: $device, prompt: Text(Self.defaultDevice))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
                HStack {
                    Button("Sign In", action: signIn)
                        .disabled(working || Machiya.entry(entry) == nil)
                    if working { ProgressView().controlSize(.small) }
                }
            } else {
                Button("Sign Out", role: .destructive) {
                    problem = nil
                    app.signOutOfMachiya()
                }
                .tint(palette.danger)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .textStyle(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        } header: {
            Text("Sign in to Machiya")
        } footer: {
            Text("Only when your rooms use Machiya's identity file: enter a code from identity pair, or a token. It stays in this device's Keychain and goes only to your Kura and Konbini.")
        }
    }

    private func signIn() {
        guard !working, Machiya.entry(entry) != nil else { return }
        working = true
        problem = nil
        Task {
            problem = await app.signInToMachiya(entry, device: Machiya.device(device, fallback: Self.defaultDevice))
            if problem == nil { entry = "" }
            working = false
        }
    }
}
