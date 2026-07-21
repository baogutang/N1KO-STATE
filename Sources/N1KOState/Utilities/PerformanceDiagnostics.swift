import Foundation
import os.signpost

/// Stable performance probes shared by Instruments signposts, tests, and
/// exported diagnostics. Counters intentionally measure the existing runtime
/// boundaries without changing their scheduling or publication semantics.
enum PerformanceMetric: String, CaseIterable, Codable {
    case schedulingPlan
    case samplerCPU
    case samplerMemory
    case samplerNetwork
    case samplerGPU
    case samplerDisk
    case samplerSensors
    case samplerFans
    case samplerBattery
    case processScan
    case snapshotCommit
    case menuBarRender
    case quickPanelUpdate
    case settingsPreviewRender
    case agentSurfaceComposition

    var signpostName: StaticString {
        switch self {
        case .schedulingPlan: return "Scheduling Plan"
        case .samplerCPU: return "Sampler CPU"
        case .samplerMemory: return "Sampler Memory"
        case .samplerNetwork: return "Sampler Network"
        case .samplerGPU: return "Sampler GPU"
        case .samplerDisk: return "Sampler Disk"
        case .samplerSensors: return "Sampler Sensors"
        case .samplerFans: return "Sampler Fans"
        case .samplerBattery: return "Sampler Battery"
        case .processScan: return "Process Scan"
        case .snapshotCommit: return "Snapshot Commit"
        case .menuBarRender: return "Menu Bar Render"
        case .quickPanelUpdate: return "Quick Panel Update"
        case .settingsPreviewRender: return "Settings Preview Render"
        case .agentSurfaceComposition: return "Agent Surface Composition"
        }
    }
}

struct PerformanceCounter: Codable, Equatable {
    var count = 0
    var totalNanoseconds: UInt64 = 0
    var maximumNanoseconds: UInt64 = 0

    var averageMilliseconds: Double {
        guard count > 0 else { return 0 }
        return Double(totalNanoseconds) / Double(count) / 1_000_000
    }

    var maximumMilliseconds: Double {
        Double(maximumNanoseconds) / 1_000_000
    }
}

struct PerformanceDiagnosticsSnapshot: Codable, Equatable {
    let generatedAt: Date
    let counters: [String: PerformanceCounter]

    var jsonObject: [String: Any] {
        var values: [String: Any] = [:]
        for (name, counter) in counters {
            values[name] = [
                "count": counter.count,
                "totalNanoseconds": counter.totalNanoseconds,
                "averageMilliseconds": counter.averageMilliseconds,
                "maximumMilliseconds": counter.maximumMilliseconds
            ]
        }
        return [
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "counters": values
        ]
    }
}

enum PerformanceDiagnostics {
    struct Interval {
        fileprivate let metric: PerformanceMetric
        fileprivate let signpostID: OSSignpostID
        fileprivate let startedAt: UInt64
    }

    private static let log = OSLog(
        subsystem: "com.n1ko.state.monitor",
        category: .pointsOfInterest
    )
    private static let lock = NSLock()
    private static var counters: [PerformanceMetric: PerformanceCounter] = [:]

    @discardableResult
    static func begin(_ metric: PerformanceMetric) -> Interval {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: metric.signpostName, signpostID: signpostID)
        return Interval(metric: metric,
                        signpostID: signpostID,
                        startedAt: DispatchTime.now().uptimeNanoseconds)
    }

    static func end(_ interval: Interval) {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- interval.startedAt
        os_signpost(.end,
                    log: log,
                    name: interval.metric.signpostName,
                    signpostID: interval.signpostID)
        record(interval.metric, elapsedNanoseconds: elapsed)
    }

    static func measure<T>(_ metric: PerformanceMetric, _ body: () throws -> T) rethrows -> T {
        let interval = begin(metric)
        defer { end(interval) }
        return try body()
    }

    /// Records state-driven view updates where a duration would only measure
    /// construction of the opaque SwiftUI value rather than platform rendering.
    static func event(_ metric: PerformanceMetric) {
        os_signpost(.event, log: log, name: metric.signpostName)
        record(metric, elapsedNanoseconds: 0)
    }

    static func snapshot() -> PerformanceDiagnosticsSnapshot {
        lock.lock()
        let values = counters
        lock.unlock()
        return PerformanceDiagnosticsSnapshot(
            generatedAt: Date(),
            counters: Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        )
    }

    static func reset() {
        lock.lock()
        counters.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    static func writeSnapshot(to url: URL, metadata: [String: String] = [:]) throws {
        var payload = snapshot().jsonObject
        payload["metadata"] = metadata
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func record(_ metric: PerformanceMetric, elapsedNanoseconds: UInt64) {
        lock.lock()
        var counter = counters[metric, default: PerformanceCounter()]
        counter.count += 1
        counter.totalNanoseconds &+= elapsedNanoseconds
        counter.maximumNanoseconds = max(counter.maximumNanoseconds, elapsedNanoseconds)
        counters[metric] = counter
        lock.unlock()
    }
}
