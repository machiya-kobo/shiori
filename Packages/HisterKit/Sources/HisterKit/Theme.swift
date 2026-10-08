import SwiftUI

/// The app's appearance setting (Settings → Appearance; stored as `theme`,
/// the rooms' word for it). `.system` follows the device: the theme's light
/// variant in light mode, its dark one in dark. Absent or unknown values
/// read as `.system`.
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
        case .day: "Light"
        case .night: "Dark"
        }
    }

    public static func resolve(_ raw: String?) -> AppTheme {
        raw.flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    public static let storageKey = "theme"
}

/// The app's theme (Settings → Theme, stored as `palette`): one of the
/// Machiya rooms' ten, each with a dark and a light variant. Tokyo Night is
/// the default; the rest are generated from the rooms' table
/// (Palettes.swift, by scripts/palettes.mjs). Absent or unknown keys read as
/// Tokyo Night.
public struct AppPalette: Sendable, Identifiable, Hashable {
    /// The rooms' key ("tokyo-night", "nord", …).
    public let key: String
    public let name: String
    public let dark: Palette
    public let light: Palette

    public var id: String { key }

    public static let tokyoNight = AppPalette(key: "tokyo-night", name: "Tokyo Night", dark: .night, light: .day)

    /// The ten, in the rooms' order.
    public static let all: [AppPalette] = [tokyoNight] + generated

    public static func resolve(_ raw: String?) -> AppPalette {
        all.first { $0.key == raw } ?? tokyoNight
    }

    /// The variant for the colour scheme in effect.
    public func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }

    public static let storageKey = "palette"

    public static func == (a: AppPalette, b: AppPalette) -> Bool { a.key == b.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// Colours for the content layer, one variant of an `AppPalette`. Tokyo
/// Night's are folke's: its "night" style for dark, and "day" for light. The
/// palette follows the colour scheme in effect, so `AppTheme` only has to
/// force (or not) the scheme.
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
    /// A dark variant: a tint may cover less of it (text must stay at 4.5:1
    /// or better on it).
    public let isDark: Bool
    /// How much of its colour a tinted result card takes (Result Style →
    /// Tint), and whether it lies over the surface rather than the page.
    /// Tokyo Night's dark cards are 14% over the page; the rooms' other
    /// themes are tinted as the web pages tint them (`--tint-mix` over the
    /// card), the strength their colours are held to 4.5:1 at.
    public let tintOpacity: Double
    public let tintsOverSurface: Bool

    init(hex: Hex, highlightOpacity: Double, isDark: Bool, tintOpacity: Double, tintsOverSurface: Bool) {
        self.hex = hex
        self.highlightOpacity = highlightOpacity
        self.isDark = isDark
        self.tintOpacity = tintOpacity
        self.tintsOverSurface = tintsOverSurface
    }

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
        highlightOpacity: 0.35, isDark: true, tintOpacity: 0.14, tintsOverSurface: false)

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
        highlightOpacity: 0.25, isDark: false, tintOpacity: 0.08, tintsOverSurface: true)

    /// What a tinted card lies on: the page or the surface.
    public var tintBase: Color { tintsOverSurface ? surface : background }

    /// The chip colours by name, in `hex.chips` order (Tokyo Night's blue,
    /// cyan, purple, green, orange, red, yellow, teal): the tabs use them as
    /// Safari's results page does its category pills.
    public enum Tint: Int, Sendable {
        case blue, cyan, purple, green, orange, red, yellow, teal
    }

    public func tint(_ tint: Tint) -> Color {
        hex.chips.indices.contains(tint.rawValue) ? Color(hex: hex.chips[tint.rawValue]) : accent
    }

    /// How much of its colour a hovered pill's fill takes, over `raised`.
    public static let hoverMix = 0.24

    /// A pill under the pointer: its fill (24% of its colour over `raised`)
    /// and its text, its own colour moved in lightness only until it reads
    /// at 4.5:1 on that fill. scripts/palettes.mjs makes the web's
    /// `--<pill>-hover-bg` and `--<pill>-hover` the same way (twins).
    public func pillHover(_ tint: Tint) -> (fill: Color, ink: Color) {
        let (fill, ink) = pillHoverHex(tint)
        return (Color(hex: fill), Color(hex: ink))
    }

    public func pillHoverHex(_ tint: Tint) -> (fill: UInt32, ink: UInt32) {
        let colour = hex.chips.indices.contains(tint.rawValue) ? hex.chips[tint.rawValue] : hex.accent
        let fill = Palette.mix(colour, hex.raised, Palette.hoverMix)
        return (fill, Palette.readable(colour, on: fill, lighter: isDark))
    }

    /// `tint` laid over `base` at `amount`, per channel (palettes.mjs's mix).
    public static func mix(_ tint: UInt32, _ base: UInt32, _ amount: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { out, shift in
            let t = Double((tint >> UInt32(shift)) & 0xFF), b = Double((base >> UInt32(shift)) & 0xFF)
            return out | (UInt32((t * amount + b * (1 - amount)).rounded()) << UInt32(shift))
        }
    }

    /// WCAG's contrast ratio between two colours.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ value: UInt32) -> Double {
            func linear(_ shift: UInt32) -> Double {
                let c = Double((value >> shift) & 0xFF) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
        }
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// `colour` moved in HSL lightness only (lighter on a dark theme, darker
    /// on a light one), half a percent a step, until 4.5:1 on `surface`;
    /// palettes.mjs's readableOn.
    static func readable(_ colour: UInt32, on surface: UInt32, lighter: Bool) -> UInt32 {
        if contrast(colour, surface) >= 4.5 { return colour }
        let rgb = [16, 8, 0].map { Double((colour >> UInt32($0)) & 0xFF) / 255 }
        let (h, l0, s) = toHLS(rgb[0], rgb[1], rgb[2])
        var l = l0
        while l >= 0 && l <= 1 {
            let (r, g, b) = fromHLS(h, l, s)
            let out = [r, g, b].reduce(UInt32(0)) { ($0 << 8) | UInt32(($1 * 255).rounded()) }
            if contrast(out, surface) >= 4.5 { return out }
            l += lighter ? 0.005 : -0.005
        }
        return lighter ? 0xFFFFFF : 0x000000
    }

    /// Python's colorsys.rgb_to_hls, as palettes.mjs has it.
    private static func toHLS(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), l = (maxC + minC) / 2
        if maxC == minC { return (0, l, 0) }
        let d = maxC - minC
        let s = l <= 0.5 ? d / (maxC + minC) : d / (2 - maxC - minC)
        var h: Double
        if maxC == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h = ((h / 6) + 1).truncatingRemainder(dividingBy: 1)
        return (h, l, s)
    }

    private static func fromHLS(_ h: Double, _ l: Double, _ s: Double) -> (Double, Double, Double) {
        if s == 0 { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func f(_ t0: Double) -> Double {
            let t = (t0 + 1).truncatingRemainder(dividingBy: 1)
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (f(h + 1.0 / 3), f(h), f(h - 1.0 / 3))
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
