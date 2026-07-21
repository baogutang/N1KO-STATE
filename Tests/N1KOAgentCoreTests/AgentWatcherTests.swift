import Foundation
import XCTest
@testable import N1KOAgentCore

final class AgentWatcherTests: XCTestCase {
    func testRestorationProjectionBoundsOneSessionToIdentityUsageAndRecentHistory() {
        let base = Date(timeIntervalSince1970: 100)
        var events = [AgentIngressEvent(
            provider: .codex,
            sessionID: "bounded",
            kind: .started,
            timestamp: base,
            cwd: "/tmp/repo"
        )]
        for index in 1...1_000 {
            events.append(AgentIngressEvent(
                provider: .codex,
                sessionID: "bounded",
                kind: .processing,
                timestamp: base.addingTimeInterval(Double(index))
            ))
        }
        events.append(AgentIngressEvent(
            provider: .codex,
            sessionID: "bounded",
            kind: .usage,
            timestamp: base.addingTimeInterval(1_001),
            usage: AgentUsage(inputTokens: 1_000, outputTokens: 100)
        ))
        events.append(AgentIngressEvent(
            provider: .codex,
            sessionID: "bounded",
            kind: .completed,
            timestamp: base.addingTimeInterval(1_002)
        ))

        let projected = CodexRolloutIngressSource.restorationProjection(events)
        XCTAssertEqual(projected.count, 82)
        XCTAssertEqual(projected.first?.kind, .started)
        XCTAssertEqual(projected.filter { $0.kind == .processing }.count, 79)
        XCTAssertEqual(projected.filter { $0.kind == .usage }.count, 1)
        XCTAssertEqual(projected.last?.kind, .completed)
    }

    func testRolloutWatcherRestoresExistingSessionWithoutPolling() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rollout = root.appendingPathComponent("rollout-thread-watch.jsonl")
        try """
        {"type":"session_meta","payload":{"id":"thread-watch","cwd":"/tmp/repo","originator":"Codex Desktop","source":"desktop"}}
        {"type":"event_msg","payload":{"type":"agent_message","phase":"final","message":"Done"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)

        let restored = expectation(description: "existing rollout restored")
        let source = CodexRolloutIngressSource(rootURL: root)
        try source.start { events, _ in
            if events.contains(where: {
                $0.sessionID == "thread-watch" && $0.kind == .completed
            }) {
                restored.fulfill()
            }
        }
        defer { source.stop() }
        wait(for: [restored], timeout: 3)
        XCTAssertTrue(source.isRunning)
    }

    func testBoundedRolloutReadKeepsSessionMetaAndLatestTail() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout-large.jsonl")
        let first = #"{"type":"session_meta","payload":{"id":"large","cwd":"/tmp/repo"}}"# + "\n"
        let filler = String(repeating: #"{"type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":"working"}}"# + "\n", count: 20_000)
        let last = #"{"type":"event_msg","payload":{"type":"agent_message","phase":"final","message":"done"}}"# + "\n"
        try (first + filler + last).write(to: url, atomically: true, encoding: .utf8)
        let size = UInt64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0)

        let bounded = try XCTUnwrap(CodexRolloutIngressSource.boundedRolloutData(from: url, size: size))
        XCTAssertLessThanOrEqual(bounded.count, 1_048_576 + first.utf8.count)
        let events = try CodexRolloutParser.parse(bounded)
        XCTAssertEqual(events.first?.sessionID, "large")
        XCTAssertEqual(events.last?.kind, .completed)
    }
}
