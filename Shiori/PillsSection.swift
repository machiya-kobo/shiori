import HisterKit
import SwiftUI

/// Settings → Search → Pills: how the pills sit (Pill Row), and one row
/// saying how many show, which opens their editor (`PillsEditor`). Their
/// order and which show are `PillOrder`'s (`AppState.pills`), shared with
/// Safari's results page (which also has Images, Videos and News), so all of
/// them are listed. All always shows.
struct PillsSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @State private var editing = false

    var body: some View {
        @Bindable var app = app
        let list = PillOrder.list(app.pills)
        Section {
            Picker("Pill Row", selection: $app.searchPage.pillRow) {
                Text("Automatic").tag("auto")
                Text("One Row").tag("scroll")
            }
            Button {
                editing = true
            } label: {
                LabeledContent("Pills") {
                    HStack(spacing: 6) {
                        Text("\(list.filter(\.shown).count) of \(list.count) Shown")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(palette.secondaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Their order, and which show")
        } header: {
            Text("Pills")
        } footer: {
            Text("Automatic wraps them to another row when they don't fit; One Row scrolls sideways. This device's own.")
        }
        .sheet(isPresented: $editing) { PillsEditor() }
    }
}

/// The pills' order and which show: drag to reorder (each row's Move Up and
/// Move Down are there for VoiceOver), and a switch each. All always shows;
/// Opened only with Show Opened, Small Web only with Small Web on.
struct PillsEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let list = PillOrder.list(app.pills)
        let among = list.map(\.key)
        NavigationStack {
            List {
                Section {
                    ForEach(Array(list.enumerated()), id: \.element.key) { index, pill in
                        let name = PillOrder.names[pill.key] ?? pill.key
                        Toggle(name, isOn: Binding(
                            get: { pill.shown },
                            set: { app.pills = PillOrder.changed(app.pills, among: among, key: pill.key, shown: $0) }))
                            .disabled(pill.key == "all")
                            .accessibilityAction(named: "Move \(name) Up") {
                                if index > 0 { app.pills = PillOrder.changed(app.pills, among: among, key: pill.key, by: -1) }
                            }
                            .accessibilityAction(named: "Move \(name) Down") {
                                if index < list.count - 1 { app.pills = PillOrder.changed(app.pills, among: among, key: pill.key, by: 1) }
                            }
                            .listRowBackground(palette.surface)
                    }
                    .onMove { from, to in
                        // The new order, each pill as shown as it was.
                        var moved = list
                        moved.move(fromOffsets: from, toOffset: to)
                        app.pills = moved.map { $0.shown ? $0.key : "-" + $0.key }
                    }
                } footer: {
                    Text("Drag to reorder. All always shows; Opened only with Show Opened, Small Web only with Small Web on.")
                }
            }
            .themedBackground()
            #if os(iOS)
            // Drag handles from the start: reordering is what this page is for.
            .environment(\.editMode, .constant(.active))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Pills")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 520)
        #endif
        .presentationDetents([.large])
    }
}
