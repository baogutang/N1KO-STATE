import Foundation
import XCTest
@testable import N1KOAgentCore

final class AgentSessionStoreTests: XCTestCase {
    func testClaudeAndCodexLifecycleMergeAttentionCompleteArchiveAndUsage() throws {
        let store = AgentSessionStore()
        let coordinator = makeCoordinator(store: store)
        let t0 = Date(timeIntervalSince1970: 100)

        _ = coordinator.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-1",
            kind: .started,
            timestamp: t0,
            cwd: "/tmp/project"
        ))
        _ = coordinator.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-1",
            kind: .processing,
            timestamp: t0.addingTimeInterval(1),
            title: "Keep title",
            message: "Working"
        ))
        _ = coordinator.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-1",
            kind: .approvalRequested,
            timestamp: t0.addingTimeInterval(2),
            title: "Approve Bash",
            requestID: "tool-1",
            responseOwnerID: "external"
        ))

        var claude = try XCTUnwrap(coordinator.snapshot.sessions.first)
        XCTAssertEqual(claude.phase, .waitingForApproval)
        XCTAssertEqual(claude.attention, .approval)
        XCTAssertTrue(claude.needsAttention)
        XCTAssertEqual(claude.cwd, "/tmp/project")

        _ = coordinator.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-1",
            kind: .completed,
            timestamp: t0.addingTimeInterval(3),
            message: "Done",
            usage: AgentUsage(inputTokens: 120, cachedInputTokens: 40, outputTokens: 30)
        ))
        claude = try XCTUnwrap(coordinator.snapshot.sessions.first)
        XCTAssertEqual(claude.phase, .completed)
        XCTAssertEqual(claude.attention, .completion)
        XCTAssertEqual(claude.usage.totalTokens, 150)

        _ = coordinator.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "codex-1",
            kind: .completed,
            timestamp: t0.addingTimeInterval(4),
            usage: AgentUsage(inputTokens: 50, outputTokens: 10)
        ))
        XCTAssertEqual(coordinator.snapshot.sessions.count, 2)
        XCTAssertEqual(coordinator.snapshot.usage.byProvider[.claude]?.inputTokens, 120)
        XCTAssertEqual(coordinator.snapshot.usage.byProvider[.codex]?.outputTokens, 10)

        _ = coordinator.archive(provider: .claude, sessionID: "claude-1", at: t0.addingTimeInterval(5))
        claude = try XCTUnwrap(coordinator.snapshot.sessions.first { $0.provider == .claude })
        XCTAssertEqual(claude.phase, .archived)
        XCTAssertFalse(claude.needsAttention)
        XCTAssertNotNil(claude.archivedAt)
    }

    func testAssociationMergesExternalIdentityIntoCanonicalSession() {
        let store = AgentSessionStore()
        let coordinator = makeCoordinator(store: store)
        _ = coordinator.associate(provider: .codex, externalID: "rollout-alias", sessionID: "thread-1")
        _ = coordinator.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "rollout-alias",
            kind: .processing,
            cwd: "/tmp/repo"
        ))
        _ = coordinator.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "thread-1",
            kind: .completed
        ))

        XCTAssertEqual(coordinator.snapshot.sessions.count, 1)
        XCTAssertEqual(coordinator.snapshot.sessions.first?.sessionID, "thread-1")
        XCTAssertEqual(coordinator.snapshot.sessions.first?.phase, .completed)
    }

    func testPersistenceRestoresSessionWithoutPersistingResponseCapability() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = AgentJSONSessionPersistence(fileURL: directory.appendingPathComponent("sessions.json"))

        let first = AgentSessionStore(persistence: persistence)
        _ = first.process(
            AgentIngressEvent(
                provider: .claude,
                sessionID: "restore-1",
                kind: .approvalRequested,
                title: "Approve",
                requestID: "req-1",
                responseOwnerID: "owner-1"
            ),
            responseCapability: "must-not-persist"
        )
        first.flush()

        let raw = try String(contentsOf: persistence.fileURL, encoding: .utf8)
        XCTAssertFalse(raw.contains("must-not-persist"))

        let restored = AgentSessionStore(persistence: persistence).snapshot()
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertTrue(restored.sessions[0].wasRestored)
        XCTAssertNil(restored.sessions[0].intervention)
        XCTAssertEqual(restored.sessions[0].attention, .approval)
    }

    func testRestoredStoreSkipsEqualOrOlderRolloutReplay() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = AgentJSONSessionPersistence(fileURL: directory.appendingPathComponent("sessions.json"))
        let timestamp = Date(timeIntervalSince1970: 500)
        let first = AgentSessionStore(persistence: persistence)
        let written = first.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "thread-old",
            kind: .completed,
            timestamp: timestamp
        ))

        let restored = AgentSessionStore(persistence: persistence)
        let replayed = restored.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "thread-old",
            kind: .started,
            timestamp: timestamp.addingTimeInterval(-20)
        ))
        XCTAssertEqual(replayed.generation, 1)
        XCTAssertEqual(replayed.sessions.first?.phase, .completed)
        XCTAssertGreaterThan(written.generation, 0)

        let exactReplay = restored.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "thread-old",
            kind: .completed,
            timestamp: timestamp
        ))
        XCTAssertEqual(exactReplay.generation, replayed.generation)
    }

    func testConversationProjectionIsBoundedPersistsAndExcludesCapabilities() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = AgentJSONSessionPersistence(fileURL: directory.appendingPathComponent("sessions.json"))
        let store = AgentSessionStore(persistence: persistence)
        let t0 = Date(timeIntervalSince1970: 1_000)

        for index in 0..<100 {
            _ = store.process(AgentIngressEvent(
                provider: .codex,
                sessionID: "conversation",
                kind: index.isMultiple(of: 2) ? .promptSubmitted : .processing,
                timestamp: t0.addingTimeInterval(Double(index)),
                message: "line-\(index)"
            ))
        }
        _ = store.process(
            AgentIngressEvent(
                provider: .codex,
                sessionID: "conversation",
                kind: .approvalRequested,
                timestamp: t0.addingTimeInterval(101),
                message: "approve-safe-projection",
                requestID: "request",
                responseOwnerID: "owner"
            ),
            responseCapability: "secret-capability-must-not-persist"
        )

        let live = try XCTUnwrap(store.snapshot().sessions.first)
        XCTAssertEqual(live.conversationItems.count, 80)
        XCTAssertEqual(live.conversationItems.last?.kind, .attention)
        XCTAssertEqual(live.conversationItems.last?.text, "approve-safe-projection")

        store.flush()
        let raw = try String(contentsOf: persistence.fileURL, encoding: .utf8)
        XCTAssertFalse(raw.contains("secret-capability-must-not-persist"))
        let restored = try XCTUnwrap(AgentSessionStore(persistence: persistence).snapshot().sessions.first)
        XCTAssertEqual(restored.conversationItems, live.conversationItems)
    }

    func testToolResultUpdatesBoundedCallProjectionWithoutAddingSecondHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = AgentJSONSessionPersistence(fileURL: directory.appendingPathComponent("sessions.json"))
        let store = AgentSessionStore(persistence: persistence)
        let t0 = Date(timeIntervalSince1970: 2_000)

        _ = store.process(AgentIngressEvent(
            provider: .claude,
            sessionID: "tool-history",
            kind: .processing,
            timestamp: t0,
            toolName: "Bash",
            toolInput: String(repeating: "i", count: 2_100),
            requestID: "tool-1"
        ))
        _ = store.process(AgentIngressEvent(
            provider: .claude,
            sessionID: "tool-history",
            kind: .toolResult,
            timestamp: t0.addingTimeInterval(1),
            toolResult: String(repeating: "r", count: 8_300),
            toolSucceeded: true,
            requestID: "tool-1"
        ))

        let live = try XCTUnwrap(store.snapshot().sessions.first?.conversationItems.first)
        XCTAssertEqual(store.snapshot().sessions.first?.conversationItems.count, 1)
        XCTAssertEqual(live.toolCallID, "tool-1")
        XCTAssertEqual(live.toolStatus, .completed)
        XCTAssertEqual(live.toolInput?.count, 2_049)
        XCTAssertEqual(live.toolResult?.count, 8_193)

        store.flush()
        let restored = try XCTUnwrap(AgentSessionStore(persistence: persistence).snapshot().sessions.first)
        XCTAssertEqual(restored.conversationItems, [live])
    }

    func testOlderReplayHydratesConversationWithoutRollingTerminalStateBackward() throws {
        let store = AgentSessionStore()
        let terminalTime = Date(timeIntervalSince1970: 5_000)
        _ = store.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "hydration",
            kind: .completed,
            timestamp: terminalTime,
            message: "Final answer"
        ))

        let hydrated = store.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "hydration",
            kind: .promptSubmitted,
            timestamp: terminalTime.addingTimeInterval(-10),
            message: "Original prompt"
        ))
        let session = try XCTUnwrap(hydrated.sessions.first)
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.completedAt, terminalTime)
        XCTAssertEqual(session.lastActivityAt, terminalTime)
        XCTAssertEqual(session.conversationItems.map(\.kind), [.user, .assistant])
        XCTAssertEqual(session.conversationItems.map(\.text), ["Original prompt", "Final answer"])

        let replayedAgain = store.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "hydration",
            kind: .promptSubmitted,
            timestamp: terminalTime.addingTimeInterval(-10),
            message: "Original prompt"
        ))
        XCTAssertEqual(replayedAgain.generation, hydrated.generation)
        XCTAssertEqual(replayedAgain.sessions.first?.conversationItems.count, 2)
    }

    func testLargeClaudeTranscriptUsesBoundedTailInsteadOfDroppingDetail() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriptURL = directory.appendingPathComponent("large-transcript.jsonl")
        let filler = #"{"sessionId":"large-claude","type":"user","message":{"role":"user","content":""#
            + String(repeating: "x", count: 4_300_000)
            + #""}}"# + "\n"
        let recent = """
        {"timestamp":"2026-07-17T01:00:00Z","sessionId":"large-claude","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Recent answer"}]}}
        {"timestamp":"2026-07-17T01:00:01Z","sessionId":"large-claude","type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tail-tool","name":"Bash","input":{"command":"swift test"}}]}}
        {"timestamp":"2026-07-17T01:00:02Z","sessionId":"large-claude","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tail-tool","content":"passed"}]}}
        """
        try (filler + recent).write(to: transcriptURL, atomically: true, encoding: .utf8)

        let coordinator = makeCoordinator()
        let snapshot = coordinator.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "large-claude",
            kind: .processing,
            timestamp: Date(timeIntervalSince1970: 1_800_000_100),
            message: "Hook update",
            transcriptPath: transcriptURL.path
        ))
        let session = try XCTUnwrap(snapshot.sessions.first)
        XCTAssertTrue(session.conversationItems.contains { $0.text == "Recent answer" })
        let tool = try XCTUnwrap(session.conversationItems.first { $0.toolCallID == "tail-tool" })
        XCTAssertEqual(tool.toolInput, #"{"command":"swift test"}"#)
        XCTAssertEqual(tool.toolResult, "passed")
        XCTAssertEqual(tool.toolStatus, .completed)
    }

    func testLatestQuotaWindowsPersistAndOlderReplayCannotOverwriteThem() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = AgentJSONSessionPersistence(fileURL: directory.appendingPathComponent("sessions.json"))
        let store = AgentSessionStore(persistence: persistence)
        let recent = Date(timeIntervalSince1970: 8_000)
        let older = recent.addingTimeInterval(-100)

        _ = store.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "quota",
            kind: .usage,
            timestamp: recent,
            usageWindows: [AgentUsageWindow(
                key: "primary",
                label: "5h",
                usedPercentage: 40,
                capturedAt: recent
            )]
        ))
        _ = store.process(AgentIngressEvent(
            provider: .codex,
            sessionID: "quota",
            kind: .usage,
            timestamp: older,
            usageWindows: [AgentUsageWindow(
                key: "primary",
                label: "5h",
                usedPercentage: 90,
                capturedAt: older
            )]
        ))

        XCTAssertEqual(store.snapshot().usage.providerWindows[.codex]?.first?.usedPercentage, 40)
        store.flush()
        XCTAssertEqual(
            AgentSessionStore(persistence: persistence).snapshot().usage.providerWindows[.codex]?.first?.usedPercentage,
            40
        )
    }

    func testHistoricalBatchPersistsAndComposesSnapshotOnlyOnce() throws {
        let persistence = CountingAgentPersistence()
        let store = AgentSessionStore(persistence: persistence)
        let base = Date(timeIntervalSince1970: 12_000)
        let events = (0..<82).map { index in
            AgentIngressEvent(
                provider: .codex,
                sessionID: "batched-history",
                kind: index == 0 ? .started : .processing,
                timestamp: base.addingTimeInterval(Double(index)),
                message: index == 0 ? nil : "history-\(index)"
            )
        }

        let snapshot = store.process(events.map { (event: $0, responseCapability: nil) })

        XCTAssertEqual(persistence.saveCount, 1)
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions.first?.conversationItems.count, 80)
        XCTAssertEqual(snapshot.sessions.first?.conversationItems.last?.text, "history-81")
    }

    func testConcurrentQwenSessionsInSameWorkspaceKeepProviderSessionIdentity() {
        let store = AgentSessionStore()
        let cwd = "/tmp/shared-qwen-workspace"
        _ = store.process(AgentIngressEvent(
            provider: .qwen,
            sessionID: "qwen-a",
            kind: .started,
            cwd: cwd
        ))
        _ = store.process(AgentIngressEvent(
            provider: .qwen,
            sessionID: "qwen-b",
            kind: .started,
            cwd: cwd
        ))
        _ = store.process(AgentIngressEvent(
            provider: .qwen,
            sessionID: "qwen-a",
            kind: .completed,
            cwd: cwd
        ))

        let sessions = store.snapshot().sessions.filter { $0.provider == .qwen }
        XCTAssertEqual(Set(sessions.map(\.sessionID)), ["qwen-a", "qwen-b"])
        XCTAssertEqual(sessions.first(where: { $0.sessionID == "qwen-a" })?.phase, .completed)
        XCTAssertEqual(sessions.first(where: { $0.sessionID == "qwen-b" })?.phase, .starting)
    }
}

private final class CountingAgentPersistence: AgentSessionPersisting {
    var saveCount = 0
    var state: AgentPersistedState?

    func load() throws -> AgentPersistedState? { state }

    func save(_ state: AgentPersistedState) throws {
        saveCount += 1
        self.state = state
    }
}

func makeCoordinator(store: AgentSessionStore = AgentSessionStore()) -> AgentSessionCoordinator {
    AgentSessionCoordinator(
        configuration: AgentCoreConfiguration(enabled: false),
        store: store,
        ingressCoordinator: AgentIngressCoordinator(sources: []),
        publicationQueue: DispatchQueue(label: "agent.tests.publication")
    )
}

func temporaryDirectory() -> URL {
    let suffix = UUID().uuidString.prefix(8)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("n1ko-\(suffix)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
