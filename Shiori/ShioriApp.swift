import HisterKit
import SwiftUI

@main
struct ShioriApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase
    /// When the app left (the background on iOS, any other app in front on
    /// the Mac), for the foreground refresh; false until the first activation.
    @State private var awayAt: Date?
    @State private var launched = false
    /// Label New Pages was scheduled when the app left (iOS stops it).
    @State private var labellerWasOn = false

    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(macOS)
                // Room for the sidebar, the results and a usable preview.
                .frame(minWidth: 700, minHeight: 480)
                #endif
                .environment(app)
                .modifier(ThemedRoot(theme: app.theme, palette: app.palette))
                .modifier(TextSizeRoot(size: app.effectiveTextSize))
                #if os(macOS)
                .onAppear { MacAppIcon.apply() }
                // A shiori:// link goes to a window already open, rather
                // than opening another (a plain WindowGroup's default).
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                #endif
                .onOpenURL { url in
                    if url.scheme?.lowercased() == "shiori", url.host()?.lowercased() == "settings" { app.settingsRequests += 1 }
                    if let target = SaveLinksTarget(url: url) { app.saveLinksRequest = target }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // A delete waiting out its Undo goes now: the app may not
                    // come back before the toast would have.
                    if phase == .background {
                        app.deletes.commit()
                        // Labelling's state, written now rather than in a few seconds.
                        app.labeller.flush()
                        #if os(iOS)
                        labellerWasOn = app.labeller.isScheduled
                        app.labeller.stop()
                        #endif
                    }
                    if Self.leaves(phase), awayAt == nil { awayAt = .now }
                    if phase == .active { cameBack() }
                }
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .toolbar) {
                // Pull to refresh is iOS's: the Mac reloads a list here.
                Button("Reload") { app.reloadRequests += 1 }
                    .keyboardShortcut("r")
            }
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                Toggle("Show Preview Pane", isOn: Binding(
                    get: { app.searchPage.previewPane },
                    set: { app.searchPage.previewPane = $0 }))
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { app.searchFocusRequests += 1 }
                    .keyboardShortcut("f")
                // ⌘K, as the web pages and many apps: the search field.
                Button("Search") { app.searchFocusRequests += 1 }
                    .keyboardShortcut("k")
            }
            SearchCommands(app: app)
        }
        #else
        // A hardware keyboard on the iPad (and iPhone): ⌘F and ⌘K to the
        // search field, ⌘R to reload the list.
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") { app.reloadRequests += 1 }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { app.searchFocusRequests += 1 }
                    .keyboardShortcut("f")
                Button("Search") { app.searchFocusRequests += 1 }
                    .keyboardShortcut("k")
            }
        }
        #endif
        #if os(macOS)
        Settings {
            // A set width (the HIG's preferences window): a field holding a long
            // address or token scrolls inside it, where it had widened the page
            // past the window, which clipped both sides.
            SettingsView()
                .frame(width: 620)
                .frame(minHeight: 520)
                .environment(app)
                .modifier(ThemedRoot(theme: app.theme, palette: app.palette))
                .modifier(TextSizeRoot(size: app.effectiveTextSize))
        }
        #endif
    }

    /// The app left: the background on iOS (a pulled-down Control Center is
    /// only inactive), any other app in front on the Mac.
    private static func leaves(_ phase: ScenePhase) -> Bool {
        #if os(macOS)
        phase != .active
        #else
        phase == .background
        #endif
    }

    /// Back in front. Waiting pages (the share sheet's, shortcuts') go out
    /// every time; the rest (the sign-in check, the rules and files, the
    /// account's settings, Kura's vaults, Label New Pages) only on the first
    /// activation or after a minute or more away, not on every app switch.
    private func cameBack() {
        let away = awayAt.map { Date.now.timeIntervalSince($0) }
        awayAt = nil
        // This device's settings, which Safari's page may have changed (local, cheap).
        app.reloadSharedSettings()
        Task { await app.sendWaiting() }
        let first = !launched
        launched = true
        guard first || (away ?? 0) >= 60 else {
            // Back within the minute: Label New Pages carries on if the
            // background had stopped it.
            if labellerWasOn { app.labeller.start(app: app) }
            labellerWasOn = false
            return
        }
        labellerWasOn = false
        // The settings that follow the person, at most every 30 s.
        Task { await app.syncAccountPrefs() }
        // Which vaults Kura shares, read again after a while away.
        Task { await app.loadVaultsIfNeeded() }
        app.labeller.start(app: app)
        Task {
            await app.checkHisterSignIn()
            // At launch the window loads them (RootView); after a while
            // away they're asked again.
            if !first { await app.reloadRules() }
        }
    }
}
