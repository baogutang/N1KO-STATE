import Foundation
import os.signpost

public enum AgentCoreMetric: String, CaseIterable, Codable, Sendable {
    case ingress
    case snapshotPublication
    case parseFailure
    case authenticationFailure
    case responseRouted
    case responseRejected
}

public struct AgentCoreDiagnosticsSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let counters: [AgentCoreMetric: UInt64]
}

public enum AgentCoreDiagnostics {
    private static let log = OSLog(subsystem: "com.n1ko.state.agent", category: .pointsOfInterest)
    private static let lock = NSLock()
    private static var counters: [AgentCoreMetric: UInt64] = [:]

    public static func event(_ metric: AgentCoreMetric) {
        let name: StaticString
        switch metric {
        case .ingress: name = "Agent Ingress"
        case .snapshotPublication: name = "Agent Snapshot Publication"
        case .parseFailure: name = "Agent Parse Failure"
        case .authenticationFailure: name = "Agent Authentication Failure"
        case .responseRouted: name = "Agent Response Routed"
        case .responseRejected: name = "Agent Response Rejected"
        }
        os_signpost(.event, log: log, name: name)
        lock.lock()
        counters[metric, default: 0] &+= 1
        lock.unlock()
    }

    public static func snapshot() -> AgentCoreDiagnosticsSnapshot {
        lock.lock()
        let current = counters
        lock.unlock()
        return AgentCoreDiagnosticsSnapshot(generatedAt: Date(), counters: current)
    }

    public static func reset() {
        lock.lock()
        counters.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
