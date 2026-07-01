import Foundation

/// Long-window metric history (24 h @ 30 s granularity) for trend charts.
final class HistoryStore {
    static let shared = HistoryStore()

    enum Series: String, CaseIterable, Codable {
        case cpu, memory, netDown, netUp
    }

    enum Range: String, CaseIterable, Identifiable {
        case m1 = "1m"
        case m10 = "10m"
        case h1 = "1h"
        case h24 = "24h"
        var id: String { rawValue }

        /// Approximate sample count at 30 s spacing (1 m uses live short buffer instead).
        var sampleCount: Int {
            switch self {
            case .m1: return 0
            case .m10: return 20
            case .h1: return 120
            case .h24: return 2880
            }
        }
    }

    private let sampleInterval: TimeInterval = 30
    private let capacity = 2880
    private var buffers: [Series: [Double]] = [:]
    private var lastRecord = Date.distantPast
    private let lock = NSLock()
    private let persistURL: URL
    private var dirty = false
    private var lastPersist = Date.distantPast
    private let persistInterval: TimeInterval = 300
    private let ioQueue = DispatchQueue(label: "com.n1ko.state.monitor.history", qos: .utility)
    private var diskLoaded = false
    static let maxDisplaySamples = 180

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("N1KO-STATE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        persistURL = dir.appendingPathComponent("history.json")
        for s in Series.allCases { buffers[s] = [] }
        ioQueue.async { [weak self] in
            self?.loadFromDisk()
        }
    }

    func record(cpu: Double, memory: Double, netDown: Double, netUp: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard diskLoaded else { return }
        let now = Date()
        guard now.timeIntervalSince(lastRecord) >= sampleInterval else { return }
        lastRecord = now
        append(.cpu, cpu)
        append(.memory, memory)
        append(.netDown, netDown)
        append(.netUp, netUp)
        dirty = true
        schedulePersistIfNeeded()
    }

    func flushSync(timeout: TimeInterval = 0.5) {
        let sem = DispatchSemaphore(value: 0)
        ioQueue.async { [weak self] in
            self?.persistToDiskLocked()
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
    }

    /// Values for chart rendering. `shortWindow` is the monitor's ~1 s sampled history (for 1 m).
    func values(for series: Series, range: Range, shortWindow: [Double]) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        if range == .m1 {
            let n = min(60, shortWindow.count)
            return n > 0 ? Array(shortWindow.suffix(n)) : shortWindow
        }
        let buf = buffers[series] ?? []
        let n = min(range.sampleCount, buf.count)
        let values = n > 0 ? Array(buf.suffix(n)) : []
        return Self.downsampleForDisplay(values)
    }

    static func downsampleForDisplay(_ values: [Double], maxSamples: Int = maxDisplaySamples) -> [Double] {
        guard maxSamples > 1, values.count > maxSamples else { return values }
        let bucketSize = Double(values.count) / Double(maxSamples)
        return (0..<maxSamples).compactMap { bucket in
            let start = Int((Double(bucket) * bucketSize).rounded(.down))
            let end = min(values.count, max(start + 1, Int((Double(bucket + 1) * bucketSize).rounded(.down))))
            guard start < end else { return nil }
            return values[start..<end].max()
        }
    }

    func snapshot() -> [String: [Double]] {
        lock.lock()
        defer { lock.unlock() }
        var out: [String: [Double]] = [:]
        for (k, v) in buffers { out[k.rawValue] = v }
        return out
    }

    private func append(_ series: Series, _ value: Double) {
        var buf = buffers[series] ?? []
        buf.append(value)
        if buf.count > capacity { buf.removeFirst(buf.count - capacity) }
        buffers[series] = buf
    }

    private struct Persisted: Codable {
        var buffers: [String: [Double]]
    }

    private func schedulePersistIfNeeded() {
        let now = Date()
        guard dirty, now.timeIntervalSince(lastPersist) >= persistInterval else { return }
        dirty = false
        lastPersist = now
        ioQueue.async { [weak self] in self?.persistToDiskLocked() }
    }

    private func persistToDiskLocked() {
        lock.lock()
        let payload = Persisted(buffers: buffers.mapKeys { $0.rawValue })
        let url = persistURL
        lock.unlock()
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadFromDisk() {
        let loadedBuffers: [Series: [Double]]
        if let data = try? Data(contentsOf: persistURL),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            var decoded: [Series: [Double]] = [:]
            for series in Series.allCases {
                decoded[series] = Array((persisted.buffers[series.rawValue] ?? []).suffix(capacity))
            }
            loadedBuffers = decoded
        } else {
            loadedBuffers = Dictionary(uniqueKeysWithValues: Series.allCases.map { ($0, []) })
        }

        lock.lock()
        buffers = loadedBuffers
        diskLoaded = true
        lock.unlock()
    }
}

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var out: [T: Value] = [:]
        for (k, v) in self { out[transform(k)] = v }
        return out
    }
}
