import Foundation
import SwiftUI

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

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .battery: return "battery.100"
        case .network: return "network"
        }
    }

    var color: Color {
        switch self {
        case .cpu: return Theme.cpu
        case .gpu: return Theme.gpu
        case .memory: return Theme.memory
        case .battery: return Theme.ok
        case .network: return Theme.network
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
