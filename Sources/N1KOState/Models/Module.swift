import Foundation

/// A popover monitor card. `allCases` order is the factory default; the user can
/// reorder and toggle each one independently (see `AppSettings.moduleOrder`).
enum Module: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, battery, disk, network, sensors

    var id: String { rawValue }

    /// Localization key / English title.
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .disk: return "Disk"
        case .network: return "Network"
        case .sensors: return "Sensors"
        }
    }

    var localizedTitle: String { title.loc }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .battery: return "battery.100"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .sensors: return "thermometer"
        }
    }
}
