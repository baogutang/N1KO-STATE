import SwiftUI

struct BatteryCard: View {
    @ObservedObject var battery: BatteryMonitor
    let snapshot: MonitorDisplaySnapshot

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: symbol,
                           title: "Battery",
                           accent: color,
                           trailing: Formatters.percent(snapshot.batteryPercentage),
                           trailingColor: color)

                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                    Text(loc: statusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    Spacer(minLength: 8)
                    if let time = timeText {
                        Text(time)
                            .font(.metric(11.5))
                            .foregroundColor(Theme.textPrimary)
                    }
                }

                BatteryBar(fraction: snapshot.batteryPercentage, color: color, charging: snapshot.batteryIsCharging)
                    .frame(height: 16)

                Divider().overlay(Theme.stroke)

                HStack(alignment: .top, spacing: 10) {
                    StatPill(label: "Health", value: healthText, color: healthColor)
                    StatPill(label: "Cycles", value: battery.cycleCount.map { "\($0)" } ?? "—")
                    StatPill(label: "Temp", value: battery.temperatureC.map { Formatters.temperature($0) } ?? "—")
                    StatPill(label: "Wattage", value: powerText)
                }

                if battery.history.count > 1 {
                    MetricChart(values: battery.history,
                                maxValue: 1,
                                color: color,
                                accessibilityName: "Battery history",
                                accessibilityFormatter: Formatters.percent)
                        .frame(height: 34)
                }
            }
        }
    }

    // MARK: - Derived presentation

    private var color: Color {
        if snapshot.batteryIsCharging || snapshot.batteryOnACPower { return Theme.ok }
        switch snapshot.batteryPercentage {
        case ..<0.20: return Theme.danger
        case ..<0.40: return Theme.warn
        default: return Theme.textPrimary
        }
    }

    private var symbol: String {
        if snapshot.batteryIsCharging { return "battery.100.bolt" }
        switch snapshot.batteryPercentage {
        case ..<0.125: return "battery.0"
        case ..<0.375: return "battery.25"
        case ..<0.625: return "battery.50"
        case ..<0.875: return "battery.75"
        default: return "battery.100"
        }
    }

    private var statusIcon: String {
        if snapshot.batteryIsCharging { return "bolt.fill" }
        if snapshot.batteryOnACPower { return "powerplug.fill" }
        return "battery.50"
    }

    private var statusText: String {
        if snapshot.batteryIsCharged && snapshot.batteryOnACPower { return "Fully charged" }
        if snapshot.batteryIsCharging { return "Charging" }
        if snapshot.batteryOnACPower { return "On AC power" }
        return "On battery"
    }

    private var timeText: String? {
        if snapshot.batteryIsCharging, let m = battery.minutesToFull {
            return "%@ to full".locf(Formatters.uptime(Double(m * 60)))
        }
        if !snapshot.batteryOnACPower, let m = battery.minutesToEmpty {
            return "%@ left".locf(Formatters.uptime(Double(m * 60)))
        }
        return nil
    }

    private var healthText: String {
        battery.healthFraction.map { Formatters.percent($0) } ?? "—"
    }

    private var healthColor: Color {
        guard let ok = battery.conditionOK else { return Theme.textPrimary }
        return ok ? Theme.textPrimary : Theme.warn
    }

    private var powerText: String {
        guard let w = battery.watts else { return "—" }
        return String(format: "%.1f W", abs(w))
    }
}

/// A horizontal battery-shaped capacity bar with a charging glyph overlay.
private struct BatteryBar: View {
    let fraction: Double
    let color: Color
    let charging: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.track)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color)
                    .frame(width: max(6, g.size.width * CGFloat(min(max(fraction, 0), 1))))
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(Theme.TypeScale.caption.weight(.black))
                        .foregroundColor(.white)
                        .frame(width: g.size.width, alignment: .center)
                }
            }
        }
    }
}
