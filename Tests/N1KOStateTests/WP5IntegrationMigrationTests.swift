import Foundation
@testable import N1KOAgentCore
@testable import N1KOState
import XCTest

final class WP5IntegrationMigrationTests: XCTestCase {
    func testPreferenceMigrationBacksUpBeforeMutationAndIsIdempotent() throws {
        let suiteName = "com.n1ko.state.tests.\(UUID().uuidString)"
        let previousSuiteName = "com.n1ko.state.tests.previous.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let previous = try XCTUnwrap(UserDefaults(suiteName: previousSuiteName))
        defaults.removePersistentDomain(forName: suiteName)
        previous.removePersistentDomain(forName: previousSuiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            previous.removePersistentDomain(forName: previousSuiteName)
        }

        defaults.set(1.0, forKey: "refreshInterval")
        defaults.set("expanded", forKey: "presentationStyle")
        previous.set(9.0, forKey: "refreshInterval")
        previous.set("zh-Hans", forKey: "language")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-settings-migration-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let service = SettingsMigrationService(
            defaults: defaults,
            domainName: suiteName,
            previousDefaults: previous,
            migrationDirectory: directory,
            now: { date }
        )

        let result = try service.migrate()
        guard case .migrated(let schema, let backupPath) = result else {
            return XCTFail("expected migration")
        }
        XCTAssertEqual(schema, SettingsMigrationService.currentSchemaVersion)
        XCTAssertEqual(defaults.double(forKey: "refreshInterval"), 1.0)
        XCTAssertEqual(defaults.string(forKey: "language"), "zh-Hans")
        XCTAssertNil(defaults.object(forKey: "presentationStyle"))
        XCTAssertTrue(defaults.bool(forKey: "didMigrateV1"))
        XCTAssertEqual(
            defaults.integer(forKey: "settings.schemaVersion"),
            SettingsMigrationService.currentSchemaVersion
        )

        let backupURL = URL(fileURLWithPath: backupPath)
        let backupData = try Data(contentsOf: backupURL)
        let backup = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: backupData, options: [], format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(backup["refreshInterval"] as? Double, 1.0)
        XCTAssertEqual(backup["presentationStyle"] as? String, "expanded")
        XCTAssertNil(backup["language"])
        XCTAssertEqual(try permissions(backupURL), 0o600)
        XCTAssertEqual(try permissions(directory), 0o700)

        let ledger = try service.loadLedger()
        let ledgerURL = directory.appendingPathComponent("preferences-ledger.json")
        XCTAssertEqual(try permissions(ledgerURL), 0o600)
        XCTAssertEqual(ledger.installedSchemaVersion, SettingsMigrationService.currentSchemaVersion)
        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries.first?.completedAt, date)

        XCTAssertEqual(
            try service.migrate(),
            .alreadyCurrent(schemaVersion: SettingsMigrationService.currentSchemaVersion)
        )
        XCTAssertEqual(try Data(contentsOf: backupURL), backupData)
        XCTAssertEqual(try service.loadLedger().entries.count, 1)
    }

    func testCapabilityPlansAreOffByDefaultAndRejectUnsafeTargets() throws {
        let disabled = AgentCapabilityPolicy()
        XCTAssertThrowsError(try disabled.require(.terminalFocus)) { error in
            XCTAssertEqual(error as? AgentCapabilityError, .disabled(.terminalFocus))
        }
        XCTAssertThrowsError(try AgentTMUXTarget(session: "safe;rm")) { error in
            XCTAssertEqual(error as? AgentCapabilityError, .invalidTMUXTarget)
        }
        let tmux = try AgentTMUXTarget(session: "work", window: "2", pane: "1")
        XCTAssertEqual(tmux.selector, "work:2:1")
        XCTAssertEqual(tmux.focusArguments, ["select-pane", "-t", "work:2:1"])

        XCTAssertThrowsError(try AgentRemoteEndpoint(
            host: "host;rm", user: "n1ko", hostKeyFingerprint: "SHA256:1234567890123456"
        )) { error in
            XCTAssertEqual(error as? AgentCapabilityError, .invalidRemoteHost)
        }
        let endpoint = try AgentRemoteEndpoint(
            host: "agent.example.test",
            user: "n1ko",
            port: 2222,
            hostKeyFingerprint: "SHA256:abcdefghijklmnopqrstuv"
        )
        XCTAssertThrowsError(try AgentRemoteCommandPlan(
            endpoint: endpoint,
            remoteArguments: ["/home/n1ko/n1ko-agent-bridge"],
            policy: disabled
        )) { error in
            XCTAssertEqual(error as? AgentCapabilityError, .disabled(.remoteSSH))
        }
        let plan = try AgentRemoteCommandPlan(
            endpoint: endpoint,
            remoteArguments: ["/home/n1ko/.n1ko-state/bin/n1ko-agent-bridge", "--mode", "attach"],
            policy: AgentCapabilityPolicy(enabled: [.remoteSSH])
        )
        XCTAssertEqual(plan.executableURL.path, "/usr/bin/ssh")
        XCTAssertTrue(plan.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(plan.arguments.contains("n1ko@agent.example.test"))
        XCTAssertFalse(plan.arguments.joined(separator: " ").lowercased().contains("ping"))
    }

    func testUpdateInstallWaitsForActiveAgentAndResumesOnce() {
        let store = AgentSessionStore()
        let active = store.process(AgentIngressEvent(
            provider: .gemini,
            sessionID: "update-session",
            kind: .processing
        ))
        let gate = AgentUpdateDeferralGate()
        var installCalls = 0
        XCTAssertTrue(gate.postponeIfNeeded(snapshot: active) { installCalls += 1 })
        XCTAssertEqual(installCalls, 0)

        let completed = store.process(AgentIngressEvent(
            provider: .gemini,
            sessionID: "update-session",
            kind: .completed,
            timestamp: Date().addingTimeInterval(1)
        ))
        gate.snapshotDidChange(completed)
        gate.snapshotDidChange(completed)
        XCTAssertEqual(installCalls, 1)
        XCTAssertFalse(gate.postponeIfNeeded(snapshot: completed) { installCalls += 1 })
    }

    func testSymbolicCompanionsUseSystemSymbolsOnly() {
        for provider in AgentProvider.allCases where provider != .legacyImport {
            let descriptor = AgentSymbolicCompanionDescriptor(provider: provider)
            XCTAssertFalse(descriptor.systemSymbolName.isEmpty)
            XCTAssertFalse(descriptor.systemSymbolName.contains("/"))
            XCTAssertFalse(descriptor.systemSymbolName.lowercased().contains("ping"))
        }
    }

    private func permissions(_ url: URL) throws -> Int {
        let value = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        return value.intValue
    }
}
