import SwiftUI

/// Compact dashboard layout with richer at-a-glance detail than standalone rings.
struct GaugeGridView: View {
    @ObservedObject var hub: MonitorHub
    @ObservedObject var settings = AppSettings.shared

    private let columns = [
        GridItem(.flexible(), spacing: Theme.gaugeGridSpacing),
        GridItem(.flexible(), spacing: Theme.gaugeGridSpacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.gaugeGridSpacing) {
            ForEach(visibleModules) { module in
                tile(for: module)
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, Theme.padding)
    }

    private var visibleModules: [Module] {
        settings.orderedModules.filter { module in
            settings.isVisible(module) && (module != .battery || hub.snapshot.batteryIsPresent)
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
        let snapshot = hub.snapshot
        return DashboardGaugeTile(
            icon: "cpu",
            title: "CPU",
            fraction: snapshot.cpuUsage,
            value: Formatters.percent(snapshot.cpuUsage),
            color: Theme.semantic(for: snapshot.cpuUsage),
            details: [
                .init(label: "Load", value: String(format: "%.2f", snapshot.cpuLoadAverageOne)),
                .init(label: "Cores", value: snapshot.cpuCoreCount == 0 ? "—" : "\(snapshot.cpuCoreCount)"),
                .init(label: "Uptime", value: Formatters.uptime(snapshot.cpuUptime))
            ]
        )
    }

    private var gpuTile: some View {
        let snapshot = hub.snapshot
        let vramText: String
        if snapshot.gpuVRAMTotal > 0 {
            vramText = Formatters.bytes(snapshot.gpuVRAMUsed)
        } else {
            vramText = "—"
        }
        return DashboardGaugeTile(
            icon: "sparkles",
            title: "GPU",
            fraction: snapshot.gpuUtilization,
            value: Formatters.percent(snapshot.gpuUtilization),
            color: Theme.gpu,
            details: [
                .init(label: "VRAM", value: vramText),
                .init(label: "Chip", value: snapshot.gpuIsAvailable ? snapshot.gpuName : "—")
            ]
        )
    }

    private var memoryTile: some View {
        let snapshot = hub.snapshot
        let usedFraction = snapshot.memoryFraction
        return DashboardGaugeTile(
            icon: "memorychip",
            title: "Memory",
            fraction: usedFraction,
            value: Formatters.percent(usedFraction),
            color: memoryColor,
            details: [
                .init(label: "Used", value: Formatters.bytes(snapshot.memoryUsed)),
                .init(label: "Free", value: Formatters.bytes(snapshot.memoryFree)),
                .init(label: "Pressure", value: snapshot.memoryPressureLevel.rawValue.loc)
            ]
        )
    }

    private var diskTile: some View {
        let snapshot = hub.snapshot
        let used = snapshot.diskPrimaryFraction ?? 0
        return DashboardGaugeTile(
            icon: "internaldrive",
            title: "Disk",
            fraction: used,
            value: Formatters.percent(used),
            color: Theme.semantic(for: used),
            details: [
                .init(label: "Free", value: snapshot.diskPrimaryFree.map { Formatters.bytes($0) } ?? "—"),
                .init(label: "Read", value: Formatters.rateCompact(snapshot.diskReadRate)),
                .init(label: "Write", value: Formatters.rateCompact(snapshot.diskWriteRate))
            ]
        )
    }

    private var batteryTile: some View {
        let snapshot = hub.snapshot
        return DashboardGaugeTile(
            icon: snapshot.batteryIsCharging ? "battery.100.bolt" : "battery.75",
            title: "Battery",
            fraction: snapshot.batteryPercentage,
            value: Formatters.percent(snapshot.batteryPercentage),
            color: batteryColor,
            details: [
                .init(label: "State", value: batteryState.loc),
                .init(label: "Health", value: snapshot.batteryHealthFraction.map { Formatters.percent($0) } ?? "—"),
                .init(label: "Cycles", value: snapshot.batteryCycleCount.map { "\($0)" } ?? "—")
            ]
        )
    }

    private var networkTile: some View {
        let snapshot = hub.snapshot
        let activity = min(snapshot.networkDownloadRate / 5_000_000, 1)
        return DashboardGaugeTile(
            icon: "network",
            title: "Network",
            fraction: snapshot.networkIsConnected ? max(activity, 0.08) : 0,
            value: snapshot.networkIsConnected ? Formatters.rateCompact(snapshot.networkDownloadRate) : "—",
            color: snapshot.networkIsConnected ? Theme.info : Theme.danger,
            details: [
                .init(label: "Download", value: Formatters.rate(snapshot.networkDownloadRate)),
                .init(label: "Upload", value: Formatters.rate(snapshot.networkUploadRate)),
                .init(label: "IP", value: snapshot.networkLocalIP ?? "—")
            ],
            statusColor: snapshot.networkIsConnected ? Theme.ok : Theme.danger
        )
    }

    private var sensorTile: some View {
        let snapshot = hub.snapshot
        let peak = snapshot.sensorPeakCelsius
        let fanValue = snapshot.fanCount == 0 ? "—" : "\(snapshot.fanCount)"
        let rpmValue = snapshot.firstFanRPM.map { "\($0) RPM" } ?? "—"
        return DashboardGaugeTile(
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
        .opacity(snapshot.sensorsIsAvailable || snapshot.fansIsAvailable ? 1 : 0.58)
    }

    private var memoryColor: Color {
        switch hub.snapshot.memoryPressureLevel {
        case .low: return Theme.ok
        case .medium: return Theme.warn
        case .high: return Theme.danger
        }
    }

    private var batteryColor: Color {
        let snapshot = hub.snapshot
        if snapshot.batteryIsCharging { return Theme.ok }
        switch snapshot.batteryPercentage {
        case ..<0.20: return Theme.danger
        case ..<0.40: return Theme.warn
        default: return Theme.ok
        }
    }

    private var batteryState: String {
        let snapshot = hub.snapshot
        if snapshot.batteryIsCharged && snapshot.batteryOnACPower { return "Fully charged" }
        if snapshot.batteryIsCharging { return "Charging" }
        if snapshot.batteryOnACPower { return "On AC power" }
        return "On battery"
    }
}

struct DashboardHeaderSummary: View {
    @ObservedObject var hub: MonitorHub

    var body: some View {
        let snapshot = hub.snapshot
        HStack(spacing: 6) {
            HeaderSummaryPill(icon: "cpu",
                              value: Formatters.percent(snapshot.cpuUsage),
                              color: Theme.semantic(for: snapshot.cpuUsage))
            HeaderSummaryPill(icon: "memorychip",
                              value: Formatters.percent(snapshot.memoryFraction),
                              color: memoryColor)
            HeaderSummaryPill(icon: "arrow.down",
                              value: Formatters.rateCompact(snapshot.networkDownloadRate),
                              color: Theme.info)
        }
    }

    private var memoryColor: Color {
        switch hub.snapshot.memoryPressureLevel {
        case .low: return Theme.ok
        case .medium: return Theme.warn
        case .high: return Theme.danger
        }
    }
}

private struct HeaderSummaryPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(color)
            Text(value)
                .font(.metric(9.5, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
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
    let icon: String
    let title: String
    let fraction: Double
    let value: String
    let color: Color
    let details: [DashboardDetail]
    var statusColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color.opacity(0.14))
                    )

                Text(loc: title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let statusColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }

                Text(value)
                    .font(.metric(12, weight: .bold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 10)

            HStack {
                Spacer(minLength: 0)
                RingGauge(fraction: fraction,
                          color: color,
                          lineWidth: 5.5,
                          value: value)
                    .frame(width: 56, height: 56)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 10)

            VStack(spacing: 5) {
                ForEach(displayDetails) { detail in
                    HStack(spacing: 6) {
                        Text(detail.label.loc.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(detail.value)
                            .font(.metric(10, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .opacity(detail.placeholder ? 0 : 1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Theme.gaugeTileMinHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.gaugeTileRadius, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.gaugeTileRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private var displayDetails: [DashboardDetail] {
        var rows = Array(details.prefix(3))
        while rows.count < 3 { rows.append(.empty) }
        return rows
    }
}
