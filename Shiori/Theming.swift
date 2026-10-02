import HisterKit
import SwiftUI

extension EnvironmentValues {
    /// The Tokyo Night palette for the colour scheme in effect.
    @Entry var palette: Palette = .night
}

/// Applies the theme setting at the root: forces (or follows) the colour
/// scheme, then hands the matching palette and accent down. Colour stays
/// on the content layer; bars, tabs and sheets keep the system material
/// (Liquid Glass on 26+).
///
/// The appearance is set on the app (Mac) or its windows (iOS), not with
/// `.preferredColorScheme`: going back to nil there left the app in the
/// last forced scheme instead of following the system again.
struct ThemedRoot: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .modifier(PaletteFromScheme())
            .onChange(of: theme, initial: true) { _, theme in Self.apply(theme) }
    }

    static func apply(_ theme: AppTheme) {
        #if SHIORI_EXTENSION
        // A share sheet follows its host app's appearance.
        #elseif os(macOS)
        NSApplication.shared.appearance = switch theme {
        case .system: nil
        case .day: NSAppearance(named: .aqua)
        case .night: NSAppearance(named: .darkAqua)
        }
        #else
        let style: UIUserInterfaceStyle = switch theme {
        case .system: .unspecified
        case .day: .light
        case .night: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                window.overrideUserInterfaceStyle = style
            }
        }
        #endif
    }
}

private struct PaletteFromScheme: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = Palette.for(scheme)
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
    }
}

extension View {
    /// The palette's background behind a scrolling content view.
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}

private struct ThemedBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.background)
    }
}

/// A small capsule naming a page's topic label.
struct LabelChip: View {
    let label: String
    @Environment(\.palette) private var palette

    var body: some View {
        let colour = palette.chipColor(for: label)
        Text(label)
            .textStyle(.caption, weight: .medium)
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            // Outlined, as the search page draws its tags.
            .overlay(Capsule().strokeBorder(colour, lineWidth: 1))
            .accessibilityLabel("Label: \(label)")
    }
}
