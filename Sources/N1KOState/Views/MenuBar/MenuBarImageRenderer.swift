import AppKit

/// Renders the live menu-bar widget to an `NSImage` drawn with Core Graphics.
///
/// The bitmap is shown as the `MenuBarExtra` label via `Image(nsImage:)`. Core
/// Graphics drawing renders reliably in any launch context and lets us draw the
/// colored chips / monospaced values exactly, which a pure-SwiftUI label can't
/// match as precisely at menu-bar sizes.
enum MenuBarImageRenderer {

    struct Input: Equatable {
        var generationID: UInt64 = 0
        var cpu: Double          // 0...1
        var gpu: Double          // 0...1
        var mem: Double          // 0...1
        var battery: Double?     // 0...1, nil if no battery
        var batteryCharging: Bool
        var down: Double         // bytes/sec
        var up: Double           // bytes/sec
        var showCPU: Bool
        var showGPU: Bool
        var showMem: Bool
        var showBattery: Bool
        var showNet: Bool
        var metricOrder: [MenuBarMetric] = MenuBarMetric.allCases
        var height: CGFloat
        /// Overall rendering mode for width control and two-line readouts.
        var layout: MenuBarLayout = .standard
        /// Compact layout: drop chip backgrounds + tighten spacing so the metrics
        /// read as one aggregated readout rather than separate chips.
        var compact: Bool = false
        var fontStyle: MenuBarFontStyle = .rounded
        var colorMode: MenuBarColorMode = .colorful
        var fontSize: CGFloat = 11
    }

    private static let cpuChip = NSColor(srgbRed: 0x0A / 255, green: 0x84 / 255, blue: 1, alpha: 1)
    private static let gpuChip = NSColor(srgbRed: 1, green: 0x64 / 255, blue: 0x82 / 255, alpha: 1)
    private static let memChip = NSColor(srgbRed: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255, alpha: 1)
    private static let downCol = NSColor(srgbRed: 0x0A / 255, green: 0x84 / 255, blue: 1, alpha: 1)
    private static let upCol   = NSColor(srgbRed: 0x32 / 255, green: 0xD7 / 255, blue: 0x4B / 255, alpha: 1)

