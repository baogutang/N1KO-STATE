import Foundation
import Combine
import Darwin

enum MemoryPressureLevel: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

final class MemoryMonitor: ObservableObject {

    private(set) var total: Double = 0
    private(set) var used: Double = 0
    private(set) var free: Double = 0
    private(set) var appMemory: Double = 0
    private(set) var wired: Double = 0
    private(set) var compressed: Double = 0
    private(set) var cached: Double = 0
    private(set) var swapUsed: Double = 0
    private(set) var swapTotal: Double = 0
    private(set) var pressure: Double = 0
    private(set) var pressureLevel: MemoryPressureLevel = .low
    private(set) var history: [Double] = []

    let historyCapacity = 300
    private let pageSize: Double

    init() {
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        pageSize = Double(ps)
        total = Double(ProcessInfo.processInfo.physicalMemory)
    }

    func refresh() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let internalPages = Double(stats.internal_page_count)
        let purgeable = Double(stats.purgeable_count)
        let external = Double(stats.external_page_count)

        wired = Double(stats.wire_count) * pageSize
        compressed = Double(stats.compressor_page_count) * pageSize
        cached = external * pageSize
        appMemory = max(internalPages - purgeable, 0) * pageSize

        used = appMemory + wired + compressed
        free = max(total - used, 0)

        if total > 0 {
            pressure = min(max(used / total, 0), 1)
        }
        pressureLevel = {
            switch pressure {
            case ..<0.70: return .low
            case ..<0.88: return .medium
            default: return .high
            }
        }()

        readSwap()

        history.append(pressure)
        if history.count > historyCapacity { history.removeFirst(history.count - historyCapacity) }

        objectWillChange.send()
    }

    private func readSwap() {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 {
            swapUsed = Double(xsw.xsu_used)
            swapTotal = Double(xsw.xsu_total)
        }
    }
}
