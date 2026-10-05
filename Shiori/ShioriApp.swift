import HisterKit
import SwiftUI

@main
struct ShioriApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

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
                #endif
                .onAppear { SearchFieldSelect.install() }
                .onOpenURL { url in
                    if url.scheme == "shiori", url.host() == "settings" { app.settingsRequests += 1 }
                    if let target = SaveLinksTarget(url: url) { app.saveLinksRequest = target }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Coming to the foreground is when the share sheet's and
                    // shortcuts' queued pages go out.
                    // A delete waiting out its Undo goes now: the app may not
                    // come back before the toast would have.
                    if phase == .background {
                        app.commitPendingDelete()
                        #if os(iOS)
                        app.labeller.stop()
                        #endif
                    }
                    if phase == .active {
                        // The settings that follow the person, at most every 30 s.
                        Task { await app.syncAccountPrefs() }
                        // Which vaults Kura shares, read again after a while away.
                        Task { await app.loadVaultsIfNeeded() }
                        app.labeller.start(app: app)
                        app.reloadSharedSettings()
                        Task {
                            await app.checkHisterSignIn()
                            await app.sendWaiting()
                            await app.reloadRules()
                        }
                    }
                }
        }
        #if os(macOS)
        .commands {
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
            }
            SearchCommands(app: app)
        }
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
                .frame(minWidth: 480, minHeight: 520)
                .environment(app)
                .modifier(ThemedRoot(theme: app.theme, palette: app.palette))
                .modifier(TextSizeRoot(size: app.effectiveTextSize))
        }
        #endif
    }
}
