import SwiftUI

/// Settings → Search → Pills: the pills over every list and search, in the
/// person's order, each shown or hidden (`PillOrder`, `AppState.pills`).
/// Shared with Safari's results page (which also has Images, Videos and
/// News), so all of them are listed. All always shows.
struct PillsSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let list = PillOrder.list(app.pills)
        let among = list.map(\.key)
        Section {
            ForEach(Array(list.enumerated()), id: \.element.key) { index, pill in
                let name = PillOrder.names[pill.key] ?? pill.key
                HStack(spacing: 12) {
                    Text(name)
                    Spacer()
                    Button("Move \(name) Up", systemImage: "arrow.up") {
                        app.pills = PillOrder.changed(app.pills, among: among, key: pill.key, by: -1)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(index == 0)
                    Button("Move \(name) Down", systemImage: "arrow.down") {
                        app.pills = PillOrder.changed(app.pills, among: among, key: pill.key, by: 1)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(index == list.count - 1)
                    Toggle("Show \(name)", isOn: Binding(
                        get: { pill.shown },
                        set: { app.pills = PillOrder.changed(app.pills, among: among, key: pill.key, shown: $0) }))
                        .labelsHidden()
                        .disabled(pill.key == "all")
                }
                .buttonStyle(.borderless)
            }
            .onMove { from, to in
                // Dragging (the Mac): the new order, each pill as shown as it was.
                var moved = list
                moved.move(fromOffsets: from, toOffset: to)
                app.pills = moved.map { $0.shown ? $0.key : "-" + $0.key }
            }
        } header: {
            Text("Pills")
        } footer: {
            Text("The pills over every list and search, in this order, here and in Safari's results. All always shows; Opened only with Show Opened, Small Web only with its tab, Files once Hister has some. Images, Videos and News are Safari's results page's.")
        }
    }
}
