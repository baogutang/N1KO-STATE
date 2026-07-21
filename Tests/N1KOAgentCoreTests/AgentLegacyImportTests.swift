import Foundation
@testable import N1KOAgentCore
import XCTest

final class AgentLegacyImportTests: XCTestCase {
    func testDiscoveryAndImportRequireAuthorizationAndExcludeTransientDefaults() throws {
        let root = try makeRoot()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let associationURL = home.appendingPathComponent(
            "Library/Application Support/PingIsland/session-associations.json"
        )
        let usageURL = home.appendingPathComponent(".ping-island/usage/agent-usage.json")
        let cacheURL = home.appendingPathComponent(".ping-island/cache/claude-usage.json")
        for url in [associationURL, usageURL, cacheURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try Data(#"{"qwen:external-1":{"provider":"qwen","sessionId":"real-1"}}"#.utf8)
            .write(to: associationURL)
        try Data(#"{"buckets":{"2026-07-16":{"tokenTotals":{"input":100,"cachedInput":20,"output":40}}}}"#.utf8)
            .write(to: usageURL)
        try Data(#"{"inputTokens":10,"cachedInputTokens":2,"outputTokens":4}"#.utf8)
            .write(to: cacheURL)

        let service = AgentLegacyImportService(homeDirectory: home) {
            [
                "HookInstaller.preferredTargets.v1": ["qwen-hooks", "gemini-hooks"],
                "windowExpanded": true,
                "remotePassword": "must-not-import"
            ]
        }
        let discovery = service.discover()
        XCTAssertTrue(discovery.hasDefaultsDomain)
        XCTAssertTrue(discovery.hasAssociations)
        XCTAssertTrue(discovery.hasUsage)
        XCTAssertTrue(discovery.hasUsageCache)

        XCTAssertThrowsError(try service.load(authorization: .denied)) { error in
            XCTAssertEqual(error as? AgentLegacyImportError, .authorizationRequired)
        }

        let payload = try service.load(authorization: .approved)
        XCTAssertEqual(payload.associations["qwen:external-1"], AgentSessionKey(
            provider: .qwen,
            sessionID: "real-1"
        ))
        XCTAssertEqual(payload.preferredProfileIDs, ["qwen-code-hooks", "gemini-hooks"])
        XCTAssertEqual(payload.usage[.legacyImport], AgentUsage(
            inputTokens: 110,
            cachedInputTokens: 22,
            outputTokens: 44
        ))
        XCTAssertEqual(payload.sourceFiles.count, 4)
        XCTAssertFalse(payload.sourceFiles.contains(where: { $0.contains("window") || $0.contains("password") }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: associationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: usageURL.path))
    }

    func testStoreImportIsIdempotentAndNeverOverwritesNewAssociation() {
        let store = AgentSessionStore()
        _ = store.associate(provider: .qwen, externalID: "external-1", sessionID: "new-choice")
        let before = store.snapshot().generation
        let payload = AgentLegacyImportPayload(
            associations: [
                "qwen:external-1": AgentSessionKey(provider: .qwen, sessionID: "legacy-choice"),
                "gemini:external-2": AgentSessionKey(provider: .gemini, sessionID: "imported-choice")
            ],
            usage: [.legacyImport: AgentUsage(inputTokens: 50, outputTokens: 20)],
            preferredProfileIDs: ["gemini-hooks"],
            sourceFiles: ["fixture"]
        )
        let first = store.importLegacy(associations: payload.associations, usage: payload.usage)
        XCTAssertGreaterThan(first.generation, before)
        XCTAssertEqual(store.resolvedSessionID(provider: .qwen, externalID: "external-1"), "new-choice")
        XCTAssertEqual(store.resolvedSessionID(provider: .gemini, externalID: "external-2"), "imported-choice")
        XCTAssertEqual(first.usage.byProvider[.legacyImport]?.totalTokens, 70)

        let second = store.importLegacy(associations: payload.associations, usage: payload.usage)
        XCTAssertEqual(second.generation, first.generation)
        XCTAssertEqual(second.usage, first.usage)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-legacy-import-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
