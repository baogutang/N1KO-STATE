import Foundation
import XCTest
@testable import N1KOAgentCore

final class AgentResponseAndShutdownTests: XCTestCase {
    func testApproveRouteRejectsWrongRequestOwnerAndCapabilityBeforeSending() throws {
        let coordinator = makeCoordinator()
        var actions: [AgentResponseAction] = []
        let channel = AgentResponseChannel(provider: .claude, ownerID: "socket-owner") {
            actions.append($0)
            return true
        }
        let snapshot = coordinator.ingest(
            AgentIngressEvent(
                provider: .claude,
                sessionID: "claude-approval",
                kind: .approvalRequested,
                title: "Approve Bash",
                requestID: "tool-1",
                responseOwnerID: "socket-owner"
            ),
            responseChannel: channel
        )
        let intervention = try XCTUnwrap(snapshot.sessions.first?.intervention)
        XCTAssertFalse(intervention.responseCapability.isEmpty)

        XCTAssertThrowsError(try coordinator.respond(
            provider: .claude,
            sessionID: "claude-approval",
            requestID: "wrong",
            ownerID: "socket-owner",
            capability: intervention.responseCapability,
            action: .approve(scope: nil)
        )) { XCTAssertEqual($0 as? AgentResponseRoutingError, .requestMismatch) }
        XCTAssertThrowsError(try coordinator.respond(
            provider: .claude,
            sessionID: "claude-approval",
            requestID: "tool-1",
            ownerID: "other-owner",
            capability: intervention.responseCapability,
            action: .approve(scope: nil)
        )) { XCTAssertEqual($0 as? AgentResponseRoutingError, .ownerMismatch) }
        XCTAssertThrowsError(try coordinator.respond(
            provider: .claude,
            sessionID: "claude-approval",
            requestID: "tool-1",
            ownerID: "socket-owner",
            capability: "wrong-capability",
            action: .approve(scope: nil)
        )) { XCTAssertEqual($0 as? AgentResponseRoutingError, .authenticationFailed) }
        XCTAssertTrue(actions.isEmpty)

        try coordinator.respond(
            provider: .claude,
            sessionID: "claude-approval",
            requestID: "tool-1",
            ownerID: "socket-owner",
            capability: intervention.responseCapability,
            action: .approve(scope: "session")
        )
        XCTAssertEqual(actions, [.approve(scope: "session")])
        XCTAssertEqual(coordinator.snapshot.sessions.first?.phase, .processing)
        XCTAssertNil(coordinator.snapshot.sessions.first?.intervention)
    }

    func testDenyAndAnswerRouteOnlyToOwningProviderChannel() throws {
        let coordinator = makeCoordinator()
        var routed: [String: AgentResponseAction] = [:]

        for (session, kind, action) in [
            ("codex-deny", AgentEventKind.approvalRequested, AgentResponseAction.deny(reason: "unsafe")),
            ("codex-answer", AgentEventKind.answerRequested, AgentResponseAction.answer(["scope": ["Tests"]]))
        ] {
            let channel = AgentResponseChannel(provider: .codex, ownerID: "ws-owner") {
                routed[session] = $0
                return true
            }
            let snapshot = coordinator.ingest(
                AgentIngressEvent(
                    provider: .codex,
                    sessionID: session,
                    kind: kind,
                    requestID: "request-\(session)",
                    responseOwnerID: "ws-owner"
                ),
                responseChannel: channel
            )
            let intervention = try XCTUnwrap(snapshot.sessions.first { $0.sessionID == session }?.intervention)
            try coordinator.respond(
                provider: .codex,
                sessionID: session,
                requestID: intervention.requestID,
                ownerID: intervention.responseOwnerID,
                capability: intervention.responseCapability,
                action: action
            )
        }

        XCTAssertEqual(routed["codex-deny"], .deny(reason: "unsafe"))
        XCTAssertEqual(routed["codex-answer"], .answer(["scope": ["Tests"]]))
    }

    func testMismatchedProviderChannelDoesNotCreateResponseCapability() throws {
        let coordinator = makeCoordinator()
        let channel = AgentResponseChannel(provider: .claude, ownerID: "owner") { _ in true }
        let snapshot = coordinator.ingest(
            AgentIngressEvent(
                provider: .codex,
                sessionID: "codex-1",
                kind: .approvalRequested,
                requestID: "request-1",
                responseOwnerID: "owner"
            ),
            responseChannel: channel
        )
        XCTAssertEqual(snapshot.sessions.first?.intervention?.responseCapability, "")
        XCTAssertThrowsError(try coordinator.respond(
            provider: .codex,
            sessionID: "codex-1",
            requestID: "request-1",
            ownerID: "owner",
            capability: "",
            action: .approve(scope: nil)
        ))
    }

