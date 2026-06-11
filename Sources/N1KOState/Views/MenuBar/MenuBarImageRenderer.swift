import AppKit

/// Renders the live menu-bar widget to an `NSImage` drawn with Core Graphics.
///
/// The bitmap is shown as the `MenuBarExtra` label via `Image(nsImage:)`. Core
/// Graphics drawing renders reliably in any launch context and lets us draw the
/// colored chips / monospaced values exactly, which a pure-SwiftUI label can't
/// match as precisely at menu-bar sizes.
enum MenuBarImageRenderer {

    struct Input {
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
        /// Compact layout: drop chip backgrounds + tighten spacing so the metrics
        /// read as one aggregated readout rather than separate chips.
        var compact: Bool = false
    }

    private static let cpuChip = NSColor(srgbRed: 0x0A / 255, green: 0x84 / 255, blue: 1, alpha: 1)
    private static let gpuChip = NSColor(srgbRed: 1, green: 0x64 / 255, blue: 0x82 / 255, alpha: 1)
    private static let memChip = NSColor(srgbRed: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255, alpha: 1)
    private static let downCol = NSColor(srgbRed: 0x0A / 255, green: 0x84 / 255, blue: 1, alpha: 1)
    private static let upCol   = NSColor(srgbRed: 0x32 / 255, green: 0xD7 / 255, blue: 0x4B / 255, alpha: 1)

