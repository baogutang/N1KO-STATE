import Foundation

/// Metrics that can appear in the menu-bar widget (distinct from popover modules).
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, battery, network
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU usage"
        case .gpu: return "GPU usage"
        case .memory: return "Memory usage"
        case .battery: return "Battery level"
        case .network: return "Network speed"
        }
    }

    var settingsKeyPath: WritableKeyPath<AppSettings, Bool> {
        switch self {
        case .cpu: return \.menuCPU
        case .gpu: return \.menuGPU
        case .memory: return \.menuMemory
        case .battery: return \.menuBattery
        case .network: return \.menuNetwork
        }
    }
}
