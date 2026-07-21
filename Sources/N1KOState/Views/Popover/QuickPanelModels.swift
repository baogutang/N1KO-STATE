import SwiftUI

enum QuickPanelSeverity: String, Equatable {
    case normal
    case elevated
    case critical

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .critical: return "Critical"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .elevated: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .normal: return Theme.ok
        case .elevated: return Theme.warn
        case .critical: return Theme.danger
        }
    }
}

struct QuickPanelHealthItem: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let severity: QuickPanelSeverity
}

struct QuickPanelModuleProjection: Identifiable {
    let module: Module
    let value: String
    let detail: String
    let trend: [Double]
    let trendMaximum: Double?
    let accent: Color

    var id: Module { module }

    var accessibilityTrendSummary: String {
        guard let summary = ChartAccessibilitySummary(values: trend) else {
            return "No history".loc
        }
        return summary.description { value in
            switch module {
            case .cpu, .gpu, .memory, .battery, .disk:
                return Formatters.percent(value)
            case .network:
                return Formatters.rateCompact(value)
            case .sensors:
                return Formatters.temperature(value)
            }
        }
    }
}

struct QuickPanelDisclosureState: Equatable {
    private(set) var expandedModule: Module?

    mutating func toggle(_ module: Module) {
        expandedModule = expandedModule == module ? nil : module
    }
}

enum QuickPanelLayoutMetrics {
    static let rowHeight: CGFloat = 50
    static let rowSpacing: CGFloat = 4
    static let healthHeight: CGFloat = 64
    static let minimumBodyHeight: CGFloat = 150
    static let expandedBodyHeight: CGFloat = 540

    static func collapsedBodyHeight(moduleCount: Int, maximum: CGFloat) -> CGFloat {
        let rows = CGFloat(max(moduleCount, 1)) * rowHeight
        let gaps = CGFloat(max(moduleCount - 1, 0)) * rowSpacing
        return min(maximum, max(minimumBodyHeight, healthHeight + rows + gaps + Theme.Spacing.m))
    }
}

enum QuickPanelProjectionFactory {
    static func health(from snapshot: MonitorDisplaySnapshot) -> [QuickPanelHealthItem] {
        let thermal = snapshot.sensorPeakCelsius
        return [
            QuickPanelHealthItem(
                id: "cpu",
                label: "CPU",
                value: Formatters.percent(snapshot.cpuUsage),
                severity: severity(fraction: snapshot.cpuUsage)
            ),
            QuickPanelHealthItem(
                id: "memory",
                label: "Memory",
                value: Formatters.percent(snapshot.memoryFraction),
                severity: memorySeverity(snapshot.memoryPressureLevel)
            ),
            QuickPanelHealthItem(
                id: "thermal",
                label: "Thermal",
                value: thermal.map(Formatters.temperature) ?? "—",
                severity: thermalSeverity(thermal)
            )
        ]
    }

    static func module(_ module: Module, hub: MonitorHub) -> QuickPanelModuleProjection {
        let snapshot = hub.snapshot
        switch module {
        case .cpu:
            return .init(module: module,
                         value: Formatters.percent(snapshot.cpuUsage),
                         detail: "Load %@".locf(String(format: "%.2f", snapshot.cpuLoadAverageOne)),
                         trend: hub.cpu.history,
                         trendMaximum: 1,
                         accent: Theme.cpu)
        case .gpu:
            return .init(module: module,
                         value: snapshot.gpuIsAvailable ? Formatters.percent(snapshot.gpuUtilization) : "—",
                         detail: snapshot.gpuIsAvailable ? snapshot.gpuName : "Unavailable".loc,
                         trend: hub.gpu.history,
                         trendMaximum: 1,
                         accent: Theme.gpu)
        case .memory:
            return .init(module: module,
                         value: Formatters.percent(snapshot.memoryFraction),
                         detail: snapshot.memoryPressureLevel.rawValue.loc,
                         trend: hub.memory.history,
                         trendMaximum: 1,
                         accent: Theme.memory)
        case .battery:
            return .init(module: module,
                         value: Formatters.percent(snapshot.batteryPercentage),
                         detail: batteryDetail(snapshot),
                         trend: hub.battery.history,
                         trendMaximum: 1,
                         accent: Theme.accent)
        case .disk:
            let combined = zipLongest(hub.disk.readHistory, hub.disk.writeHistory)
            return .init(module: module,
                         value: snapshot.diskPrimaryFraction.map(Formatters.percent) ?? "—",
                         detail: snapshot.diskPrimaryFree.map { "%@ free".locf(Formatters.bytesCompact($0)) } ?? "Unavailable".loc,
                         trend: combined,
                         trendMaximum: nil,
                         accent: Theme.disk)
        case .network:
            return .init(module: module,
                         value: snapshot.networkIsConnected ? Formatters.rateCompact(snapshot.networkDownloadRate) : "—",
                         detail: snapshot.networkIsConnected
                            ? "Up %@".locf(Formatters.rateCompact(snapshot.networkUploadRate))
                            : "Disconnected".loc,
                         trend: hub.network.downHistory,
                         trendMaximum: nil,
                         accent: Theme.network)
        case .sensors:
            return .init(module: module,
                         value: snapshot.sensorPeakCelsius.map(Formatters.temperature) ?? "—",
                         detail: snapshot.firstFanRPM.map { "%d RPM".locf($0) } ?? "Thermal status".loc,
                         trend: hub.sensors.peakHistory,
                         trendMaximum: 110,
                         accent: Theme.accent)
        }
    }

