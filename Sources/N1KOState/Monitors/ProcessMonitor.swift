import Foundation
import Combine
import Darwin

struct ProcSample: Identifiable, Equatable, Codable {
    let id: Int          // pid
    let name: String
    let cpu: Double       // percent (0...100 per core summed)
    let memBytes: Double
}

/// Top processes by CPU and by memory. Routine sampling uses public libproc
/// counters and per-PID CPU-time deltas; `/bin/ps` is retained only as a
/// compatibility fallback when libproc cannot enumerate processes.
final class ProcessMonitor: ObservableObject {

    @Published private(set) var topByCPU: [ProcSample] = []
    @Published private(set) var topByMemory: [ProcSample] = []

    private let queue = monitorWorkQueue
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 10.0
    private var inFlight = false
    private let sampler = LibprocProcessSampler()

    func refresh(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastRun) >= minInterval, !inFlight else { return }
        lastRun = now
        inFlight = true
        queue.async { [weak self] in
            guard let self else { return }
            let samples = PerformanceDiagnostics.measure(.processScan) {
                self.sampler.sample()
            }
            let ranked = ProcessMonitor.rank(samples: samples, limit: 5)
            DispatchQueue.main.async {
                if self.topByCPU != ranked.cpu { self.topByCPU = ranked.cpu }
                if self.topByMemory != ranked.memory { self.topByMemory = ranked.memory }
                self.inFlight = false
            }
        }
    }

    static func sample() -> [ProcSample] {
        LibprocProcessSampler().sample()
    }

    static func rank(samples: [ProcSample], limit: Int) -> (cpu: [ProcSample], memory: [ProcSample]) {
        let count = max(limit, 0)
        return (
            Array(samples.sorted { lhs, rhs in
                lhs.cpu == rhs.cpu ? lhs.id < rhs.id : lhs.cpu > rhs.cpu
            }.prefix(count)),
            Array(samples.sorted { lhs, rhs in
                lhs.memBytes == rhs.memBytes ? lhs.id < rhs.id : lhs.memBytes > rhs.memBytes
            }.prefix(count))
        )
    }

    static func cpuPercent(previousCPUTimeNanoseconds: UInt64,
                           currentCPUTimeNanoseconds: UInt64,
                           previousUptimeNanoseconds: UInt64,
                           currentUptimeNanoseconds: UInt64) -> Double {
        guard currentCPUTimeNanoseconds >= previousCPUTimeNanoseconds,
              currentUptimeNanoseconds > previousUptimeNanoseconds else { return 0 }
        let cpuDelta = Double(currentCPUTimeNanoseconds - previousCPUTimeNanoseconds)
        let wallDelta = Double(currentUptimeNanoseconds - previousUptimeNanoseconds)
        return min(max(cpuDelta / wallDelta * 100, 0), 10_000)
    }

    static func psFallback() -> [ProcSample] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-exo", "pid,pcpu,rss,comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcSample] = []
        result.reserveCapacity(256)
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("PID") { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { continue }
            let name = (String(parts[3]) as NSString).lastPathComponent
            result.append(ProcSample(id: pid, name: name, cpu: cpu, memBytes: rssKB * 1024))
        }
        return result
    }

    /// Send SIGTERM to a process (no privilege elevation).
    @discardableResult
    static func terminate(pid: Int) -> Bool {
        kill(pid_t(pid), SIGTERM) == 0
    }
}

final class LibprocProcessSampler {
    private struct Counter {
        let totalTicks: UInt64
        let sampledAt: UInt64
    }

    private var previous: [Int: Counter] = [:]
    func sample() -> [ProcSample] {
        let now = DispatchTime.now().uptimeNanoseconds
        let pids = allPIDs()
        guard !pids.isEmpty else { return ProcessMonitor.psFallback() }

        var next: [Int: Counter] = [:]
        next.reserveCapacity(pids.count)
        var samples: [ProcSample] = []
        samples.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let raw = resourceUsage(pid: pid) else { continue }
            let id = Int(pid)
            let totalTicks = raw.userTicks &+ raw.systemTicks
            let cpu: Double
            if let prior = previous[id], now > prior.sampledAt, totalTicks >= prior.totalTicks {
                cpu = ProcessMonitor.cpuPercent(
                    previousCPUTimeNanoseconds: prior.totalTicks,
                    currentCPUTimeNanoseconds: totalTicks,
                    previousUptimeNanoseconds: prior.sampledAt,
                    currentUptimeNanoseconds: now
                )
            } else {
                cpu = 0
            }
            next[id] = Counter(totalTicks: totalTicks, sampledAt: now)
            samples.append(ProcSample(id: id,
                                      name: processName(pid: pid),
                                      cpu: cpu,
                                      memBytes: Double(raw.physicalFootprint)))
        }

        previous = next
        return samples
    }

    private func allPIDs() -> [pid_t] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimatedCount) + 32)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private func resourceUsage(pid: pid_t) -> (userTicks: UInt64,
                                                systemTicks: UInt64,
                                                physicalFootprint: UInt64)? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else { return nil }
        return (info.ri_user_time, info.ri_system_time, info.ri_phys_footprint)
    }

    private func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { bytes in
            proc_name(pid, bytes.baseAddress, UInt32(bytes.count))
        }
        guard length > 0 else { return "PID \(pid)" }
        return String(cString: buffer)
    }

}
