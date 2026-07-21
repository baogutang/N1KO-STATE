import SwiftUI
import AppKit

/// Calm Telemetry design system for N1KO-STATE.
/// Values are deliberately small in number so every surface shares one visual
/// language instead of inventing local card, type, spacing, and motion rules.
enum Theme {

    // MARK: - Accent

    static var accent: Color = Color(hex: 0x5E5CE6)

    // MARK: - Appearance

    static func applyAppearance(_ mode: String) {
        let app = NSApplication.shared
        switch mode {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark":  app.appearance = NSAppearance(named: .darkAqua)
        default:      app.appearance = nil
        }
    }

    private static var isDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var differentiateWithoutColor: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
    }

    // MARK: - Surfaces (adaptive)

    static var surface: Color {
        isDark ? Color(hex: 0x16161A) : Color(nsColor: .windowBackgroundColor)
    }
    static var card: Color {
        isDark ? Color(hex: 0x1E1E24) : Color(nsColor: .controlBackgroundColor)
    }
    static var stroke: Color {
        if increaseContrast {
            return isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.30)
        }
        return isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }
    static var track: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    static var popoverSurface: Color {
        isDark ? Color(hex: 0x101218) : Color(nsColor: .windowBackgroundColor)
    }
    static var popoverHeader: Color {
        isDark ? Color(hex: 0x171A22) : Color(nsColor: .controlBackgroundColor)
    }
    static var popoverCard: Color {
        isDark ? Color(hex: 0x1D2029) : Color(nsColor: .controlBackgroundColor)
    }

    // MARK: - Materials (Liquid Glass on Tahoe, fallback on older macOS)

    static var surfaceMaterial: Material { .ultraThinMaterial }
    static var cardMaterial: Material { .thinMaterial }

    // MARK: - Text (adaptive)

    static var textPrimary: Color {
        isDark ? Color.white.opacity(0.95) : Color(nsColor: .labelColor)
    }
    static var textSecondary: Color {
        isDark ? Color.white.opacity(increaseContrast ? 0.82 : 0.64) : Color(nsColor: .secondaryLabelColor)
    }
    static var textTertiary: Color {
        isDark ? Color.white.opacity(increaseContrast ? 0.72 : 0.50) : Color(nsColor: .tertiaryLabelColor)
    }

    // MARK: - Semantic

    static let ok = Color(hex: 0x32D74B)
    static let info = Color(hex: 0x0A84FF)
    static let warn = Color(hex: 0xFF9F0A)
    static let danger = Color(hex: 0xFF453A)

    // MARK: - Module Accents

    static var cpu: Color { accent }
    static let gpu = Color(hex: 0x8B7EC8)
    static let memory = Color(hex: 0x6D77B8)
    static let disk = Color(hex: 0x5B8FA8)
    static let network = Color(hex: 0x4C86A8)

    static func semantic(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return info
        case ..<0.8: return warn
        default: return danger
        }
    }

    static func chartGradient(_ base: Color) -> LinearGradient {
        LinearGradient(
            colors: [base.opacity(0.55), base.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func lineGradient(_ base: Color) -> LinearGradient {
        LinearGradient(
            colors: [base, base.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Metrics

    static let cardRadius: CGFloat = Radius.surface
    static let settingsCardRadius: CGFloat = Radius.surface
    static let padding: CGFloat = Spacing.l
    static let cardPadding: CGFloat = Spacing.m
    static let popoverWidth: CGFloat = 360
    static let gaugeGridSpacing: CGFloat = 10
    static let gaugeTileRadius: CGFloat = 12
    static let gaugeRingSize: CGFloat = 100
    static let gaugeRingLineWidth: CGFloat = 5
    static let gaugeRingInnerInset: CGFloat = 18
    static let gaugeTileHeight: CGFloat = 158

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 8
        static let surface: CGFloat = 12
    }

    enum HitTarget {
        static let icon: CGFloat = 28
    }

    enum Motion {
        static let feedback: Double = 0.11
        static let disclosure: Double = 0.20
        static let reduced: Double = 0.08

        static func disclosureAnimation(reduceMotion: Bool) -> Animation {
            reduceMotion
                ? .easeOut(duration: reduced)
                : .easeInOut(duration: disclosure)
        }

        static func feedbackAnimation(reduceMotion: Bool) -> Animation {
            .easeOut(duration: reduceMotion ? reduced : feedback)
        }
    }

    enum TypeScale {
        static let title = Font.system(size: 17, weight: .semibold)
        static let section = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let secondary = Font.system(size: 11.5, weight: .regular)
        static let caption = Font.system(size: 10, weight: .medium)
        static let metric = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
        static let metricLarge = Font.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()

        static let minimumContentPointSize: CGFloat = 10
        static let standardBodyPointSize: CGFloat = 13
    }
}

/// Press feedback is opacity-only: no scale/offset animation, so it remains
/// calm and automatically satisfies Reduce Motion.
struct N1KOButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .animation(Theme.Motion.feedbackAnimation(reduceMotion: Theme.reduceMotion),
                       value: configuration.isPressed)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    func toHexInt() -> UInt32? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = UInt32((srgb.redComponent * 255).rounded())
        let g = UInt32((srgb.greenComponent * 255).rounded())
        let b = UInt32((srgb.blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}

extension Font {
    static func metric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
