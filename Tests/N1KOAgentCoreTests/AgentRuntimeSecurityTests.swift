import Darwin
import Foundation
import XCTest
@testable import N1KOAgentCore

final class AgentRuntimeSecurityTests: XCTestCase {
    func testRuntimePathsAndSecretUsePrivatePermissionsAndN1KOIdentity() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AgentRuntimePaths(
            runtimeDirectory: root.appendingPathComponent("com.n1ko.state.agent.501"),
            applicationSupportDirectory: root.appendingPathComponent("N1KO-STATE/AgentCore")
        )
        try paths.prepare()
        let secretStore = AgentInstallSecretStore(secretURL: paths.secretURL)
        let first = try secretStore.loadOrCreate()
        let second = try secretStore.loadOrCreate()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.utf8.count, 64)
        XCTAssertTrue(paths.socketURL.path.contains("com.n1ko.state.agent"))
        XCTAssertEqual(permissions(paths.runtimeDirectory), 0o700)
        XCTAssertEqual(permissions(paths.secretURL), 0o600)
    }

    func testDiagnosticsRedactSecretsPromptsTokensAndHomePaths() throws {
        let input = Data(#"{"authentication":"top-secret","message":"private prompt","path":"/Users/test/repo","session_id":"private-session","nested":{"api_key":"key-value","response_capability":"cap-value"}}"#.utf8)
        let data = AgentDiagnosticRedactor.redact(json: input, homeDirectory: "/Users/test")
        let output = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(output.contains("top-secret"))
        XCTAssertFalse(output.contains("private prompt"))
        XCTAssertFalse(output.contains("key-value"))
        XCTAssertFalse(output.contains("private-session"))
        XCTAssertFalse(output.contains("cap-value"))
        XCTAssertFalse(output.contains("/Users/test"))
        XCTAssertTrue(output.contains("<redacted>") || output.contains("\\u003c"))
    }

    func testTextDiagnosticsRedactHeadersCredentialsCapabilitiesAndAnyUserPath() {
        let input = "Authorization: Bearer abc.def password=hunter2 " +
            "cookie=session-value capability=cap-123 /Users/other/private " +
            "ssh://name:pass@example.test/repo"
        let output = AgentDiagnosticRedactor.redact(text: input, homeDirectory: "/Users/test")
        for secret in ["abc.def", "hunter2", "session-value", "cap-123", "/Users/other", "name:pass"] {
            XCTAssertFalse(output.contains(secret), "failed to redact \(secret)")
        }
        XCTAssertTrue(output.contains("<redacted>"))
    }

    func testSocketChecksPeerUIDAuthenticatesEnvelopeAndUses0600Mode() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AgentRuntimePaths(
            runtimeDirectory: root.appendingPathComponent("runtime"),
            applicationSupportDirectory: root.appendingPathComponent("support")
        )
        try paths.prepare()
        let secret = try AgentInstallSecretStore(secretURL: paths.secretURL).loadOrCreate()
        let server = AgentHookSocketServer(paths: paths, expectedSecret: secret)
        let received = expectation(description: "authenticated hook delivered")
        try server.start { events, _ in
            guard let event = events.first else {
                XCTFail("Expected one authenticated hook event")
                return
            }
            XCTAssertEqual(event.provider, .claude)
            XCTAssertEqual(event.sessionID, "socket-session")
            received.fulfill()
        }
        defer { server.stop() }
        XCTAssertEqual(permissions(paths.socketURL), 0o600)
        XCTAssertTrue(AgentHookSocketServer.peerUIDAccepted(actual: getuid(), expected: getuid()))
        XCTAssertFalse(AgentHookSocketServer.peerUIDAccepted(actual: getuid() &+ 1, expected: getuid()))

        let payload: AgentJSONValue = .object([
            "session_id": .string("socket-session"),
            "hook_event_name": .string("SessionStart"),
            "cwd": .string("/tmp/repo")
        ])
        let envelope = AgentWireEnvelope(
            authentication: secret,
            provider: .claude,
            responseOwnerID: "hook-client",
            expectsResponse: false,
            payload: payload
        )
        let response = try send(envelope: envelope, socketURL: paths.socketURL)
        XCTAssertTrue(response.contains("\"ok\":true"))
        wait(for: [received], timeout: 2)
    }

    func testSocketRejectsWrongInstallSecret() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AgentRuntimePaths(
            runtimeDirectory: root.appendingPathComponent("runtime"),
            applicationSupportDirectory: root.appendingPathComponent("support")
        )
        try paths.prepare()
        let server = AgentHookSocketServer(paths: paths, expectedSecret: String(repeating: "a", count: 64))
        var delivered = false
        try server.start { _, _ in delivered = true }
        defer { server.stop() }

        let envelope = AgentWireEnvelope(
            authentication: String(repeating: "b", count: 64),
            provider: .claude,
            responseOwnerID: "hook-client",
            expectsResponse: false,
            payload: .object([
                "session_id": .string("rejected"),
                "hook_event_name": .string("SessionStart")
            ])
        )
        let response = try send(envelope: envelope, socketURL: paths.socketURL)
        XCTAssertTrue(response.contains("authentication_failed"))
        XCTAssertFalse(delivered)
    }

    private func permissions(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func send(envelope: AgentWireEnvelope, socketURL: URL) throws -> String {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        _ = socketURL.path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: 104) {
                    strlcpy($0, source, 104)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connected, 0)

        var data = try JSONEncoder().encode(envelope)
        data.append(0x0a)
        let written = data.withUnsafeBytes { raw in
            Darwin.write(fd, raw.baseAddress, raw.count)
        }
        XCTAssertEqual(written, data.count)

        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(fd, &bytes, bytes.count)
        XCTAssertGreaterThan(count, 0)
        return String(decoding: bytes.prefix(max(count, 0)), as: UTF8.self)
    }
}
