import SwiftUI

/// Shiori's text size (Settings → Appearance).
///
/// On iPhone and iPad it is Dynamic Type: System follows the system
/// setting, and any other choice overrides it for Shiori alone. macOS has
/// no Dynamic Type: `.dynamicTypeSize` changes nothing there (every size
/// rendered alike, macOS 27). So on the Mac the same choice
/// scales macOS's own text-style sizes, through `textStyle(_:)` below.
enum TextSize: String, CaseIterable, Identifiable {
    case system, xSmall, small, medium, large, xLarge, xxLarge, xxxLarge

    static let storageKey = "textSize"

    var id: Self { self }

    /// The choices on this platform. On the Mac, System is macOS's
    /// standard size, which Large would repeat.
    static var choices: [TextSize] {
        #if os(macOS)
        allCases.filter { $0 != .large }
        #else
        allCases
        #endif
    }

    var label: String {
        switch self {
        case .system:
            #if os(macOS)
            "Standard"
            #else
            "System"
            #endif
        case .xSmall: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .xLarge: "Extra Large"
        case .xxLarge: "Extra Extra Large"
        case .xxxLarge: "Largest"
        }
    }

    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .xSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        }
    }

    /// Relative to the standard size (Large), roughly as Dynamic Type
    /// steps body text.
    var scale: CGFloat {
        dynamicTypeSize.map(Self.scale(for:)) ?? 1
    }

    static func scale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 14 / 17
        case .small: 15 / 17
        case .medium: 16 / 17
        case .large: 1
        case .xLarge: 19 / 17
        case .xxLarge: 21 / 17
        case .xxxLarge: 23 / 17
        case .accessibility1: 28 / 17
        case .accessibility2: 33 / 17
        case .accessibility3: 40 / 17
        case .accessibility4: 47 / 17
        case .accessibility5: 53 / 17
        @unknown default: 1
        }
    }

    static func resolve(_ raw: String?) -> TextSize {
        let size = raw.flatMap(TextSize.init(rawValue:)) ?? .system
        return choices.contains(size) ? size : .system
    }
}

extension EnvironmentValues {
    /// The Mac's text scale from Settings → Text Size (1 everywhere else,
    /// where Dynamic Type does the work).
    @Entry var macTextScale: CGFloat = 1
}

extension TextSize {
    /// macOS's text styles (body 13 points) read small for a reading app,
    /// so Shiori's Standard on the Mac is this much larger; every size
    /// scales from it. Safari's results page uses the same base.
    static let macBase: CGFloat = 1.2
}

/// Applies the text size at the root.
struct TextSizeRoot: ViewModifier {
    let size: TextSize

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .environment(\.macTextScale, size.scale * TextSize.macBase)
            .font(.system(size: TextStyleFont.macSize(.body) * size.scale * TextSize.macBase))
        #else
        // A range either way, so changing the setting keeps the view tree
        // (and where the user was in it).
        content.dynamicTypeSize(size.dynamicTypeSize.map { $0...$0 } ?? .xSmall ... .accessibility5)
        #endif
    }
}

extension View {
    /// A text style that follows Settings → Text Size on the Mac too. Use
    /// it in place of `.font(.headline)` and the like.
    func textStyle(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> some View {
        modifier(TextStyleFont(style: style, design: design, weight: weight))
    }
}

struct TextStyleFont: ViewModifier {
    let style: Font.TextStyle
    var design: Font.Design?
    var weight: Font.Weight?
    @Environment(\.macTextScale) private var scale

    func body(content: Content) -> some View {
        #if os(macOS)
        content.font(
            .system(size: Self.macSize(style) * scale, weight: weight ?? Self.macWeight(style), design: design)
        )
        #else
        content.font(.system(style, design: design, weight: weight))
        #endif
    }

    /// macOS's text-style sizes (HIG, Typography: macOS built-in styles).
    static func macSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .extraLargeTitle2: 28
        case .extraLargeTitle: 36
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }

    static func macWeight(_ style: Font.TextStyle) -> Font.Weight {
        switch style {
        case .headline: .bold
        case .caption2: .medium
        default: .regular
        }
    }
}