    private static let downArrow: NSImage? = {
        guard let img = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil) else { return nil }
        return img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold))
    }()
    private static let upArrow: NSImage? = {
        guard let img = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil) else { return nil }
        return img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold))
    }()

    /// Value color by load in colorful mode. Adaptive mode uses a template image
    /// so macOS supplies the correct menu-bar foreground/highlight color.
    private static func tint(_ f: Double) -> NSColor {
        switch f {
        case ..<0.6: return .labelColor
        case ..<0.8: return NSColor(srgbRed: 1, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
        default:     return NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
        }
    }

    private static func adaptiveInk(_ mode: MenuBarColorMode) -> NSColor {
        mode == .adaptive ? .black : .labelColor
    }

    private static func accent(_ color: NSColor, mode: MenuBarColorMode) -> NSColor {
        mode == .adaptive ? .black : color
    }

    private static func valueTint(_ value: Double, mode: MenuBarColorMode) -> NSColor {
        mode == .adaptive ? .black : tint(value)
    }

    // Layout constants.
    private static let sidePad: CGFloat = 6
    private static let itemGap: CGFloat = 6
    private static let chipPadX: CGFloat = 3.5
    private static let chipValueGap: CGFloat = 4
    private static func valueSlot(_ fonts: FontSet) -> CGFloat {
        max(30, ceil(("100%" as NSString).size(withAttributes: [.font: fonts.valueFont]).width) + 1)
    }
    private static func netRateSlot(_ fonts: FontSet) -> CGFloat {
        let sample = (Formatters.rateCompact(888_800_000) as NSString)
            .size(withAttributes: [.font: fonts.rateFont]).width
        return ceil(sample)
    }

    private struct FontSet {
        let tagFont: NSFont
        let valueFont: NSFont
        let stackedTagFont: NSFont
        let stackedValueFont: NSFont
        let minimalFont: NSFont
        let rateFont: NSFont
    }

    private static func makeFonts(style: MenuBarFontStyle, size rawSize: CGFloat) -> FontSet {
        let size = min(max(rawSize, CGFloat(AppSettings.menuBarFontSizeRange.lowerBound)),
                       CGFloat(AppSettings.menuBarFontSizeRange.upperBound))
        return FontSet(
            tagFont: menuFont(style: style, size: max(6.5, size - 3), weight: .black),
            valueFont: menuFont(style: style, size: size, weight: .semibold),
            stackedTagFont: menuFont(style: style, size: max(6, size - 4), weight: .bold),
            stackedValueFont: menuFont(style: style, size: max(7.5, size - 1.5), weight: .semibold),
            minimalFont: menuFont(style: style, size: max(8, size - 1), weight: .semibold),
            rateFont: menuFont(style: style, size: max(7, size - 2.5), weight: .medium)
        )
    }

    private static func menuFont(style: MenuBarFontStyle,
                                 size: CGFloat,
                                 weight: NSFont.Weight) -> NSFont {
        if style == .monospaced {
            return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch style {
        case .rounded: design = .rounded
        case .system: return base
        case .monospaced: return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func render(_ input: Input) -> NSImage {
        var segments: [(kind: Segment, width: CGFloat)] = []

        let layout = input.layout == .standard && input.compact ? MenuBarLayout.compact : input.layout
        let compact = layout == .compact
        let plainTags = compact || input.colorMode == .adaptive
        let fonts = makeFonts(style: input.fontStyle, size: input.fontSize)
        let valueSlot = valueSlot(fonts)
        let netRateSlot = netRateSlot(fonts)
        let netSlot = 12 + netRateSlot
        let gap: CGFloat
        switch layout {
        case .standard: gap = itemGap
        case .compact: gap = 5
        case .stacked, .minimal: gap = 4
        }

        func chipWidth(_ tag: String) -> CGFloat {
            let tagW = (tag as NSString).size(withAttributes: [.font: fonts.tagFont]).width
            let pad = plainTags ? 0 : chipPadX * 2
            return ceil(tagW) + pad + chipValueGap + valueSlot
        }

        func stackedWidth(tag: String) -> CGFloat {
            let tagW = (tag as NSString).size(withAttributes: [.font: fonts.stackedTagFont]).width
            let valueW = ("100%" as NSString)
                .size(withAttributes: [.font: fonts.stackedValueFont]).width
            return ceil(max(tagW, valueW)) + 4
        }

        func minimalWidth(tag: String) -> CGFloat {
            let text = "\(tag)100"
            return ceil((text as NSString).size(withAttributes: [.font: fonts.minimalFont]).width) + 2
        }

        func widthForMetric(tag: String) -> CGFloat {
            switch layout {
            case .standard, .compact: return chipWidth(tag)
            case .stacked: return stackedWidth(tag: tag)
            case .minimal: return minimalWidth(tag: String(tag.prefix(1)))
            }
        }

        for metric in input.metricOrder {
            switch metric {
            case .cpu where input.showCPU:
                segments.append((.metric("CPU", input.cpu, cpuChip), widthForMetric(tag: "CPU")))
            case .gpu where input.showGPU:
                segments.append((.metric("GPU", input.gpu, gpuChip), widthForMetric(tag: "GPU")))
            case .memory where input.showMem:
                segments.append((.metric("MEM", input.mem, memChip), widthForMetric(tag: "MEM")))
            case .battery where input.showBattery:
                if let bat = input.battery {
                    segments.append((.battery(bat, input.batteryCharging), widthForMetric(tag: "BAT")))
                }
            case .network where input.showNet:
                if !segments.isEmpty { segments.append((.divider, 1)) }
                segments.append((.network(input.down, input.up), netSlot))
            default:
                break
            }
        }
        if segments.isEmpty { segments.append((.brand, 36)) }

        let contentWidth = segments.reduce(0) { $0 + $1.width } + CGFloat(max(segments.count - 1, 0)) * gap
        let width = ceil(contentWidth + sidePad * 2)
        let height = input.height
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            var x = sidePad
            for (i, seg) in segments.enumerated() {
                switch layout {
                case .standard, .compact:
                    drawSegment(seg.kind, fonts: fonts, x: x, width: seg.width,
                                height: height, compact: plainTags,
                                valueSlot: valueSlot, netRateSlot: netRateSlot,
                                colorMode: input.colorMode)
                case .stacked:
                    drawStackedSegment(seg.kind, fonts: fonts, x: x, width: seg.width,
                                       height: height, netRateSlot: netRateSlot,
                                       colorMode: input.colorMode)
                case .minimal:
                    drawMinimalSegment(seg.kind, fonts: fonts, x: x, width: seg.width,
                                       height: height, netRateSlot: netRateSlot,
                                       colorMode: input.colorMode)
                }
                x += seg.width
                if i < segments.count - 1 { x += gap }
            }
            return true
        }
        image.isTemplate = input.colorMode == .adaptive
        image.accessibilityDescription = accessibilitySummary(input)
        return image
    }

    private static func accessibilitySummary(_ input: Input) -> String {
        var parts: [String] = []
        if input.showCPU { parts.append("CPU \(Formatters.percent(input.cpu))") }
        if input.showGPU { parts.append("GPU \(Formatters.percent(input.gpu))") }
        if input.showMem { parts.append("Memory \(Formatters.percent(input.mem))") }
        if input.showBattery, let b = input.battery {
            parts.append("Battery \(Formatters.percent(b))")
        }
        if input.showNet {
            parts.append("Download \(Formatters.rateCompact(input.down))")
            parts.append("Upload \(Formatters.rateCompact(input.up))")
        }
        return parts.isEmpty ? "N1KO-STATE" : parts.joined(separator: ", ")
    }

    private enum Segment {
        case metric(String, Double, NSColor)
        case battery(Double, Bool)
        case network(Double, Double)
        case divider
        case brand
    }

    /// Battery chip color: green while charging, otherwise red/orange/neutral by level.
    private static func batteryChip(level: Double, charging: Bool) -> NSColor {
        if charging { return NSColor(srgbRed: 0x32 / 255, green: 0xD7 / 255, blue: 0x4B / 255, alpha: 1) }
        switch level {
        case ..<0.20: return NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
        case ..<0.40: return NSColor(srgbRed: 1, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
        default:      return NSColor(srgbRed: 0x32 / 255, green: 0xD7 / 255, blue: 0x4B / 255, alpha: 1)
        }
    }

    private static func drawSegment(_ seg: Segment,
                                    fonts: FontSet,
                                    x: CGFloat,
                                    width: CGFloat,
                                    height: CGFloat,
                                    compact: Bool,
                                    valueSlot: CGFloat,
                                    netRateSlot: CGFloat,
                                    colorMode: MenuBarColorMode) {
        switch seg {
        case let .metric(tag, value, chip):
            drawMetric(tag: tag, value: value, chip: chip, fonts: fonts,
                       x: x, height: height, valueSlot: valueSlot, compact: compact,
                       colorMode: colorMode)
        case let .battery(level, charging):
            // Reuse the metric chip styling; the chip color encodes charge state
            // and the value uses the same color so a low battery reads at a glance.
            let color = batteryChip(level: level, charging: charging)
            drawMetric(tag: "BAT", value: level, chip: color,
                       fonts: fonts, x: x, height: height, valueSlot: valueSlot,
                       compact: compact, valueColor: accent(color, mode: colorMode),
                       colorMode: colorMode)
        case let .network(down, up):
            drawNetwork(down: down, up: up, fonts: fonts, x: x, width: width,
                        height: height, netRateSlot: netRateSlot, colorMode: colorMode)
        case .divider:
            let bar = NSBezierPath(rect: NSRect(x: x, y: height / 2 - 7, width: 1, height: 14))
            adaptiveInk(colorMode).withAlphaComponent(colorMode == .adaptive ? 0.55 : 0.35).setFill()
            bar.fill()
        case .brand:
            let attrs = textAttrs([
                .font: fonts.valueFont,
                .foregroundColor: adaptiveInk(colorMode)
            ])
            draw("N1KO", attrs: attrs, x: x, height: height)
        }
    }

    private static func drawStackedSegment(_ seg: Segment,
                                           fonts: FontSet,
                                           x: CGFloat,
                                           width: CGFloat,
                                           height: CGFloat,
                                           netRateSlot: CGFloat,
                                           colorMode: MenuBarColorMode) {
        switch seg {
        case let .metric(tag, value, chip):
            drawStackedMetric(tag: tag, value: value, chip: chip, fonts: fonts,
                              x: x, width: width, height: height, colorMode: colorMode)
        case let .battery(level, charging):
            let color = batteryChip(level: level, charging: charging)
            drawStackedMetric(tag: "BAT", value: level, chip: color, fonts: fonts, x: x, width: width,
                              height: height, valueColor: accent(color, mode: colorMode),
                              colorMode: colorMode)
        case let .network(down, up):
            drawNetwork(down: down, up: up, fonts: fonts, x: x, width: width,
                        height: height, netRateSlot: netRateSlot, colorMode: colorMode)
        case .divider:
            let bar = NSBezierPath(rect: NSRect(x: x, y: height / 2 - 7, width: 1, height: 14))
            adaptiveInk(colorMode).withAlphaComponent(colorMode == .adaptive ? 0.5 : 0.25).setFill()
            bar.fill()
        case .brand:
            let attrs = textAttrs([
                .font: fonts.minimalFont,
                .foregroundColor: adaptiveInk(colorMode)
            ])
            draw("N1KO", attrs: attrs, x: x, height: height)
        }
    }

    private static func drawMinimalSegment(_ seg: Segment,
                                           fonts: FontSet,
                                           x: CGFloat,
                                           width: CGFloat,
                                           height: CGFloat,
                                           netRateSlot: CGFloat,
                                           colorMode: MenuBarColorMode) {
        switch seg {
        case let .metric(tag, value, chip):
            drawMinimalMetric(tag: String(tag.prefix(1)), value: value, chip: chip,
                              fonts: fonts, x: x, width: width, height: height, colorMode: colorMode)
        case let .battery(level, charging):
            let color = batteryChip(level: level, charging: charging)
            drawMinimalMetric(tag: "B", value: level, chip: color, fonts: fonts, x: x, width: width,
                              height: height, colorMode: colorMode)
        case let .network(down, up):
            drawNetwork(down: down, up: up, fonts: fonts, x: x, width: width,
                        height: height, netRateSlot: netRateSlot, colorMode: colorMode)
        case .divider:
            let bar = NSBezierPath(rect: NSRect(x: x, y: height / 2 - 6, width: 1, height: 12))
            adaptiveInk(colorMode).withAlphaComponent(colorMode == .adaptive ? 0.45 : 0.22).setFill()
            bar.fill()
        case .brand:
            let attrs = textAttrs([
                .font: fonts.minimalFont,
                .foregroundColor: adaptiveInk(colorMode)
            ])
            draw("N1KO", attrs: attrs, x: x, height: height)
        }
    }

    private static func drawMetric(tag: String, value: Double, chip: NSColor, fonts: FontSet, x: CGFloat, height: CGFloat,
                                   valueSlot: CGFloat, compact: Bool = false, valueColor: NSColor? = nil,
                                   colorMode: MenuBarColorMode) {
        let tagSize = (tag as NSString).size(withAttributes: [.font: fonts.tagFont])
        let chipW: CGFloat
        if compact {
            // No background: the tag is drawn as small colored text instead.
            chipW = ceil(tagSize.width)
            draw(tag, attrs: textAttrs([.font: fonts.tagFont, .foregroundColor: accent(chip, mode: colorMode)]),
                 x: x, height: height)
        } else {
            // Chip background + white tag.
            let chipH = ceil(tagSize.height) + 2
            let w = ceil(tagSize.width) + chipPadX * 2
            let chipRect = NSRect(x: x, y: (height - chipH) / 2, width: w, height: chipH)
            let path = NSBezierPath(roundedRect: chipRect, xRadius: 3, yRadius: 3)
            chip.setFill()
            path.fill()
            draw(tag, attrs: [.font: fonts.tagFont, .foregroundColor: NSColor.white], centerIn: chipRect)
            chipW = w
        }

        // Value in a fixed-width, right-aligned slot.
        let valueX = x + chipW + chipValueGap
        let str = Formatters.percent(value)
        let attrs = textAttrs([.font: fonts.valueFont, .foregroundColor: valueColor ?? valueTint(value, mode: colorMode)])
        let vSize = (str as NSString).size(withAttributes: attrs)
        let vx = valueX + (valueSlot - vSize.width)   // right-align in slot
        draw(str, attrs: attrs, x: vx, height: height)
    }

    private static func drawStackedMetric(tag: String, value: Double, chip: NSColor, x: CGFloat, width: CGFloat,
                                          height: CGFloat, valueColor: NSColor? = nil) {
        let fonts = makeFonts(style: .rounded, size: 11)
        drawStackedMetric(tag: tag, value: value, chip: chip, fonts: fonts,
                          x: x, width: width, height: height, valueColor: valueColor,
                          colorMode: .colorful)
    }

    private static func drawStackedMetric(tag: String, value: Double, chip: NSColor, fonts: FontSet,
                                          x: CGFloat, width: CGFloat, height: CGFloat, valueColor: NSColor? = nil,
                                          colorMode: MenuBarColorMode) {
        let tagAttrs = textAttrs([.font: fonts.stackedTagFont, .foregroundColor: accent(chip, mode: colorMode)])
        let valueString = Formatters.percent(value)
        let valueAttrs = textAttrs([
            .font: fonts.stackedValueFont,
            .foregroundColor: valueColor ?? valueTint(value, mode: colorMode)
        ])
        drawCentered(tag, attrs: tagAttrs, x: x, width: width, yCenter: height * 0.68)
        drawCentered(valueString, attrs: valueAttrs, x: x, width: width, yCenter: height * 0.28)
    }

    private static func drawMinimalMetric(tag: String, value: Double, chip: NSColor,
                                          fonts: FontSet, x: CGFloat, width: CGFloat, height: CGFloat,
                                          colorMode: MenuBarColorMode) {
        let str = "\(tag)\(Int((value * 100).rounded()))"
        let attrs = textAttrs([.font: fonts.minimalFont, .foregroundColor: valueTint(value, mode: colorMode)])
        let tagAttrs = textAttrs([.font: fonts.minimalFont, .foregroundColor: accent(chip, mode: colorMode)])
        let tagW = (tag as NSString).size(withAttributes: tagAttrs).width
        let totalW = (str as NSString).size(withAttributes: attrs).width
        let start = x + (width - totalW) / 2
        draw(tag, attrs: tagAttrs, x: start, height: height)
        draw(String(str.dropFirst()), attrs: attrs, x: start + tagW, height: height)
    }

    private static func drawNetwork(down: Double, up: Double, fonts: FontSet,
                                    x: CGFloat, width: CGFloat, height: CGFloat, netRateSlot: CGFloat,
                                    colorMode: MenuBarColorMode) {
        let half = height / 2
        drawNetLine("arrow.down", rate: down, tint: accent(downCol, mode: colorMode), fonts: fonts,
                    x: x, width: width, yCenter: half + half / 2, netRateSlot: netRateSlot,
                    colorMode: colorMode)
        drawNetLine("arrow.up", rate: up, tint: accent(upCol, mode: colorMode), fonts: fonts,
                    x: x, width: width, yCenter: half / 2, netRateSlot: netRateSlot,
                    colorMode: colorMode)
    }

    private static func drawNetLine(_ symbol: String, rate: Double, tint: NSColor,
                                    fonts: FontSet, x: CGFloat, width: CGFloat,
                                    yCenter: CGFloat, netRateSlot: CGFloat,
                                    colorMode: MenuBarColorMode) {
        var cursor = x
        let glyph = (symbol == "arrow.down" ? downArrow : upArrow)
        if let glyph {
            let gs = glyph.size
            let tinted = tintImage(glyph, with: tint)
            tinted.draw(in: NSRect(x: cursor, y: yCenter - gs.height / 2, width: gs.width, height: gs.height))
            cursor += gs.width + 2
        }
        let str = Formatters.rateCompact(rate)
        let attrs = textAttrs([.font: fonts.rateFont, .foregroundColor: adaptiveInk(colorMode)])
        let s = (str as NSString).size(withAttributes: attrs)
        let rx = x + width - netRateSlot + (netRateSlot - s.width)
        (str as NSString).draw(at: NSPoint(x: rx, y: yCenter - s.height / 2), withAttributes: attrs)
    }

    // MARK: - Drawing helpers

    /// Central text attributes hook. Intentionally adds no shadow or glow:
    /// status-bar glyphs must stay crisp at small sizes.
    private static func textAttrs(_ base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        base
    }

    private static func draw(_ s: String, attrs: [NSAttributedString.Key: Any], x: CGFloat, height: CGFloat) {
        let size = (s as NSString).size(withAttributes: attrs)
        (s as NSString).draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attrs)
    }

    private static func draw(_ s: String, attrs: [NSAttributedString.Key: Any], centerIn rect: NSRect) {
        let size = (s as NSString).size(withAttributes: attrs)
        let p = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (s as NSString).draw(at: p, withAttributes: attrs)
    }

    private static func drawCentered(_ s: String, attrs: [NSAttributedString.Key: Any],
                                     x: CGFloat, width: CGFloat, yCenter: CGFloat) {
        let size = (s as NSString).size(withAttributes: attrs)
        let p = NSPoint(x: x + (width - size.width) / 2, y: yCenter - size.height / 2)
        (s as NSString).draw(at: p, withAttributes: attrs)
    }

    private static func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let s = image.size
        let out = NSImage(size: s, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        out.isTemplate = false
        return out
    }
}
