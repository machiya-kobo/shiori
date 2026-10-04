import AuthenticationServices
import HisterKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Settings → Server → Sign in to Hister (docs/signing-in.md): for a Hister
/// with users. Inert until then: shown only while the sign-in helper on
/// Hister's host says Hister has users (`HisterAccount.available`), or
/// while this device is signed in. Two ways in: the name and password
/// (Hister's own login, traded with the helper for an id), or the
/// helper's sign-in page in a private browser session (its other ways in,
/// such as the tailnet's sign-in provider). Sign Out ends the session
/// everywhere, through the helper.
struct HisterSignInSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var problem: String?
    /// The server's answer about this device's session (nil: not asked yet).
    @State private var stillSignedIn: Bool?

    /// The device's name on the helper's sessions page.
    static var deviceLabel: String {
        #if os(iOS)
        "Shiori on \(UIDevice.current.model)"
        #else
        "Shiori on Mac"
        #endif
    }

    var body: some View {
        // AppState checks whether to offer it (`histerSignInOffered`): a
        // `.task` here would never run while this is empty.
        if app.histerAccount != nil || app.histerSignInOffered {
            section
                .task(id: app.serverURL) { await check() }
        }
    }

    private var section: some View {
        Section {
            if let account = app.histerAccount {
                LabeledContent("Signed In As") {
                    Text(account.username.isEmpty ? "You" : account.username)
                        .foregroundStyle(palette.secondaryText)
                }
                if stillSignedIn == false {
                    Label("Hister signed this device out. Sign out here, then sign in again.", systemImage: "exclamationmark.triangle")
                        .textStyle(.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
                HStack {
                    Button("Sign Out", role: .destructive) {
                        working = true
                        Task {
                            await app.signOutOfHister()
                            working = false
                            stillSignedIn = nil
                        }
                    }
                    .tint(palette.danger)
                    .disabled(working)
                    if working { ProgressView().controlSize(.small) }
                }
            } else {
                // First: Hister's own sign-in page in a Safari sheet, where
                // Safari's AutoFill (Passwords, Bitwarden) offers the saved
                // login for the site. The app's own fields can't be matched
                // to the site without Associated Domains (a paid team's).
                // The tailnet's sign-in (Hister's OIDC provider), when it has
                // one: one tap, no form.
                if app.histerOAuthProviders.contains("oidc") {
                    Button("Sign In with Tailscale", systemImage: "network") { signInWithBrowser(provider: "oidc") }
                        .disabled(working)
                }
                Button("Sign In with Saved Password…", systemImage: "key.fill") { signInWithBrowser() }
                    .disabled(working)
                TextField("Name", text: $username, prompt: Text("Name"))
                    .textContentType(.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Password", text: $password, prompt: Text("Password"))
                    .textContentType(.password)
                    .onSubmit(signInWithPassword)
                HStack {
                    Button("Sign In", action: signInWithPassword)
                        .disabled(working || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    if working { ProgressView().controlSize(.small) }
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .textStyle(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        } header: {
            Text("Sign in to Hister")
        } footer: {
            Text("Your Hister has users: sign in once on this device. The session stays in this device's Keychain and goes only to your Hister (and the rooms get an id for it, never the session). Sign In with Tailscale signs in through your tailnet; Sign In with Saved Password opens Hister's sign-in page privately, where your saved password is offered; or type your name and password below. Sign Out ends the session everywhere; Hister's sessions page lists every device.")
        }
        .buttonStyle(.borderless)
    }

    /// Whether to offer sign-in again, and whether this device's session still holds.
    private func check() async {
        await app.checkHisterSignIn()
        guard let server = app.client?.baseURL else { return }
        if let account = app.histerAccount {
            stillSignedIn = (try? await HisterAccount.username(server: server, hister: account.session)).map { $0 != nil }
        }
    }

    private func signInWithPassword() {
        guard !working, let server = app.client?.baseURL, !password.isEmpty else { return }
        working = true
        problem = nil
        let name = username.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let signedIn = try await HisterAccount.signIn(
                    server: server, username: name, password: password, label: Self.deviceLabel)
                problem = app.keepHisterSignIn(signedIn)
                if problem == nil {
                    password = ""
                    stillSignedIn = true
                }
            } catch {
                problem = (error as? HisterAccount.SignInError ?? .unavailable).message
            }
            password = ""
            working = false
        }
    }

    private func signInWithBrowser(provider: String? = nil) {
        guard !working, let server = app.client?.baseURL else { return }
        working = true
        problem = nil
        Task {
            defer { working = false }
            let callback: URL
            do {
                // A private browser session: the app's Hister session is its
                // own, never Safari's.
                callback = try await webAuthenticationSession.authenticate(
                    using: HisterAccount.browserSignInURL(server: server, provider: provider),
                    callbackURLScheme: HisterAccount.callbackScheme,
                    preferredBrowserSession: .ephemeral)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                problem = HisterAccount.SignInError.unavailable.message
                return
            }
            do {
                let signedIn = try await HisterAccount.finishBrowserSignIn(server: server, callback: callback)
                problem = app.keepHisterSignIn(signedIn)
                if problem == nil { stillSignedIn = true }
            } catch {
                problem = (error as? HisterAccount.SignInError ?? .unavailable).message
            }
        }
    }
}
