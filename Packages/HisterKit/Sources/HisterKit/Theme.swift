import SwiftUI

/// The app's theme setting (Settings → Theme). `.system` follows the
/// device: Tokyo Night Day in light mode, Tokyo Night in dark. Absent or
/// unknown values read as `.system`.
public enum AppTheme: String, CaseIterable, Sendable, Identifiable {
    case system
    case day
    case night

    public var id: String { rawValue }

    /// For `.preferredColorScheme`; nil follows the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .day: .light
        case .night: .dark
        }
    }

    public var label: String {
        switch self {
        case .system: "System"
        case .day: "Tokyo Night Day"
        case .night: "Tokyo Night"
        }
    }

    public static func resolve(_ raw: String?) -> AppTheme {
        raw.flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    public static let storageKey = "theme"
}

/// Colours from folke's Tokyo Night: its "night" style for dark, and "day"
/// for light. The palette follows the colour scheme in effect, so
/// `AppTheme` only has to force (or not) the scheme.
public struct Palette: Sendable {
    /// The raw sRGB values, shared by SwiftUI and the preview's CSS.
    public struct Hex: Sendable {
        var background: UInt32
        var surface: UInt32
        var raised: UInt32
        var text: UInt32
        var secondaryText: UInt32
        var accent: UInt32
        var highlight: UInt32
        var danger: UInt32
        var chips: [UInt32]
    }

    public let hex: Hex
    /// How opaque the highlight behind search hits is.
    let highlightOpacity: Double

    public var background: Color { Color(hex: hex.background) }
    public var surface: Color { Color(hex: hex.surface) }
    public var raised: Color { Color(hex: hex.raised) }
    public var text: Color { Color(hex: hex.text) }
    /// Every text colour here, chips included, is at least 4.5:1 on
    /// `background` (ThemeTests checks).
    /// Secondary text.
    public var secondaryText: Color { Color(hex: hex.secondaryText) }
    public var accent: Color { Color(hex: hex.accent) }
    /// Behind search hits in snippets.
    public var highlight: Color { Color(hex: hex.highlight).opacity(highlightOpacity) }
    public var danger: Color { Color(hex: hex.danger) }

    public static let night = Palette(
        hex: Hex(
            background: 0x1A1B26, surface: 0x16161E, raised: 0x292E42,
            text: 0xC0CAF5, secondaryText: 0xA9B1D6, accent: 0x7AA2F7,
            highlight: 0xE0AF68, danger: 0xF7768E,
            chips: [0x7AA2F7, 0x7DCFFF, 0xBB9AF7, 0x9ECE6A, 0xFF9E64, 0xF7768E, 0xE0AF68, 0x1ABC9C]),
        highlightOpacity: 0.35)

    public static let day = Palette(
        hex: Hex(
            // The surface (Settings rows, sheets, cards) is lighter than the
            // background, as grouped lists are on iOS: Tokyo Night Day's darker
            // bg_dark left its text under 4.5:1 there.
            background: 0xE1E2E7, surface: 0xF0F1F5, raised: 0xC4C8DA,
            // Tokyo Night Day's hues, darkened where needed to reach 4.5:1
            // as text on the background (its own accent is 3.1:1).
            text: 0x3760BF, secondaryText: 0x4C5A8F, accent: 0x155FC5,
            highlight: 0x8C6C3E, danger: 0xBD204C,
            chips: [0x155FC5, 0x006B8F, 0x802CEE, 0x506B34, 0x9A5000, 0xBD204C, 0x7A5E36, 0x0D6E5C]),
        highlightOpacity: 0.25)

    /// Tokyo Night, not Day: the most a tint may cover differs (text must
    /// stay at 4.5:1 or better on it).
    public var isDark: Bool { hex.background == Palette.night.hex.background }

    public static func `for`(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .night : .day
    }

    /// The chip colours by name, in `hex.chips` order (Tokyo Night's blue,
    /// cyan, purple, green, orange, red, yellow, teal): the tabs use them as
    /// Safari's results page does its category pills.
    public enum Tint: Int, Sendable {
        case blue, cyan, purple, green, orange, red, yellow, teal
    }

    public func tint(_ tint: Tint) -> Color {
        hex.chips.indices.contains(tint.rawValue) ? Color(hex: hex.chips[tint.rawValue]) : accent
    }

    /// A stable chip colour for a label, so `books` is always the same hue.
    public func chipColor(for label: String) -> Color {
        Color(hex: chipHex(for: label))
    }

    public func chipHex(for label: String) -> UInt32 {
        guard !hex.chips.isEmpty else { return hex.accent }
        let hash = label.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return hex.chips[Int(hash % UInt32(hex.chips.count))]
    }

    /// `#rrggbb` for CSS.
    public static func css(_ value: UInt32) -> String {
        String(format: "#%06X", value & 0xFFFFFF)
    }

    /// CSS custom properties for the preview page.
    public var cssVariables: String {
        let c = Self.css
        return """
            --bg: \(c(hex.background)); --surface: \(c(hex.surface)); --raised: \(c(hex.raised));
            --text: \(c(hex.text)); --secondary: \(c(hex.secondaryText)); --accent: \(c(hex.accent));
            --highlight: \(c(hex.highlight)); --highlight-opacity: \(highlightOpacity);
            """
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
