import Foundation
@testable import N1KOAgentCore
import XCTest

final class AgentBridgeIntegrationTests: XCTestCase {
    func testBundledBridgeProbeAuthenticatesAndReachesProviderAwareIngress() throws {
        let root = URL(
            fileURLWithPath: "/tmp/n1ko-b-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let rollout = root.appendingPathComponent("rollout", isDirectory: true)
        try FileManager.default.createDirectory(at: rollout, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let coordinator = try AgentSessionCoordinator(configuration: AgentCoreConfiguration(
            enabled: true,
            runtimePaths: AgentRuntimePaths(
                runtimeDirectory: runtime,
                applicationSupportDirectory: support
            ),
            codexRolloutRoot: rollout
        ))
        try coordinator.start()
        defer { _ = coordinator.shutdown() }

        let received = expectation(description: "Gemini bridge probe reached Agent Core")
        let observer = coordinator.addSnapshotObserver { snapshot in
            if snapshot.sessions.contains(where: { $0.provider == .gemini }) {
                received.fulfill()
            }
        }
        defer { coordinator.removeSnapshotObserver(observer) }

        let bridgeURL = repositoryRoot()
            .appendingPathComponent(".build/debug/N1KOAgentBridge")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: bridgeURL.path), bridgeURL.path)
        let process = Process()
        process.executableURL = bridgeURL
        process.arguments = [
            "--provider", "gemini",
            "--profile", "gemini-hooks",
            "--managed-by", "com.n1ko.state.agent",
            "--schema-version", "1",
            "--runtime-directory", runtime.path,
            "--probe"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let response = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, response)
        XCTAssertTrue(response.contains("\"ok\":true"), response)
        wait(for: [received], timeout: 2)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
