import Foundation
import Combine
import Metal
import IOKit

final class GPUMonitor: ObservableObject {

    private(set) var name: String = "GPU"
    private(set) var utilization: Double = 0
    private(set) var vramUsed: Double = 0
    private(set) var vramTotal: Double = 0
    private(set) var history: [Double] = []
    private(set) var isAvailable = false

    let historyCapacity = 300
    private let device: MTLDevice?
    private var cachedService: io_service_t = 0
    /// Rediscovery is a full IORegistry sweep — never retry it more often than
    /// this, or machines with no usable accelerator pay the sweep every tick.
    private var lastDiscovery = Date.distantPast
    private let discoveryBackoff: TimeInterval = 60

    init() {
        device = MTLCreateSystemDefaultDevice()
        if let d = device {
            name = d.name
            vramTotal = Double(d.recommendedMaxWorkingSetSize)
            isAvailable = true
        }
        lastDiscovery = .distantPast
        discoverAcceleratorService()
    }

    deinit {
        if cachedService != 0 { IOObjectRelease(cachedService) }
    }

    func refresh() {
        if let stats = readStatsFromCache() {
            utilization = min(max(stats.util, 0), 1)
            if stats.memUsed > 0 { vramUsed = stats.memUsed }
        } else if let d = device {
            vramUsed = Double(d.currentAllocatedSize)
        }
        history.append(utilization)
        if history.count > historyCapacity { history.removeFirst(history.count - historyCapacity) }
        objectWillChange.send()
    }

    private func discoverAcceleratorService() {
        guard Date().timeIntervalSince(lastDiscovery) >= discoveryBackoff else { return }
        lastDiscovery = Date()
        if cachedService != 0 {
            IOObjectRelease(cachedService)
            cachedService = 0
        }
        autoreleasepool {
            guard let matching = IOServiceMatching("IOAccelerator") else { return }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                return
            }
            defer { IOObjectRelease(iterator) }

            var best: io_service_t = 0
            var bestUtil = -1.0
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let perf = IORegistryEntryCreateCFProperty(
                    service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? [String: Any] {
                    let hasUtil = perf["Device Utilization %"] != nil || perf["GPU Activity(%)"] != nil
                    if hasUtil {
                        let util = ((perf["Device Utilization %"] as? NSNumber)?.doubleValue
                            ?? (perf["GPU Activity(%)"] as? NSNumber)?.doubleValue ?? 0)
                        if util >= bestUtil {
                            if best != 0 { IOObjectRelease(best) }
                            best = service
                            IOObjectRetain(service)
                            bestUtil = util
                        }
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            cachedService = best
        }
    }

    private func readStatsFromCache() -> (util: Double, memUsed: Double)? {
        autoreleasepool {
            if cachedService == 0 { discoverAcceleratorService() }
            guard cachedService != 0 else { return nil }
            guard let perf = IORegistryEntryCreateCFProperty(
                cachedService, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else {
                IOObjectRelease(cachedService)
                cachedService = 0
                discoverAcceleratorService()
                return nil
            }
            let hasUtil = perf["Device Utilization %"] != nil || perf["GPU Activity(%)"] != nil
            guard hasUtil else { return nil }
            let util = ((perf["Device Utilization %"] as? NSNumber)?.doubleValue
                ?? (perf["GPU Activity(%)"] as? NSNumber)?.doubleValue ?? 0) / 100.0
            let mem = (perf["In use system memory"] as? NSNumber)?.doubleValue
                ?? (perf["Alloc system memory"] as? NSNumber)?.doubleValue ?? 0
            return (util, mem)
        }
    }
}
