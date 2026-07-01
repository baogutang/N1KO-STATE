import SwiftUI

/// Compact dashboard layout with at-a-glance detail inside each ring.
struct GaugeGridView: View {
    @ObservedObject var hub: MonitorHub
    @ObservedObject var settings = AppSettings.shared
    @State private var tilesAppeared = false

    private let columns = [
        GridItem(.flexible(), spacing: Theme.gaugeGridSpacing, alignment: .top),
        GridItem(.flexible(), spacing: Theme.gaugeGridSpacing, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.gaugeGridSpacing) {
            ForEach(Array(visibleModules.enumerated()), id: \.element.id) { index, module in
                tile(for: module)
                    .opacity(tilesAppeared ? 1 : 0)
                    .offset(y: tilesAppeared ? 0 : 10)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.82)
                            .delay(Double(index) * 0.045),
                        value: tilesAppeared
                    )
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.top, 12)
        .padding(.bottom, Theme.padding)
        .onAppear {
            tilesAppeared = true
        }
        .onDisappear {
            tilesAppeared = false
        }
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
            details: ringDetails([
                ("Load", String(format: "%.2f", snapshot.cpuLoadAverageOne)),
                ("Cores", snapshot.cpuCoreCount == 0 ? "—" : "\(snapshot.cpuCoreCount)"),
                ("Uptime", Formatters.uptime(snapshot.cpuUptime))
            ])
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
            details: ringDetails([
                ("VRAM", vramText),
                ("Chip", snapshot.gpuIsAvailable ? snapshot.gpuName : "—")
            ])
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
            details: ringDetails([
                ("Used", Formatters.bytes(snapshot.memoryUsed)),
                ("Free", Formatters.bytes(snapshot.memoryFree)),
                ("Pressure", snapshot.memoryPressureLevel.rawValue.loc)
            ])
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
            details: ringDetails([
                ("Free", snapshot.diskPrimaryFree.map { Formatters.bytes($0) } ?? "—"),
                ("Read", Formatters.rateCompact(snapshot.diskReadRate)),
                ("Write", Formatters.rateCompact(snapshot.diskWriteRate))
            ])
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
            details: ringDetails([
                ("State", batteryState.loc),
                ("Health", snapshot.batteryHealthFraction.map { Formatters.percent($0) } ?? "—"),
                ("Cycles", snapshot.batteryCycleCount.map { "\($0)" } ?? "—")
            ])
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
            details: ringDetails([
                ("Download", Formatters.rateCompact(snapshot.networkDownloadRate)),
                ("Upload", Formatters.rateCompact(snapshot.networkUploadRate)),
                ("IP", snapshot.networkLocalIP ?? "—")
            ]),
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
            details: ringDetails([
                ("Peak", peak.map { Formatters.temperature($0) } ?? "—"),
                ("Fans", fanValue),
                ("RPM", rpmValue)
            ])
        )
        .opacity(snapshot.sensorsIsAvailable || snapshot.fansIsAvailable ? 1 : 0.58)
    }

    private func ringDetails(_ rows: [(String, String)]) -> [DashboardRingDetail] {
        var details = rows.map { DashboardRingDetail(label: $0.0, value: $0.1) }
        while details.count < 3 { details.append(.empty) }
        return Array(details.prefix(3))
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: value)
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

private struct DashboardGaugeTile: View {
    let icon: String
    let title: String
    let fraction: Double
    let value: String
    let color: Color
    let details: [DashboardRingDetail]
    var statusColor: Color?

    var body: some View {
        VStack(spacing: 10) {
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
                        .shadow(color: statusColor.opacity(0.45), radius: 3)
                }
            }

            DashboardRingGauge(fraction: fraction, color: color) {
                DashboardRingCenter(primaryValue: value, primaryColor: color, details: details)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: Theme.gaugeTileHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.gaugeTileRadius, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.gaugeTileRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.07), color.opacity(0.01)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.gaugeTileRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [color.opacity(0.22), Theme.stroke],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: color.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}
