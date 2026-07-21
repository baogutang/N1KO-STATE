import Foundation
@testable import N1KOAgentCore
import XCTest

final class AgentManagedHookTests: XCTestCase {
    func testProofBeforeLegacyRemovalPreservesUnrelatedJSONAndBacksUp() throws {
        let context = try makeContext()
        let profile = try XCTUnwrap(AgentIntegrationRegistry.profile(id: "claude-hooks"))
        let configURL = profile.configurationURL(homeDirectory: context.home)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data(#"{"unrelated":{"keep":true},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/legacy/PingIslandBridge --source claude"}]},{"hooks":[{"type":"command","command":"/Users/me/custom-hook"}]}]}}"#.utf8)
        try original.write(to: configURL)

        var proofObservedBoth = false
        let result = try context.installer.install(
            profileID: profile.id,
            schemaVersion: 1,
            ownerID: "owner-proof",
            takeOverLegacyReferences: true
        ) { _, _ in
            let staged = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            proofObservedBoth = staged.contains("PingIslandBridge")
                && staged.contains("com.n1ko.state.agent")
            return true
        }

        XCTAssertTrue(proofObservedBoth)
        XCTAssertEqual(result.state, .installed)
        XCTAssertEqual(result.legacyReferencesRemoved, 1)
        let final = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(final.contains("PingIslandBridge"))
        let finalJSON = try jsonObject(at: configURL)
        let finalHooks = try XCTUnwrap(finalJSON["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(finalHooks["SessionStart"] as? [[String: Any]])
        XCTAssertTrue(sessionStart.contains { entry in
            let nested = entry["hooks"] as? [[String: Any]]
            return nested?.contains { $0["command"] as? String == "/Users/me/custom-hook" } == true
        })
        XCTAssertTrue(final.contains("\"keep\" : true"))

        let installed = try XCTUnwrap(context.installer.loadLedger().entries.last {
            $0.state == .installed
        })
        let record = try XCTUnwrap(installed.files.first)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: record.backupPath)), original)
        let permissions = try FileManager.default.attributesOfItem(atPath: record.backupPath)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRepeatedInstallUpgradeDowngradeRemovalAndRollback() throws {
        let context = try makeContext()
        let profile = try XCTUnwrap(AgentIntegrationRegistry.profile(id: "gemini-hooks"))
        let configURL = profile.configurationURL(homeDirectory: context.home)
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"custom":7,"hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"custom-end"}]}]}}"#.utf8)
        try original.write(to: configURL)

        XCTAssertEqual(try context.installer.install(
            profileID: profile.id, schemaVersion: 1, ownerID: "owner-cycle",
            takeOverLegacyReferences: false, proof: { _, _ in true }
        ).state, .installed)

        var repeatedProofCalls = 0
        XCTAssertEqual(try context.installer.install(
            profileID: profile.id, schemaVersion: 1, ownerID: "owner-cycle",
            takeOverLegacyReferences: false,
            proof: { _, _ in repeatedProofCalls += 1; return true }
        ).state, .alreadyInstalled)
        XCTAssertEqual(repeatedProofCalls, 0)

        XCTAssertEqual(try context.installer.install(
            profileID: profile.id, schemaVersion: 2, ownerID: "owner-cycle",
            takeOverLegacyReferences: false, proof: { _, _ in true }
        ).state, .installed)
        XCTAssertThrowsError(try context.installer.install(
            profileID: profile.id, schemaVersion: 1, ownerID: "owner-cycle",
            takeOverLegacyReferences: false, proof: { _, _ in true }
        )) { error in
            XCTAssertEqual(
                error as? AgentHookInstallationError,
                .downgradeBlocked(installed: 2, requested: 1)
            )
        }

        let installedEntry = try XCTUnwrap(context.installer.loadLedger().entries.last {
            $0.state == .installed && $0.schemaVersion == 2
        })
        XCTAssertEqual(try context.installer.rollback(
            entryID: installedEntry.id,
            ownerID: "owner-cycle"
        ).state, .rolledBack)
        XCTAssertTrue(try String(contentsOf: configURL, encoding: .utf8).contains("schema-version 1"))

        XCTAssertEqual(try context.installer.remove(
            profileID: profile.id,
            schemaVersion: 2
        ).state, .removed)
        let removed = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(removed.contains("custom-end"))
        XCTAssertTrue(removed.contains("\"custom\" : 7"))
        XCTAssertFalse(removed.contains("com.n1ko.state.agent"))
        let removalEntry = try XCTUnwrap(context.installer.loadLedger().entries.last {
            $0.state == .removed
        })
        XCTAssertFalse(removalEntry.files.isEmpty)
        XCTAssertTrue(removalEntry.files.allSatisfy { !$0.backupPath.isEmpty })
    }

    func testProofFailureRestoresExactFileAndConcurrentEditIsNeverOverwritten() throws {
        do {
            let context = try makeContext()
            let profile = try XCTUnwrap(AgentIntegrationRegistry.profile(id: "qwen-code-hooks"))
            let url = profile.configurationURL(homeDirectory: context.home)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = Data(#"{"user":"exact"}"#.utf8)
            try original.write(to: url)
            XCTAssertThrowsError(try context.installer.install(
                profileID: profile.id, schemaVersion: 1, ownerID: "owner-fail",
                takeOverLegacyReferences: false, proof: { _, _ in false }
            )) { error in
                XCTAssertEqual(error as? AgentHookInstallationError, .proofFailed)
            }
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertEqual(try context.installer.loadLedger().entries.last?.state, .proofFailed)
        }

        do {
            let context = try makeContext()
            let profile = try XCTUnwrap(AgentIntegrationRegistry.profile(id: "cursor-hooks"))
            let url = profile.configurationURL(homeDirectory: context.home)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
            let external = Data(#"{"external":"changed-during-proof"}"#.utf8)
            XCTAssertThrowsError(try context.installer.install(
                profileID: profile.id, schemaVersion: 1, ownerID: "owner-conflict",
                takeOverLegacyReferences: false,
                proof: { _, _ in try? external.write(to: url); return true }
            )) { error in
                guard case .concurrentModification(let path) = error as? AgentHookInstallationError else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertEqual(path, url.path)
            }
            XCTAssertEqual(try Data(contentsOf: url), external)
            XCTAssertEqual(try context.installer.loadLedger().entries.last?.state, .conflicted)
        }
    }

    func testCoexistenceLeaseBlocksLegacyAndAnotherLiveOwner() throws {
        let context = try makeContext()
        XCTAssertThrowsError(try context.installer.install(
            profileID: "claude-hooks", schemaVersion: 1, ownerID: "owner-a",
            runningBundleIdentifiers: [AgentLegacyIdentityAllowlist.bundleIdentifier],
            takeOverLegacyReferences: true, proof: { _, _ in true }
        )) { error in
            XCTAssertEqual(error as? AgentHookInstallationError, .conflictingOwner)
        }

        _ = try context.installer.install(
            profileID: "claude-hooks", schemaVersion: 1, ownerID: "owner-a",
            takeOverLegacyReferences: false, proof: { _, _ in true }
        )
        XCTAssertThrowsError(try context.installer.install(
            profileID: "claude-hooks", schemaVersion: 1, ownerID: "owner-b",
            takeOverLegacyReferences: false, proof: { _, _ in true }
        )) { error in
            XCTAssertEqual(error as? AgentHookInstallationError, .conflictingOwner)
        }
    }

    func testAllManagedProfilesInstallN1KOOwnedShapesAndRuntimeProfilesRejectWrites() throws {
        let context = try makeContext()
        for profile in AgentIntegrationRegistry.profiles where profile.managedHookAvailable {
            let result = try context.installer.install(
                profileID: profile.id,
                schemaVersion: 1,
                ownerID: "owner-matrix",
                takeOverLegacyReferences: false,
                proof: { _, _ in true }
            )
            XCTAssertEqual(result.state, .installed, profile.id)
            let primary = primaryURL(profile: profile, home: context.home)
            let text = try String(contentsOf: primary, encoding: .utf8)
            XCTAssertTrue(text.contains("com.n1ko.state.agent"), profile.id)
            XCTAssertTrue(text.contains(profile.id), profile.id)
            XCTAssertFalse(text.lowercased().contains("ping island"), profile.id)
        }

        let copilot = try jsonObject(
            at: AgentIntegrationRegistry.profile(id: "copilot-hooks")!.configurationURL(homeDirectory: context.home)
        )
        XCTAssertEqual(copilot["version"] as? Int, 1)
        let copilotHooks = try XCTUnwrap(copilot["hooks"] as? [String: Any])
        let firstCopilot = try XCTUnwrap((copilotHooks["sessionStart"] as? [[String: Any]])?.first)
        XCTAssertNotNil(firstCopilot["bash"])
        XCTAssertNil(firstCopilot["command"])

        let cursor = try jsonObject(
            at: AgentIntegrationRegistry.profile(id: "cursor-hooks")!.configurationURL(homeDirectory: context.home)
        )
        let cursorHooks = try XCTUnwrap(cursor["hooks"] as? [String: Any])
        let direct = try XCTUnwrap((cursorHooks["beforeSubmitPrompt"] as? [[String: Any]])?.first)
        XCTAssertNotNil(direct["command"])
        XCTAssertNil(direct["hooks"])

        let kimi = try String(
            contentsOf: AgentIntegrationRegistry.profile(id: "kimi-hooks")!.configurationURL(homeDirectory: context.home),
            encoding: .utf8
        )
        XCTAssertTrue(kimi.contains("[[hooks]]"))
        XCTAssertTrue(kimi.contains("event = \"SessionStart\""))

        let hermes = AgentIntegrationRegistry.profile(id: "hermes-hooks")!.configurationURL(homeDirectory: context.home)
        XCTAssertTrue(FileManager.default.fileExists(atPath: hermes.appendingPathComponent("plugin.yaml").path))
        let openClaw = AgentIntegrationRegistry.profile(id: "openclaw-hooks")!.configurationURL(homeDirectory: context.home)
        XCTAssertTrue(FileManager.default.fileExists(atPath: openClaw.appendingPathComponent("HOOK.md").path))

        for profile in AgentIntegrationRegistry.profiles where !profile.managedHookAvailable {
            XCTAssertThrowsError(try context.installer.install(
                profileID: profile.id, schemaVersion: 1, ownerID: "owner-matrix",
                takeOverLegacyReferences: false, proof: { _, _ in true }
            )) { error in
                XCTAssertEqual(
                    error as? AgentHookInstallationError,
                    .invalidConfiguration("runtime-only profile")
                )
            }
        }
    }

    func testKimiTakeoverRemovesOnlyLegacyTOMLHookBlock() throws {
        let context = try makeContext()
        let profile = try XCTUnwrap(AgentIntegrationRegistry.profile(id: "kimi-hooks"))
        let url = profile.configurationURL(homeDirectory: context.home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = """
        model = "kimi"

        [[hooks]]
        event = "SessionStart"
        command = "/old/ping-island-bridge --source kimi"

        [[hooks]]
        event = "SessionEnd"
        command = "/Users/me/custom-kimi-hook"
        """
        try Data(original.utf8).write(to: url)
        let result = try context.installer.install(
            profileID: profile.id, schemaVersion: 1, ownerID: "owner-kimi",
            takeOverLegacyReferences: true, proof: { _, _ in true }
        )
        XCTAssertEqual(result.legacyReferencesRemoved, 1)
        let final = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(final.contains("ping-island-bridge"))
        XCTAssertTrue(final.contains("custom-kimi-hook"))
        XCTAssertTrue(final.contains("model = \"kimi\""))
    }

    func testRemovalAndRollbackNeverOverwriteConcurrentUserEdits() throws {
        do {
            let context = try makeContext()
            let profile = try XCTUnwrap(AgentIntegrationRegistry.profile(id: "opencode-hooks"))
            _ = try context.installer.install(
                profileID: profile.id, schemaVersion: 1, ownerID: "owner-plugin-user",
                takeOverLegacyReferences: false, proof: { _, _ in true }
            )
            let pluginURL = primaryURL(profile: profile, home: context.home)
            let replacement = Data("export default function userPlugin() {}\n".utf8)
            try replacement.write(to: pluginURL)
            _ = try context.installer.remove(profileID: profile.id, schemaVersion: 1)
            XCTAssertEqual(try Data(contentsOf: pluginURL), replacement)
        }

        do {
            let context = try makeContext()
            let profile = try XCTUnwrap(AgentIntegrationRegistry.profile(id: "claude-hooks"))
            _ = try context.installer.install(
                profileID: profile.id, schemaVersion: 1, ownerID: "owner-rollback-conflict",
                takeOverLegacyReferences: false, proof: { _, _ in true }
            )
            let entry = try XCTUnwrap(context.installer.loadLedger().entries.last {
                $0.state == .installed
            })
            let url = profile.configurationURL(homeDirectory: context.home)
            let external = Data(#"{"external":"new-owner"}"#.utf8)
            try external.write(to: url)
            XCTAssertThrowsError(try context.installer.rollback(
                entryID: entry.id,
                ownerID: "owner-rollback-conflict"
            )) { error in
                guard case .concurrentModification(let path) = error as? AgentHookInstallationError else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertEqual(path, url.path)
            }
            XCTAssertEqual(try Data(contentsOf: url), external)
        }
    }

    private struct Context {
        let root: URL
        let home: URL
        let installer: AgentManagedHookInstaller
    }

    private func makeContext() throws -> Context {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-hook-tests-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Context(
            root: root,
            home: home,
            installer: AgentManagedHookInstaller(
                homeDirectory: home,
                bridgeURL: root.appendingPathComponent("n1ko-agent-bridge"),
                applicationSupportDirectory: support
            )
        )
    }

    private func primaryURL(profile: AgentIntegrationProfile, home: URL) -> URL {
        let configured = profile.configurationURL(homeDirectory: home)
        switch profile.installationKind {
        case .pluginDirectory:
            return configured.appendingPathComponent(profile.provider == .hermes ? "__init__.py" : "index.ts")
        case .hookDirectory:
            return configured.appendingPathComponent("handler.ts")
        default:
            return configured
        }
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
