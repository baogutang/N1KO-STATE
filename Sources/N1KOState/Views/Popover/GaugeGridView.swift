import SwiftUI

/// Compact dashboard layout with richer at-a-glance detail than standalone rings.
struct GaugeGridView: View {
    @ObservedObject var hub: MonitorHub
    @ObservedObject var settings = AppSettings.shared

    private static let tileHeight: CGFloat = 124
    private let columns = [
        GridItem(.flexible(minimum: 138), spacing: 10),
        GridItem(.flexible(minimum: 138), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSummary(hub: hub)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(visibleModules) { module in
                    tile(for: module)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var visibleModules: [Module] {
        settings.orderedModules.filter { module in
            settings.isVisible(module) && (module != .battery || hub.battery.isPresent)
        }
    }

    @ViewBuilder
    private func tile(for module: Module) -> some View {
        Group {
            switch module {
            case .cpu: cpuTile
            case .gpu: gpuTile
            case .memory: memoryTile
            case .battery: batteryTile
            case .disk: diskTile
            case .network: networkTile
            case .sensors: sensorTile
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cpuTile: some View {
        DashboardGaugeTile(
            height: Self.tileHeight,
            icon: "cpu",
            title: "CPU",
            fraction: hub.cpu.totalUsage,
            value: Formatters.percent(hub.cpu.totalUsage),
            color: Theme.semantic(for: hub.cpu.totalUsage),
            details: [
                .init(label: "Load", value: String(format: "%.2f", hub.cpu.loadAverage.one)),
                .init(label: "Cores", value: hub.cpu.cores.isEmpty ? "—" : "\(hub.cpu.cores.count)"),
                .init(label: "Uptime", value: Formatters.uptime(hub.cpu.uptime))
            ]
        )
    }

    private var gpuTile: some View {
        let vramText: String
        if hub.gpu.vramTotal > 0 {
            vramText = "\(Formatters.bytes(hub.gpu.vramUsed)) / \(Formatters.bytes(hub.gpu.vramTotal))"
        } else {
            vramText = "—"
        }
        return DashboardGaugeTile(
            height: Self.tileHeight,
            icon: "sparkles",
            title: "GPU",
            fraction: hub.gpu.utilization,
            value: Formatters.percent(hub.gpu.utilization),
            color: Theme.gpu,
            details: [
                .init(label: "VRAM", value: vramText),
                .init(label: "Chip", value: hub.gpu.isAvailable ? hub.gpu.name : "—")
            ]
        )
    }

    private var memoryTile: some View {
        let usedFraction = hub.memory.total > 0 ? hub.memory.used / hub.memory.total : 0
        return DashboardGaugeTile(
            height: Self.tileHeight,
            icon: "memorychip",
            title: "Memory",
            fraction: usedFraction,
            value: Formatters.percent(usedFraction),
            color: memoryColor,
            details: [
                .init(label: "Used", value: Formatters.bytes(hub.memory.used)),
                .init(label: "Free", value: Formatters.bytes(hub.memory.free)),
                .init(label: "Pressure", value: hub.memory.pressureLevel.rawValue.loc)
            ]
        )
    }

    private var diskTile: some View {
        let volume = primaryVolume
        let used = volume?.fraction ?? 0
        return DashboardGaugeTile(
            height: Self.tileHeight,
            icon: "internaldrive",
            title: "Disk",
            fraction: used,
            value: Formatters.percent(used),
            color: Theme.semantic(for: used),
            details: [
                .init(label: "Free", value: volume.map { Formatters.bytes($0.free) } ?? "—"),
                .init(label: "Read", value: Formatters.rateCompact(hub.disk.readRate)),
                .init(label: "Write", value: Formatters.rateCompact(hub.disk.writeRate))
            ]
        )
    }

    private var batteryTile: some View {
        DashboardGaugeTile(
            height: Self.tileHeight,
            icon: hub.battery.isCharging ? "battery.100.bolt" : "battery.75",
            title: "Battery",
            fraction: hub.battery.percentage,
            value: Formatters.percent(hub.battery.percentage),
            color: batteryColor,
            details: [
                .init(label: "State", value: batteryState.loc),
                .init(label: "Health", value: hub.battery.healthFraction.map { Formatters.percent($0) } ?? "—"),
                .init(label: "Cycles", value: hub.battery.cycleCount.map { "\($0)" } ?? "—")
            ]
        )
    }

    private var networkTile: some View {
        NetworkDashboardTile(network: hub.network, height: Self.tileHeight)
    }

    private var sensorTile: some View {
        let peak = hub.sensors.peakCelsius
        let fanValue = hub.fans.fans.isEmpty
            ? "—"
            : "\(hub.fans.fans.count)"
        let rpmValue = hub.fans.fans.first.map { "\($0.rpm) RPM" } ?? "—"
        return DashboardGaugeTile(
            height: Self.tileHeight,
            icon: "thermometer",
            title: "Sensors",
            fraction: peak.map { min($0 / 110, 1) } ?? 0,
            value: peak.map { Formatters.temperature($0) } ?? "—",
            color: Theme.semantic(for: min((peak ?? 0) / 100, 1)),
            details: [
                .init(label: "Peak", value: peak.map { Formatters.temperature($0) } ?? "—"),
                .init(label: "Fans", value: fanValue),
                .init(label: "RPM", value: rpmValue)
            ]
        )
        .opacity(hub.sensors.isAvailable || hub.fans.isAvailable ? 1 : 0.58)
    }

    private var primaryVolume: VolumeInfo? {
        hub.disk.volumes.first { $0.id == "/" } ?? hub.disk.volumes.first
    }

    private var memoryColor: Color {
        switch hub.memory.pressureLevel {
        case .low: return Theme.ok
        case .medium: return Theme.warn
        case .high: return Theme.danger
        }
    }

    private var batteryColor: Color {
        if hub.battery.isCharging { return Theme.ok }
        switch hub.battery.percentage {
        case ..<0.20: return Theme.danger
        case ..<0.40: return Theme.warn
        default: return Theme.ok
        }
    }

    private var batteryState: String {
        if hub.battery.isCharged && hub.battery.onACPower { return "Fully charged" }
        if hub.battery.isCharging { return "Charging" }
        if hub.battery.onACPower { return "On AC power" }
        return "On battery"
    }
}

private struct DashboardSummary: View {
    @ObservedObject var hub: MonitorHub

    var body: some View {
        HStack(spacing: 8) {
            SummaryBadge(icon: "cpu",
                         title: "CPU",
                         value: Formatters.percent(hub.cpu.totalUsage),
                         color: Theme.semantic(for: hub.cpu.totalUsage))
            SummaryBadge(icon: "memorychip",
                         title: "Memory",
                         value: Formatters.percent(memoryFraction),
                         color: memoryColor)
            SummaryBadge(icon: "arrow.down",
                         title: "Download",
                         value: Formatters.rateCompact(hub.network.downloadRate),
                         color: Theme.info)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private var memoryFraction: Double {
        hub.memory.total > 0 ? hub.memory.used / hub.memory.total : 0
    }

    private var memoryColor: Color {
        switch hub.memory.pressureLevel {
        case .low: return Theme.ok
        case .medium: return Theme.warn
        case .high: return Theme.danger
        }
    }
}

private struct SummaryBadge: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.16))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(loc: title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                Text(value)
                    .font(.metric(11, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DashboardDetail: Identifiable {
    let label: String
    let value: String
    var placeholder = false

    var id: String { "\(label)|\(value)|\(placeholder)" }

    static let empty = DashboardDetail(label: "", value: "", placeholder: true)
}

private struct DashboardGaugeTile: View {
    let height: CGFloat
    let icon: String
    let title: String
    let fraction: Double
    let value: String
    let color: Color
    let details: [DashboardDetail]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                Text(loc: title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(value)
                    .font(.metric(11, weight: .bold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(height: 16)

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 9) {
                RingGauge(fraction: fraction,
                          color: color,
                          lineWidth: 6,
                          value: value)
                    .frame(width: 58, height: 58)

                VStack(spacing: 4) {
                    ForEach(Array(displayDetails.enumerated()), id: \.offset) { _, detail in
                        HStack(spacing: 5) {
                            Text(detail.label.loc.uppercased())
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 3)
                            Text(detail.value)
                                .font(.metric(9.5, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(height: 13)
                        .opacity(detail.placeholder ? 0 : 1)
                    }
                }
                .frame(height: 58, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 58)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private var displayDetails: [DashboardDetail] {
        var rows = Array(details.prefix(3))
        while rows.count < 3 { rows.append(.empty) }
        return rows
    }
}

private struct NetworkDashboardTile: View {
    @ObservedObject var network: NetworkMonitor
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "network")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.info)
                Text(loc: "Network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer(minLength: 0)
                Circle()
                    .fill(network.isConnected ? Theme.ok : Theme.danger)
                    .frame(width: 7, height: 7)
            }
            .frame(height: 16)

            Spacer(minLength: 7)

            VStack(spacing: 5) {
                rateRow(icon: "arrow.down", label: "Download", value: Formatters.rate(network.downloadRate), color: Theme.info)
                rateRow(icon: "arrow.up", label: "Upload", value: Formatters.rate(network.uploadRate), color: Theme.ok)
            }
            .frame(height: 39)

            Spacer(minLength: 7)

            Divider().overlay(Theme.stroke)

            Spacer(minLength: 5)

            HStack(spacing: 5) {
                Text("IP")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                Spacer(minLength: 3)
                Text(network.localIP ?? "—")
                    .font(.metric(9.5, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(height: 12)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func rateRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
                .frame(width: 17, height: 17)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(label.loc.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                Text(value)
                    .font(.metric(10.5, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
    }
}