    private static let tagFont   = NSFont.systemFont(ofSize: 8, weight: .black)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let rateFont  = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
    private static let arrowFont = NSFont.systemFont(ofSize: 7, weight: .bold)
    private static let downArrow: NSImage? = {
        guard let img = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil) else { return nil }
        return img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold))
    }()
    private static let upArrow: NSImage? = {
        guard let img = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil) else { return nil }
        return img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold))
    }()

    /// Value color by load; uses system label so it adapts to light/dark menu bars.
    private static func tint(_ f: Double) -> NSColor {
        switch f {
        case ..<0.6: return .labelColor
        case ..<0.8: return NSColor(srgbRed: 1, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
        default:     return NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
        }
    }

    // Layout constants.
    private static let sidePad: CGFloat = 6
    private static let itemGap: CGFloat = 6
    private static let chipPadX: CGFloat = 3.5
    private static let chipValueGap: CGFloat = 4
    private static let valueSlot: CGFloat = 30   // fixed slot so width is stable
    private static let netRateSlot: CGFloat = {
        let sample = (Formatters.rateCompact(888_800_000) as NSString)
            .size(withAttributes: [.font: rateFont]).width
        return ceil(sample)
    }()
    private static let netSlot: CGFloat = 12 + netRateSlot

    static func render(_ input: Input) -> NSImage {
        var segments: [(kind: Segment, width: CGFloat)] = []

        let compact = input.compact
        let gap = compact ? 5 : itemGap

        func chipWidth(_ tag: String) -> CGFloat {
            let tagW = (tag as NSString).size(withAttributes: [.font: tagFont]).width
            let pad = compact ? 0 : chipPadX * 2
            return ceil(tagW) + pad + chipValueGap + valueSlot
        }

        for metric in input.metricOrder {
            switch metric {
            case .cpu where input.showCPU:
                segments.append((.metric("CPU", input.cpu, cpuChip), chipWidth("CPU")))
            case .gpu where input.showGPU:
                segments.append((.metric("GPU", input.gpu, gpuChip), chipWidth("GPU")))
            case .memory where input.showMem:
                segments.append((.metric("MEM", input.mem, memChip), chipWidth("MEM")))
            case .battery where input.showBattery:
                if let bat = input.battery {
                    segments.append((.battery(bat, input.batteryCharging), chipWidth("BAT")))
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
                drawSegment(seg.kind, x: x, width: seg.width, height: height, compact: compact)
                x += seg.width
                if i < segments.count - 1 { x += gap }
            }
            return true
        }
        image.isTemplate = false
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

    private static func drawSegment(_ seg: Segment, x: CGFloat, width: CGFloat, height: CGFloat, compact: Bool) {
        switch seg {
        case let .metric(tag, value, chip):
            drawMetric(tag: tag, value: value, chip: chip, x: x, height: height, compact: compact)
        case let .battery(level, charging):
            // Reuse the metric chip styling; the chip color encodes charge state
            // and the value uses the same color so a low battery reads at a glance.
            drawMetric(tag: "BAT", value: level, chip: batteryChip(level: level, charging: charging),
                       x: x, height: height, compact: compact,
                       valueColor: batteryChip(level: level, charging: charging))
        case let .network(down, up):
            drawNetwork(down: down, up: up, x: x, width: width, height: height)
        case .divider:
            let bar = NSBezierPath(rect: NSRect(x: x, y: height / 2 - 7, width: 1, height: 14))
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
            bar.fill()
        case .brand:
            let attrs = legibleAttrs([
                .font: NSFont.systemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: NSColor.labelColor
            ])
            draw("N1KO", attrs: attrs, x: x, height: height)
        }
    }

    private static func drawMetric(tag: String, value: Double, chip: NSColor, x: CGFloat, height: CGFloat,
                                   compact: Bool = false, valueColor: NSColor? = nil) {
        let tagSize = (tag as NSString).size(withAttributes: [.font: tagFont])
        let chipW: CGFloat
        if compact {
            // No background: the tag is drawn as small colored text instead.
            chipW = ceil(tagSize.width)
            draw(tag, attrs: legibleAttrs([.font: tagFont, .foregroundColor: chip]), x: x, height: height)
        } else {
            // Chip background + white tag.
            let chipH = ceil(tagSize.height) + 2
            let w = ceil(tagSize.width) + chipPadX * 2
            let chipRect = NSRect(x: x, y: (height - chipH) / 2, width: w, height: chipH)
            let path = NSBezierPath(roundedRect: chipRect, xRadius: 3, yRadius: 3)
            chip.setFill()
            path.fill()
            draw(tag, attrs: [.font: tagFont, .foregroundColor: NSColor.white], centerIn: chipRect)
            chipW = w
        }

        // Value in a fixed-width, right-aligned slot.
        let valueX = x + chipW + chipValueGap
        let str = Formatters.percent(value)
        let attrs = legibleAttrs([.font: valueFont, .foregroundColor: valueColor ?? tint(value)])
        let vSize = (str as NSString).size(withAttributes: attrs)
        let vx = valueX + (valueSlot - vSize.width)   // right-align in slot
        draw(str, attrs: attrs, x: vx, height: height)
    }

    private static func drawNetwork(down: Double, up: Double, x: CGFloat, width: CGFloat, height: CGFloat) {
        let half = height / 2
        drawNetLine("arrow.down", rate: down, tint: downCol, x: x, width: width,
                    yCenter: half + half / 2)
        drawNetLine("arrow.up", rate: up, tint: upCol, x: x, width: width,
                    yCenter: half / 2)
    }

    private static func drawNetLine(_ symbol: String, rate: Double, tint: NSColor,
                                    x: CGFloat, width: CGFloat, yCenter: CGFloat) {
        var cursor = x
        let glyph = (symbol == "arrow.down" ? downArrow : upArrow)
        if let glyph {
            let gs = glyph.size
            let tinted = tintImage(glyph, with: tint)
            tinted.draw(in: NSRect(x: cursor, y: yCenter - gs.height / 2, width: gs.width, height: gs.height))
            cursor += gs.width + 2
        }
        let str = Formatters.rateCompact(rate)
        let attrs = legibleAttrs([.font: rateFont, .foregroundColor: NSColor.labelColor])
        let s = (str as NSString).size(withAttributes: attrs)
        let rx = x + width - netRateSlot + (netRateSlot - s.width)
        (str as NSString).draw(at: NSPoint(x: rx, y: yCenter - s.height / 2), withAttributes: attrs)
    }

    // MARK: - Drawing helpers

    /// Soft shadow so text stays readable on colorful translucent menu-bar wallpapers
    /// without a heavy background box.
    private static func legibleAttrs(_ base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = base
        let shadow = NSShadow()
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 2.5
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        attrs[.shadow] = shadow
        return attrs
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
