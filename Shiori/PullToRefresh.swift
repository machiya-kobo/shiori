import SwiftUI

/// Pull to refresh that you can see and feel, as the web app's and the
/// rooms' (`S.PULL`): past 70 points a tap of haptics says it will reload,
/// letting go reloads, and a mark under the bars grows with the pull and
/// spins while it works (at least half a second, so it's seen).
///
/// Not the system's `.refreshable`: with Shiori's bars under the navigation
/// bar (`topBar`'s safe-area bars), iOS drew its spinner where it couldn't
/// be seen, and its haptic came only after a long pull. iOS only: the Mac
/// has no pull (a trackpad's bounce isn't one).
struct PullToRefresh: ViewModifier {
    let action: () async -> Void

    @Environment(\.palette) private var palette
    @State private var pull: CGFloat = 0
    @State private var armed = false
    @State private var refreshing = false
    @State private var dragging = false

    /// How far to pull before letting go reloads (the web app's threshold).
    static let threshold: CGFloat = 70

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, new in
                pull = new
                guard dragging, !refreshing else { return }
                // Past the threshold arms it; pulled back well short disarms it.
                if !armed, new >= Self.threshold { armed = true }
                if armed, new < Self.threshold * 0.6 { armed = false }
            }
            .onScrollPhaseChange { _, phase in
                let wasDragging = dragging
                dragging = phase == .interacting
                // Let go while armed: reload.
                if wasDragging, !dragging, armed, !refreshing { start() }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, now in now }
            .overlay(alignment: .top) { mark }
        #else
        content
        #endif
    }

    private func start() {
        armed = false
        refreshing = true
        Task {
            let began = ContinuousClock.now
            await action()
            // Seen, however fast the server answers.
            let shown = ContinuousClock.now - began
            if shown < .milliseconds(500) { try? await Task.sleep(for: .milliseconds(500) - shown) }
            withAnimation(.easeOut(duration: 0.2)) { refreshing = false }
        }
    }

    /// The arrow growing with the pull (turned and in the accent once
    /// letting go reloads), then a spinner while it reloads.
    @ViewBuilder private var mark: some View {
        let progress = min(pull / Self.threshold, 1)
        if refreshing || progress > 0.1 {
            ZStack {
                if refreshing {
                    ProgressView().controlSize(.small).tint(palette.accent)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(armed ? palette.accent : palette.secondaryText)
                        .rotationEffect(.degrees(armed ? 180 : 0))
                }
            }
            .frame(width: 32, height: 32)
            .background(palette.raised, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            .scaleEffect(refreshing ? 1 : 0.6 + 0.4 * progress)
            .opacity(refreshing ? 1 : progress)
            .padding(.top, 10)
            .animation(.snappy(duration: 0.2), value: armed)
            .accessibilityLabel(refreshing ? "Refreshing" : "Pull to refresh")
            .transition(.opacity)
        }
    }
}

extension View {
    /// Shiori's pull to refresh (`PullToRefresh`) on iOS; nothing on the Mac.
    func pullToRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(PullToRefresh(action: action))
    }
}
