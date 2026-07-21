import Foundation
import Combine
import Darwin

struct CoreSample: Identifiable, Equatable {
    let id: Int
    let usage: Double
    let isPerformance: Bool
}

struct LoadAverage: Equatable {
    let one: Double
    let five: Double
    let fifteen: Double
}

struct CPUModuleSnapshot: Equatable {
    let totalUsage: Double
    let cores: [CoreSample]
    let loadAverage: LoadAverage
    let uptime: TimeInterval
    let history: [Double]
}

final class CPUMonitor: ObservableObject {

    private(set) var totalUsage: Double = 0
    private(set) var cores: [CoreSample] = []
    private(set) var loadAverage = LoadAverage(one: 0, five: 0, fifteen: 0)
    private(set) var uptime: TimeInterval = 0
    private(set) var history: [Double] = []
    private(set) var frequency: Double?

    let historyCapacity = 300
    private lazy var historyBuffer = RingBuffer<Double>(capacity: historyCapacity)

    private var previousTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var sampledUsage: Double = 0
    private var sampledCores: [CoreSample] = []
    private let efficiencyCoreCount: Int
    private let performanceCoreCount: Int
    private let bootDate: Date

    init() {
        efficiencyCoreCount = CPUMonitor.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        performanceCoreCount = CPUMonitor.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        bootDate = CPUMonitor.bootDate()
        if let hz = CPUMonitor.sysctlInt("hw.cpufrequency"), hz > 0 {
            frequency = Double(hz) / 1_000_000_000
        }
    }

    func sample() -> CPUModuleSnapshot {
        PerformanceDiagnostics.measure(.samplerCPU) {
            let coreResult = sampleCores()
            var loads = [Double](repeating: 0, count: 3)
            getloadavg(&loads, 3)
            let load = LoadAverage(one: loads[0], five: loads[1], fifteen: loads[2])
            historyBuffer.append(coreResult.usage)
            return CPUModuleSnapshot(
                totalUsage: coreResult.usage,
                cores: coreResult.cores,
                loadAverage: load,
                uptime: Date().timeIntervalSince(bootDate),
                history: historyBuffer.elements
            )
        }
    }

    func apply(_ sample: CPUModuleSnapshot, publish: Bool = true) {
        if publish { objectWillChange.send() }
        totalUsage = sample.totalUsage
        cores = sample.cores
        loadAverage = sample.loadAverage
        uptime = sample.uptime
        history = sample.history
    }

    func refresh(publish: Bool = true) {
        apply(sample(), publish: publish)
    }

    private func sampleCores() -> (usage: Double, cores: [CoreSample]) {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &numCpus,
                                         &cpuInfo,
                                         &numCpuInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return (sampledUsage, sampledCores)
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let coreCount = Int(numCpus)
        var newTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        newTicks.reserveCapacity(coreCount)
        var samples: [CoreSample] = []
        samples.reserveCapacity(coreCount)

        var totalBusy = 0.0
        var totalAll = 0.0

        for i in 0..<coreCount {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            newTicks.append((user, system, idle, nice))

            var usage = 0.0
            if i < previousTicks.count {
                let prev = previousTicks[i]
                let du = Double(user &- prev.user)
                let ds = Double(system &- prev.system)
                let dn = Double(nice &- prev.nice)
                let di = Double(idle &- prev.idle)
                let busy = du + ds + dn
                let all = busy + di
                usage = all > 0 ? busy / all : 0
                totalBusy += busy
                totalAll += all
            }
            samples.append(CoreSample(id: i,
                                      usage: min(max(usage, 0), 1),
                                      isPerformance: coreIsPerformance(index: i, total: coreCount)))
        }

        previousTicks = newTicks
        let usage = totalAll > 0 ? totalBusy / totalAll : sampledUsage
        sampledUsage = usage
        sampledCores = samples
        return (usage, samples)
    }

    private func coreIsPerformance(index: Int, total: Int) -> Bool {
        guard efficiencyCoreCount + performanceCoreCount == total,
              efficiencyCoreCount > 0 else {
            return true
        }
        return index >= efficiencyCoreCount
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    static func bootDate() -> Date {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            return Date(timeIntervalSince1970: Double(tv.tv_sec))
        }
        return Date()
    }
}
