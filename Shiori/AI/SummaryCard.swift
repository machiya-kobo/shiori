import HisterKit
import ShioriAI
import SwiftUI

/// The summary above the preview: what it says, which engine wrote it,
/// and Copy, Regenerate and Close.
struct SummaryCard: View {
    let state: SummaryState
    let regenerate: () -> Void
    let close: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Summary", systemImage: "sparkles")
                    .textStyle(.subheadline, weight: .semibold)
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                if case .done(let summary) = state {
                    Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(summary.text) }
                        .help("Copy the summary")
                    Button("Regenerate", systemImage: "arrow.clockwise", action: regenerate)
                        .help("Summarize again")
                }
                Button("Close", systemImage: "xmark", action: close)
                    .help("Hide the summary")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            switch state {
            case .none:
                EmptyView()
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…")
                        .foregroundStyle(palette.secondaryText)
                }
            case .done(let summary):
                ScrollView {
                    Text(summary.text)
                        .textStyle(.body)
                        .foregroundStyle(palette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)
                Text(byline(summary))
                    .textStyle(.caption)
                    .foregroundStyle(palette.secondaryText)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(palette.text)
                Button("Try Again", action: regenerate)
            }
        }
        .padding(12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.background)
    }

    private func byline(_ summary: Summary) -> String {
        var text = "By \(summary.provider.displayName)"
        if summary.partial { text += " · from the first part of a long page" }
        return text
    }
}
