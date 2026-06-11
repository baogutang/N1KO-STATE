import SwiftUI

/// iStat Menus 7-style compact ring gauge grid, shown as an alternative to the card layout.
struct GaugeGridView: View {
    @ObservedObject var hub: MonitorHub
    @ObservedObject var settings = AppSettings.shared

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            if settings.showCPU {
                GaugeCell(fraction: hub.cpu.totalUsage,
                          label: "CPU",
                          value: Formatters.percent(hub.cpu.totalUsage),
                          color: Theme.info)
            }
            if settings.showGPU {
                GaugeCell(fraction: hub.gpu.utilization,
                          label: "GPU",
                          value: Formatters.percent(hub.gpu.utilization),
                          color: Theme.gpu)
            }
            if settings.showMemory {
                let frac = hub.memory.total > 0 ? hub.memory.used / hub.memory.total : 0
                GaugeCell(fraction: frac,
                          label: "Memory",
                          value: Formatters.percent(frac),
                          color: Theme.memory)
            }
            if settings.showDisk {
                let vol = hub.disk.volumes.first { $0.id == "/" }
                    ?? hub.disk.volumes.max { $0.total < $1.total }
                let frac = vol?.fraction ?? 0
                GaugeCell(fraction: frac,
                          label: "Disk",
                          value: Formatters.percent(frac),
                          color: Theme.disk)
            }
            if settings.showBattery, hub.battery.isPresent {
                GaugeCell(fraction: hub.battery.percentage,
                          label: "Battery",
                          value: Formatters.percent(hub.battery.percentage),
                          color: batteryColor)
            }
            if settings.showNetwork {
                NetworkGaugeCell(down: hub.network.downloadRate,
                                 up: hub.network.uploadRate)
            }
            if settings.showSensors, hub.sensors.isAvailable, let peak = hub.sensors.peakCelsius {
                GaugeCell(fraction: min(peak / 110, 1),
                          label: "Sensors",
                          value: Formatters.temperature(peak),
                          color: Theme.semantic(for: min(peak / 100, 1)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var batteryColor: Color {
        if hub.battery.isCharging { return Theme.ok }
        switch hub.battery.percentage {
        case ..<0.20: return Theme.danger
        case ..<0.40: return Theme.warn
        default: return Theme.ok
        }
    }
}

// MARK: - Gauge Cell

private struct GaugeCell: View {
    let fraction: Double
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            RingGauge(fraction: fraction,
                      color: color,
                      lineWidth: 7,
                      value: value)
                .frame(width: 80, height: 80)
            Text(loc: label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Network Cell (text-based, no ring)

private struct NetworkGaugeCell: View {
    let down: Double
    let up: Double

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "network")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.info)

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.info)
                    Text(Formatters.rateCompact(down))
                        .font(.metric(12))
                        .foregroundColor(Theme.textPrimary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.ok)
                    Text(Formatters.rateCompact(up))
                        .font(.metric(12))
                        .foregroundColor(Theme.textPrimary)
                }
            }

            Text(loc: "Network")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}
