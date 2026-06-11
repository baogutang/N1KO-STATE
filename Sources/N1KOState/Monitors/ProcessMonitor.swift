import Foundation
import Combine
import Darwin

struct ProcSample: Identifiable {
    let id: Int          // pid
    let name: String
    let cpu: Double       // percent (0...100 per core summed)
    let memBytes: Double
}

/// Top processes by CPU and by memory, sampled with `ps` on a background queue
/// and throttled so our own footprint stays tiny.
final class ProcessMonitor: ObservableObject {

    @Published private(set) var topByCPU: [ProcSample] = []
    @Published private(set) var topByMemory: [ProcSample] = []

    private let queue = monitorWorkQueue
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 5.0
    private var inFlight = false

    func refresh() {
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= minInterval, !inFlight else { return }
        lastRun = now
        inFlight = true
        queue.async { [weak self] in
            let samples = ProcessMonitor.sample()
            let byCPU = Array(samples.sorted { $0.cpu > $1.cpu }.prefix(5))
            let byMem = Array(samples.sorted { $0.memBytes > $1.memBytes }.prefix(5))
            DispatchQueue.main.async {
                self?.topByCPU = byCPU
                self?.topByMemory = byMem
                self?.inFlight = false
            }
        }
    }

    static func sample() -> [ProcSample] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // Sort by CPU descending and only parse the first N rows — avoids scanning
        // thousands of processes every tick (major source of N1KO-STATE CPU use).
        task.arguments = ["-exo", "pid,pcpu,rss,comm", "-r"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcSample] = []
        result.reserveCapacity(48)
        for line in out.split(separator: "\n") {
            if result.count >= 48 { break }
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