    private static func zipLongest(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        let count = max(lhs.count, rhs.count)
        guard count > 0 else { return [] }
        let leftOffset = count - lhs.count
        let rightOffset = count - rhs.count
        return (0..<count).map { index in
            let l = index >= leftOffset ? lhs[index - leftOffset] : 0
            let r = index >= rightOffset ? rhs[index - rightOffset] : 0
            return l + r
        }
    }

    private static func severity(fraction: Double) -> QuickPanelSeverity {
        switch fraction {
        case ..<0.70: return .normal
        case ..<0.90: return .elevated
        default: return .critical
        }
    }

    private static func memorySeverity(_ level: MemoryPressureLevel) -> QuickPanelSeverity {
        switch level {
        case .low: return .normal
        case .medium: return .elevated
        case .high: return .critical
        }
    }

    private static func thermalSeverity(_ value: Double?) -> QuickPanelSeverity {
        guard let value else { return .normal }
        switch value {
        case ..<75: return .normal
        case ..<90: return .elevated
        default: return .critical
        }
    }

    private static func batteryDetail(_ snapshot: MonitorDisplaySnapshot) -> String {
        if snapshot.batteryIsCharging { return "Charging".loc }
        if snapshot.batteryOnACPower { return "On AC power".loc }
        return "On battery".loc
    }
}

struct QuickPanelModulePreview: Identifiable, Equatable {
    let module: Module
    let value: String
    let detail: String
    var id: Module { module }
}

/// Immutable, action-free projection used by Settings. It cannot terminate a
/// process, change a fan, open Settings, or quit the app.
struct QuickPanelPreviewModel: Equatable {
    let health: [QuickPanelHealthItem]
    let modules: [QuickPanelModulePreview]

    static func make(snapshot: MonitorDisplaySnapshot, modules: [Module]) -> QuickPanelPreviewModel {
        QuickPanelPreviewModel(
            health: QuickPanelProjectionFactory.health(from: snapshot),
            modules: modules.map { module in
                switch module {
                case .cpu:
                    return .init(module: module, value: Formatters.percent(snapshot.cpuUsage), detail: "Current usage".loc)
                case .gpu:
                    return .init(module: module, value: snapshot.gpuIsAvailable ? Formatters.percent(snapshot.gpuUtilization) : "—", detail: snapshot.gpuName)
                case .memory:
                    return .init(module: module, value: Formatters.percent(snapshot.memoryFraction), detail: snapshot.memoryPressureLevel.rawValue.loc)
                case .battery:
                    return .init(module: module, value: Formatters.percent(snapshot.batteryPercentage), detail: snapshot.batteryIsCharging ? "Charging".loc : "Battery status".loc)
                case .disk:
                    return .init(module: module, value: snapshot.diskPrimaryFraction.map(Formatters.percent) ?? "—", detail: "Primary volume".loc)
                case .network:
                    return .init(module: module, value: Formatters.rateCompact(snapshot.networkDownloadRate), detail: snapshot.networkIsConnected ? "Connected".loc : "Disconnected".loc)
                case .sensors:
                    return .init(module: module, value: snapshot.sensorPeakCelsius.map(Formatters.temperature) ?? "—", detail: "Thermal status".loc)
                }
            }
        )
    }
}
