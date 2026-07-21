import Foundation
@testable import N1KOAgentCore
import XCTest

final class AgentNativeRuntimeTests: XCTestCase {
    func testCodexResponsePayloadsPreserveMethodSpecificSemantics() throws {
        let command = try XCTUnwrap(CodexAppServerStdioTransport.responsePayload(
            action: .approve(scope: "session"),
            method: "item/commandExecution/requestApproval",
            params: [:]
        ))
        XCTAssertEqual(command["decision"] as? String, "acceptForSession")

        let permissions = try XCTUnwrap(CodexAppServerStdioTransport.responsePayload(
            action: .approve(scope: nil),
            method: "item/permissions/requestApproval",
            params: ["permissions": ["network": true]]
        ))
        XCTAssertEqual(permissions["scope"] as? String, "turn")
        XCTAssertEqual((permissions["permissions"] as? [String: Bool])?["network"], true)

        let answer = try XCTUnwrap(CodexAppServerStdioTransport.responsePayload(
            action: .answer(["choice": ["A", "B"]]),
            method: "item/tool/requestUserInput",
            params: [:]
        ))
        let answers = answer["answers"] as? [String: [String: [String]]]
        XCTAssertEqual(answers?["choice"]?["answers"], ["A", "B"])
        XCTAssertNil(CodexAppServerStdioTransport.responsePayload(
            action: .answer([:]),
            method: "item/fileChange/requestApproval",
            params: [:]
        ))
    }

    func testExecutableResolutionHonorsExplicitAuthenticatedClientPaths() {
        let codex = CodexAppServerStdioTransport.resolveExecutable(
            environment: ["N1KO_CODEX_PATH": "/private/tools/codex", "PATH": ""],
            isExecutable: { $0 == "/private/tools/codex" }
        )
        XCTAssertEqual(codex?.path, "/private/tools/codex")

        let claude = AgentNativeRuntimeController.resolveClaudeExecutable(
            environment: ["N1KO_CLAUDE_PATH": "/private/tools/claude", "PATH": ""],
            isExecutable: { $0 == "/private/tools/claude" }
        )
        XCTAssertEqual(claude?.path, "/private/tools/claude")
    }

    func testCodexNativeOwnershipAndNonTMUXMessagingUseOneTransport() async throws {
        let transport = MockCodexCommandTransport()
        let runtime = AgentNativeRuntimeController(codexTransport: transport)
        let recorder = NativeEventRecorder()
        runtime.start { recorder.append($0) }

        let handle = try await runtime.startSession(
            provider: .codex,
            cwd: FileManager.default.temporaryDirectory.path,
            preferredSessionID: nil
        )
        XCTAssertEqual(handle.sessionID, "native-codex-thread")
        XCTAssertTrue(runtime.manages(provider: .codex, sessionID: handle.sessionID))
        XCTAssertEqual(recorder.events.map(\.kind), [.started])

        try await runtime.sendMessage(
            provider: .codex,
            sessionID: "existing-desktop-thread",
            expectedTurnID: "turn-7",
            text: "continue"
        )
        XCTAssertEqual(transport.messages.first?.threadID, "existing-desktop-thread")
        XCTAssertEqual(transport.messages.first?.expectedTurnID, "turn-7")

        do {
            try await runtime.terminateSession(provider: .codex, sessionID: "existing-desktop-thread")
            XCTFail("An externally-owned Codex thread must not be archived by native termination")
        } catch let error as AgentNativeRuntimeError {
            XCTAssertEqual(error, .sessionNotOwned(.codex, "existing-desktop-thread"))
        }

        try await runtime.terminateSession(provider: .codex, sessionID: handle.sessionID)
        XCTAssertEqual(transport.archivedThreadIDs, [handle.sessionID])
        XCTAssertFalse(runtime.manages(provider: .codex, sessionID: handle.sessionID))
    }

    func testInvalidWorkingDirectoryNeverLaunchesAChild() async {
        let transport = MockCodexCommandTransport()
        let runtime = AgentNativeRuntimeController(codexTransport: transport)
        runtime.start { _ in }
        do {
            _ = try await runtime.startSession(provider: .codex, cwd: "relative/path", preferredSessionID: nil)
            XCTFail("Relative paths must be rejected")
        } catch let error as AgentNativeRuntimeError {
            XCTAssertEqual(error, .invalidWorkingDirectory)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(transport.startThreadCalls, 0)
    }

    func testInstalledCodexAppServerInitializesAndStopsWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["N1KO_RUN_CODEX_APP_SERVER_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Set N1KO_RUN_CODEX_APP_SERVER_ACCEPTANCE=1 for the local app-server acceptance gate")
        }
        let transport = CodexAppServerStdioTransport(requestTimeout: 8)
        try transport.start { _ in }
        XCTAssertTrue(transport.isRunning)
        transport.stop()
        XCTAssertFalse(transport.isRunning)
    }

    func testClaudePseudoTerminalLaunchInputAndOwnedTermination() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-native-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("claude")
        try Data("#!/bin/sh\ntrap 'exit 0' TERM HUP INT\nwhile IFS= read -r line; do :; done\n".utf8)
            .write(to: executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let runtime = AgentNativeRuntimeController(environment: [
            "N1KO_CLAUDE_PATH": executable.path,
            "HOME": root.path,
            "PATH": "/usr/bin:/bin"
        ])
        let recorder = NativeEventRecorder()
        runtime.start { recorder.append($0) }
        let handle = try await runtime.startSession(
            provider: .claude,
            cwd: root.path,
            preferredSessionID: "test-session"
        )
        XCTAssertTrue(runtime.manages(provider: .claude, sessionID: handle.sessionID))
        try await runtime.sendMessage(
            provider: .claude,
            sessionID: handle.sessionID,
            expectedTurnID: nil,
            text: "hello"
        )
        try await runtime.terminateSession(provider: .claude, sessionID: handle.sessionID)
        XCTAssertFalse(runtime.manages(provider: .claude, sessionID: handle.sessionID))
        XCTAssertEqual(recorder.events.map(\.kind), [.started, .promptSubmitted, .ended])
    }
}

private final class NativeEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AgentIngressEvent] = []
    var events: [AgentIngressEvent] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func append(_ event: AgentIngressEvent) {
        lock.lock(); storage.append(event); lock.unlock()
    }
}

private final class MockCodexCommandTransport: CodexAppServerCommandTransport, @unchecked Sendable {
    struct Message {
        let threadID: String
        let expectedTurnID: String?
        let text: String
    }

    var isRunning = true
    private(set) var startThreadCalls = 0
    private(set) var archivedThreadIDs: [String] = []
    private(set) var messages: [Message] = []

    func start(receive: @escaping (CodexAppServerMessage) -> Void) throws {}
    func stop() { isRunning = false }

    func startThread(cwd: String) async throws -> String {
        startThreadCalls += 1
        return "native-codex-thread"
    }

    func archiveThread(threadID: String) async throws {
        archivedThreadIDs.append(threadID)
    }

    func sendMessage(threadID: String, expectedTurnID: String?, text: String) async throws {
        messages.append(Message(threadID: threadID, expectedTurnID: expectedTurnID, text: text))
    }
}
