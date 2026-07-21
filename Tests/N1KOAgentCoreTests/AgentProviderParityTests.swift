import Foundation
@testable import N1KOAgentCore
import XCTest

final class AgentProviderParityTests: XCTestCase {
    private struct Fixture: Decodable {
        let profileID: String
        let provider: AgentProvider
        let payload: [String: AgentJSONValue]
    }

    func testEveryAuditedProfileHasAReproducibleIngressFixture() throws {
        let data = try Data(contentsOf: fixtureURL())
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)

        XCTAssertEqual(fixtures.count, AgentIntegrationRegistry.profiles.count)
        XCTAssertEqual(Set(fixtures.map(\.profileID)), Set(AgentIntegrationRegistry.profiles.map(\.id)))
        XCTAssertEqual(Set(fixtures.map(\.provider)), Set(AgentIntegrationRegistry.profiles.map(\.provider)))

        for fixture in fixtures {
            let payloadData = try JSONEncoder().encode(AgentJSONValue.object(fixture.payload))
            let events = try AgentManagedHookParser.parse(
                payloadData,
                provider: fixture.provider,
                responseOwnerID: "fixture-owner"
            )
            XCTAssertEqual(events.count, 1, fixture.profileID)
            XCTAssertEqual(events.first?.provider, fixture.provider, fixture.profileID)
            XCTAssertFalse(events.first?.sessionID.isEmpty ?? true, fixture.profileID)
        }
    }

    func testRegistrySeparatesManagedHookAndRuntimeOnlyClients() {
        XCTAssertEqual(AgentIntegrationRegistry.profiles.count, 21)
        XCTAssertEqual(
            Set(AgentIntegrationRegistry.profiles.filter { !$0.managedHookAvailable }.map(\.id)),
            ["trae-runtime", "jetbrains-runtime"]
        )
        XCTAssertTrue(AgentIntegrationRegistry.profiles
            .filter(\.managedHookAvailable)
            .allSatisfy { $0.capabilities.contains(.ingress) })
        XCTAssertEqual(
            AgentIntegrationRegistry.profile(provider: .qwen)?.id,
            "qwen-code-hooks"
        )
        XCTAssertEqual(
            AgentIntegrationRegistry.profile(provider: .qoderCN)?.bundleIdentifiers,
            ["com.aliyun.lingma.ide"]
        )
        XCTAssertTrue(
            AgentIntegrationRegistry.profile(provider: .qoderCNCLI)?
                .capabilities.contains(.inlineResponse) == true
        )
    }

    func testProviderAwareApprovalRetainsResponseOwner() throws {
        let payload = Data(#"{"session_id":"qwen-approval","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_use_id":"req-1"}"#.utf8)
        let event = try XCTUnwrap(AgentManagedHookParser.parse(
            payload,
            provider: .qwen,
            responseOwnerID: "owner-qwen"
        ).first)
        XCTAssertEqual(event.provider, .qwen)
        XCTAssertEqual(event.kind, .approvalRequested)
        XCTAssertEqual(event.responseOwnerID, "owner-qwen")
        XCTAssertEqual(event.requestID, "req-1")
    }

    func testNavigationContextNormalizesTerminalTMUXAndRemoteHints() throws {
        let payload = Data(#"{"session_id":"qwen-nav","hook_event_name":"SessionStart","terminal_bundle_identifier":"com.apple.Terminal","tmux_session":"agent","tmux_window":"2","tmux_pane":"1","remote_host":"build.example.test"}"#.utf8)
        let event = try XCTUnwrap(AgentManagedHookParser.parse(
            payload,
            provider: .qwen,
            responseOwnerID: "owner"
        ).first)
        XCTAssertEqual(event.navigation?.terminalBundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(event.navigation?.tmuxTarget?.selector, "agent:2:1")
        XCTAssertEqual(event.navigation?.remoteHost, "build.example.test")

        let store = AgentSessionStore()
        let snapshot = store.process(event)
        XCTAssertEqual(snapshot.sessions.first?.navigation, event.navigation)
    }

    func testTMUXFollowUpPlanUsesLiteralTextSeparateEnterAndCapabilityGate() throws {
        let target = try AgentTMUXTarget(session: "agent", window: "2", pane: "1")
        XCTAssertThrowsError(try AgentTMUXMessagePlan(
            target: target,
            message: "continue",
            policy: AgentCapabilityPolicy()
        )) { error in
            XCTAssertEqual(error as? AgentCapabilityError, .disabled(.tmux))
        }

        let plan = try AgentTMUXMessagePlan(
            target: target,
            message: "  continue with $HOME && `safe`  ",
            policy: AgentCapabilityPolicy(enabled: [.tmux])
        )
        XCTAssertEqual(plan.executableURL.path, "/usr/bin/tmux")
        XCTAssertEqual(
            plan.textArguments,
            ["send-keys", "-t", "agent:2:1", "-l", "continue with $HOME && `safe`"]
        )
        XCTAssertEqual(plan.enterArguments, ["send-keys", "-t", "agent:2:1", "Enter"])
        XCTAssertThrowsError(try AgentTMUXMessagePlan(
            target: target,
            message: "\0",
            policy: AgentCapabilityPolicy(enabled: [.tmux])
        )) { error in
            XCTAssertEqual(error as? AgentCapabilityError, .invalidMessage)
        }
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Agent/wp5-provider-events.json")
    }
}
