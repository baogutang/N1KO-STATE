import SwiftUI
import AppKit

/// Centralized design system for N1KO-STATE.
/// Supports light / dark / system appearance with Liquid Glass materials on macOS Tahoe.
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

    // MARK: - Surfaces (adaptive)

    static var surface: Color {
        isDark ? Color(hex: 0x16161A) : Color(nsColor: .windowBackgroundColor)
    }
    static var card: Color {
        isDark ? Color(hex: 0x1E1E24) : Color(nsColor: .controlBackgroundColor)
    }
    static var stroke: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
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
        isDark ? Color.white.opacity(0.55) : Color(nsColor: .secondaryLabelColor)
    }
    static var textTertiary: Color {
        isDark ? Color.white.opacity(0.45) : Color(nsColor: .tertiaryLabelColor)
    }

    // MARK: - Semantic

    static let ok = Color(hex: 0x32D74B)
    static let info = Color(hex: 0x0A84FF)
    static let warn = Color(hex: 0xFF9F0A)
    static let danger = Color(hex: 0xFF453A)

    // MARK: - Module Accents

    static let cpu = info
    static let gpu = Color(hex: 0xFF6482)
    static let memory = Color(hex: 0xBF5AF2)
    static let disk = Color(hex: 0x5E5CE6)
    static let network = info

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

    static let cardRadius: CGFloat = 14
    static let settingsCardRadius: CGFloat = 12
    static let padding: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let popoverWidth: CGFloat = 360
    static let gaugeGridSpacing: CGFloat = 10
    static let gaugeTileRadius: CGFloat = 12
    static let gaugeRingSize: CGFloat = 100
    static let gaugeRingLineWidth: CGFloat = 5
    static let gaugeRingInnerInset: CGFloat = 18
    static let gaugeTileHeight: CGFloat = 158
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