    func testLifecyclePolicyDoesNotOwnMonitorSamplingAndShutdownClosesEverything() throws {
        let socket = MockIngressSource(kind: .socket)
        let watcher = MockIngressSource(kind: .watcher)
        let transport = MockIngressSource(kind: .transport)
        let ingress = AgentIngressCoordinator(sources: [socket, watcher, transport])
        let coordinator = AgentSessionCoordinator(
            configuration: AgentCoreConfiguration(enabled: true),
            store: AgentSessionStore(),
            ingressCoordinator: ingress,
            publicationQueue: DispatchQueue(label: "agent.tests.publication")
        )
        let task = MockTask()
        let process = MockProcess()
        coordinator.register(task: task)
        coordinator.register(subprocess: process)
        try coordinator.start()

        let activeResources = coordinator.resourceSnapshot
        XCTAssertTrue(activeResources.coordinatorStarted)
        XCTAssertEqual(activeResources.sockets, 1)
        XCTAssertEqual(activeResources.watchers, 1)
        XCTAssertEqual(activeResources.transports, 1)
        XCTAssertEqual(activeResources.registeredTasks, 1)
        XCTAssertEqual(activeResources.activeTasks, 1)
        XCTAssertEqual(activeResources.registeredSubprocesses, 1)
        XCTAssertEqual(activeResources.activeSubprocesses, 1)

        coordinator.applyLifecycle(.screenLocked)
        XCTAssertFalse(socket.suspended)
        XCTAssertTrue(watcher.suspended)
        XCTAssertTrue(transport.suspended)
        XCTAssertTrue(task.isCancelled)
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(coordinator.resourceSnapshot.activeTasks, 0)
        XCTAssertEqual(coordinator.resourceSnapshot.activeSubprocesses, 0)

        // Re-arm dedicated resources to prove shutdown accounting.
        task.isCancelled = false
        process.isRunning = true
        socket.isRunning = true
        watcher.isRunning = true
        transport.isRunning = true
        let report = coordinator.shutdown()
        XCTAssertEqual(report.socketsClosed, 1)
        XCTAssertEqual(report.watchersClosed, 1)
        XCTAssertEqual(report.transportsClosed, 1)
        XCTAssertEqual(report.tasksCancelled, 1)
        XCTAssertEqual(report.subprocessesTerminated, 1)
        XCTAssertEqual(report.remainingRunningResources, 0)
        XCTAssertFalse(socket.isRunning)
        XCTAssertFalse(watcher.isRunning)
        XCTAssertFalse(transport.isRunning)
    }

    func testCodexAppServerTransportFeedsProtocolParserAndStopsCleanly() throws {
        let transport = MockCodexTransport()
        let source = CodexAppServerIngressSource(transport: transport, ownerID: "ws-owner")
        let received = expectation(description: "app-server request normalized")
        try source.start { events, channel in
            let event = try! XCTUnwrap(events.first)
            XCTAssertEqual(event.provider, .codex)
            XCTAssertEqual(event.sessionID, "thread-transport")
            XCTAssertEqual(event.kind, .approvalRequested)
            XCTAssertEqual(event.requestID, "request-transport")
            XCTAssertEqual(channel?.ownerID, "ws-owner")
            received.fulfill()
        }
        let channel = AgentResponseChannel(provider: .codex, ownerID: "ws-owner") { _ in true }
        transport.emit(CodexAppServerMessage(
            data: Data(#"{"jsonrpc":"2.0","id":"request-transport","method":"item/fileChange/requestApproval","params":{"threadId":"thread-transport","reason":"Edit file"}}"#.utf8),
            responseChannel: channel
        ))
        wait(for: [received], timeout: 1)
        source.stop()
        XCTAssertFalse(source.isRunning)
        XCTAssertEqual(transport.stopCount, 1)
    }
}

private final class MockIngressSource: AgentIngressSource {
    let resourceKind: AgentIngressResourceKind
    var isRunning = false
    var suspended = false

    init(kind: AgentIngressResourceKind) { resourceKind = kind }

    func start(handler: @escaping AgentIngressHandler) throws { isRunning = true }
    func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        isRunning = !suspended
    }
    func stop() { isRunning = false }
}

private final class MockTask: AgentCancellableTask {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

private final class MockProcess: AgentManagedSubprocess {
    var isRunning = true
    func terminate() { isRunning = false }
}

private final class MockCodexTransport: CodexAppServerTransport {
    var isRunning = false
    var stopCount = 0
    private var receive: ((CodexAppServerMessage) -> Void)?

    func start(receive: @escaping (CodexAppServerMessage) -> Void) throws {
        isRunning = true
        self.receive = receive
    }

    func emit(_ message: CodexAppServerMessage) { receive?(message) }

    func stop() {
        if isRunning { stopCount += 1 }
        isRunning = false
        receive = nil
    }
}
