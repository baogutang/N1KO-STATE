import Foundation
import Combine
import Darwin

enum MemoryPressureLevel: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

struct MemoryModuleSnapshot: Equatable {
    let total: Double
    let used: Double
    let free: Double
    let appMemory: Double
    let wired: Double
    let compressed: Double
    let cached: Double
    let swapUsed: Double
    let swapTotal: Double
    let pressure: Double
    let pressureLevel: MemoryPressureLevel
    let history: [Double]
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
    private lazy var historyBuffer = RingBuffer<Double>(capacity: historyCapacity)
    private let pageSize: Double
    private var sampledSwap = (used: 0.0, total: 0.0)

    init() {
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        pageSize = Double(ps)
        total = Double(ProcessInfo.processInfo.physicalMemory)
    }

    func sample() -> MemoryModuleSnapshot? {
        PerformanceDiagnostics.measure(.samplerMemory) {
            var stats = vm_statistics64_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

            let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
                }
            }
            guard kr == KERN_SUCCESS else { return nil }

            let internalPages = Double(stats.internal_page_count)
            let purgeable = Double(stats.purgeable_count)
            let external = Double(stats.external_page_count)

            let wired = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            let cached = external * pageSize
            let appMemory = max(internalPages - purgeable, 0) * pageSize

            let used = appMemory + wired + compressed
            let free = max(total - used, 0)

            let pressure = total > 0 ? min(max(used / total, 0), 1) : 0
            let pressureLevel: MemoryPressureLevel = {
                switch pressure {
                case ..<0.70: return .low
                case ..<0.88: return .medium
                default: return .high
                }
            }()

            let swap = readSwap()

            historyBuffer.append(pressure)
            return MemoryModuleSnapshot(
                total: total, used: used, free: free, appMemory: appMemory,
                wired: wired, compressed: compressed, cached: cached,
                swapUsed: swap.used, swapTotal: swap.total,
                pressure: pressure, pressureLevel: pressureLevel,
                history: historyBuffer.elements
            )
        }
    }

    func apply(_ sample: MemoryModuleSnapshot, publish: Bool = true) {
        if publish { objectWillChange.send() }
        total = sample.total
        used = sample.used
        free = sample.free
        appMemory = sample.appMemory
        wired = sample.wired
        compressed = sample.compressed
        cached = sample.cached
        swapUsed = sample.swapUsed
        swapTotal = sample.swapTotal
        pressure = sample.pressure
        pressureLevel = sample.pressureLevel
        history = sample.history
    }

    func refresh(publish: Bool = true) {
        if let sample = sample() { apply(sample, publish: publish) }
    }

    private func readSwap() -> (used: Double, total: Double) {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 {
            sampledSwap = (Double(xsw.xsu_used), Double(xsw.xsu_total))
        }
        return sampledSwap
    }
}
