import Darwin
import Foundation

/// Temporary, narrowly scoped identities accepted only while importing or
/// replacing the pinned legacy Agent application. They are never emitted as
/// N1KO product identity and are scheduled for removal after two schemas.
public enum AgentLegacyIdentityAllowlist {
    public static let removalSchemaVersion = 4
    public static let bundleIdentifier = "com.wudanwu.PingIsland"
    public static let managedCommandMarkers = ["PingIslandBridge", "ping-island-bridge"]
    public static let managedPathMarkers = [
        "/ping-island.js", "/ping_island/", "/ping-island-openclaw", "ping-island-openclaw"
    ]

    public static func isLegacyManagedReference(_ value: String) -> Bool {
        managedCommandMarkers.contains(where: value.contains)
            || managedPathMarkers.contains(where: value.contains)
    }
}

public enum AgentHookLedgerState: String, Codable, Sendable {
    case staged
    case installed
    case alreadyInstalled
    case conflicted
    case rolledBack
    case removed
    case proofFailed
}

public struct AgentHookFileRecord: Codable, Equatable, Sendable {
    public let path: String
    public let backupPath: String
    public let originalExisted: Bool
    public let beforeHash: String
    public let stagedHash: String
    public let finalHash: String?
}

public struct AgentHookLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: String
    public let schemaVersion: Int
    public let state: AgentHookLedgerState
    public let createdAt: Date
    public let files: [AgentHookFileRecord]
    public let legacyReferencesRemoved: Int
    public let note: String?
}

public struct AgentHookMigrationLedger: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public var entries: [AgentHookLedgerEntry]

    public init(formatVersion: Int = 1, entries: [AgentHookLedgerEntry] = []) {
        self.formatVersion = formatVersion
        self.entries = entries
    }
}

public enum AgentHookInstallationError: Error, Equatable {
    case unknownProfile
    case invalidConfiguration(String)
    case conflictingOwner
    case concurrentModification(String)
    case downgradeBlocked(installed: Int, requested: Int)
    case proofFailed
    case rollbackUnavailable
}

public struct AgentHookInstallResult: Equatable, Sendable {
    public let profileID: String
    public let state: AgentHookLedgerState
    public let changedFiles: [String]
    public let legacyReferencesRemoved: Int
}

public struct AgentIntegrationLease: Codable, Equatable, Sendable {
    public let productIdentifier: String
    public let ownerID: String
    public let processID: Int32
    public let acquiredAt: Date

    public init(
        productIdentifier: String = "com.n1ko.state.agent",
        ownerID: String,
        processID: Int32 = getpid(),
        acquiredAt: Date = Date()
    ) {
        self.productIdentifier = productIdentifier
        self.ownerID = ownerID
        self.processID = processID
        self.acquiredAt = acquiredAt
    }
}

public enum AgentIntegrationLeaseResult: Equatable, Sendable {
    case acquired
    case alreadyOwned
    case blockedByLegacyApplication
    case blockedByAnotherOwner(String)
}

/// A per-user lease prevents a concurrently running legacy app or another
/// N1KO instance from alternately rewriting the same hook files.
public final class AgentIntegrationLeaseStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func acquire(
        _ lease: AgentIntegrationLease,
        runningBundleIdentifiers: Set<String>
    ) throws -> AgentIntegrationLeaseResult {
        if runningBundleIdentifiers.contains(AgentLegacyIdentityAllowlist.bundleIdentifier) {
            return .blockedByLegacyApplication
        }
        if let existing = try load() {
            if existing.ownerID == lease.ownerID { return .alreadyOwned }
            if processIsRunning(existing.processID) {
                return .blockedByAnotherOwner(existing.ownerID)
            }
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder.agentHook.encode(lease).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return .acquired
    }

    public func release(ownerID: String) throws {
        guard let existing = try load(), existing.ownerID == ownerID else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func load() throws -> AgentIntegrationLease? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder.agentHook.decode(
            AgentIntegrationLease.self,
            from: Data(contentsOf: fileURL)
        )
    }

    private func processIsRunning(_ processID: Int32) -> Bool {
        processID > 0 && (kill(processID, 0) == 0 || errno == EPERM)
    }
}

/// Transactional managed-hook writer. It stages N1KO entries beside any
/// recognized legacy entries, requires a successful ingress probe, verifies
/// that no file changed during the probe, and only then removes exact legacy
/// references. Every touched file receives an exact backup and ledger record.
public final class AgentManagedHookInstaller: @unchecked Sendable {
    public typealias Proof = (_ profile: AgentIntegrationProfile, _ bridgeCommand: String) -> Bool

    public let homeDirectory: URL
    public let bridgeURL: URL
    public let ledgerURL: URL
    public let backupDirectory: URL
    public let leaseStore: AgentIntegrationLeaseStore

    private let fileManager: FileManager

    public init(
        homeDirectory: URL,
        bridgeURL: URL,
        applicationSupportDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.bridgeURL = bridgeURL
        ledgerURL = applicationSupportDirectory.appendingPathComponent("Migration/hook-ledger.json")
        backupDirectory = applicationSupportDirectory.appendingPathComponent("Migration/HookBackups", isDirectory: true)
        leaseStore = AgentIntegrationLeaseStore(
            fileURL: applicationSupportDirectory.appendingPathComponent("Migration/integration-owner.json")
        )
        self.fileManager = fileManager
    }

    public func install(
        profileID: String,
        schemaVersion: Int,
        ownerID: String,
        runningBundleIdentifiers: Set<String> = [],
        takeOverLegacyReferences: Bool,
        proof: Proof
    ) throws -> AgentHookInstallResult {
        guard let profile = AgentIntegrationRegistry.profile(id: profileID) else {
            throw AgentHookInstallationError.unknownProfile
        }
        guard profile.managedHookAvailable else {
            throw AgentHookInstallationError.invalidConfiguration("runtime-only profile")
        }
        let lease = AgentIntegrationLease(ownerID: ownerID)
        switch try leaseStore.acquire(lease, runningBundleIdentifiers: runningBundleIdentifiers) {
        case .acquired, .alreadyOwned:
            break
        case .blockedByLegacyApplication:
            throw AgentHookInstallationError.conflictingOwner
        case .blockedByAnotherOwner:
            throw AgentHookInstallationError.conflictingOwner
        }

        let command = bridgeCommand(profile: profile, schemaVersion: schemaVersion)
        let targets = try stagedTargets(profile: profile, command: command, schemaVersion: schemaVersion)
        if let installedVersion = targets.compactMap(\.installedSchemaVersion).max(),
           installedVersion > schemaVersion {
            throw AgentHookInstallationError.downgradeBlocked(
                installed: installedVersion,
                requested: schemaVersion
            )
        }

        let hasLegacyReferences = targets.contains { target in
            if let object = try? JSONSerialization.jsonObject(with: target.originalData) {
                return Self.containsLegacyManagedReference(object)
            }
            return String(data: target.originalData, encoding: .utf8)
                .map(AgentLegacyIdentityAllowlist.isLegacyManagedReference) ?? false
        }
        if targets.allSatisfy({ $0.originalExisted && $0.originalData == $0.stagedData }),
           !takeOverLegacyReferences || !hasLegacyReferences {
            let entry = AgentHookLedgerEntry(
                id: UUID(), profileID: profileID, schemaVersion: schemaVersion,
                state: .alreadyInstalled, createdAt: Date(), files: [],
                legacyReferencesRemoved: 0, note: "idempotent-no-file-write"
            )
            try appendLedger(entry)
            return AgentHookInstallResult(
                profileID: profileID,
                state: .alreadyInstalled,
                changedFiles: [],
                legacyReferencesRemoved: 0
            )
        }

        let entryID = UUID()
        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var records: [AgentHookFileRecord] = []
        for target in targets {
            let backupURL = backupDirectory.appendingPathComponent("\(entryID.uuidString)-\(records.count).backup")
            try target.originalData.write(to: backupURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            try writePrivate(target.stagedData, to: target.url)
            records.append(AgentHookFileRecord(
                path: target.url.path,
                backupPath: backupURL.path,
                originalExisted: target.originalExisted,
                beforeHash: Self.hash(target.originalData),
                stagedHash: Self.hash(target.stagedData),
                finalHash: nil
            ))
        }

        try appendLedger(AgentHookLedgerEntry(
            id: entryID, profileID: profileID, schemaVersion: schemaVersion,
            state: .staged, createdAt: Date(), files: records,
            legacyReferencesRemoved: 0, note: nil
        ))

        guard proof(profile, command) else {
            try restore(records)
            try appendLedger(AgentHookLedgerEntry(
                id: entryID, profileID: profileID, schemaVersion: schemaVersion,
                state: .proofFailed, createdAt: Date(), files: records,
                legacyReferencesRemoved: 0, note: "probe did not reach N1KO ingress"
            ))
            throw AgentHookInstallationError.proofFailed
        }

        for record in records {
            let current = (try? Data(contentsOf: URL(fileURLWithPath: record.path))) ?? Data()
            guard Self.hash(current) == record.stagedHash else {
                try appendLedger(AgentHookLedgerEntry(
                    id: entryID, profileID: profileID, schemaVersion: schemaVersion,
                    state: .conflicted, createdAt: Date(), files: records,
                    legacyReferencesRemoved: 0, note: "file changed during probe"
                ))
                throw AgentHookInstallationError.concurrentModification(record.path)
            }
        }

        var removed = 0
        var finalRecords: [AgentHookFileRecord] = []
        for (index, target) in targets.enumerated() {
            let finalized: Data
            if takeOverLegacyReferences {
                let result = try removingLegacyReferences(from: target.stagedData, kind: target.kind)
                finalized = result.data
                removed += result.removed
            } else {
                finalized = target.stagedData
            }
            try writePrivate(finalized, to: target.url)
            let record = records[index]
            finalRecords.append(AgentHookFileRecord(
                path: record.path,
                backupPath: record.backupPath,
                originalExisted: record.originalExisted,
                beforeHash: record.beforeHash,
                stagedHash: record.stagedHash,
                finalHash: Self.hash(finalized)
            ))
        }

        try appendLedger(AgentHookLedgerEntry(
            id: entryID, profileID: profileID, schemaVersion: schemaVersion,
            state: .installed, createdAt: Date(), files: finalRecords,
            legacyReferencesRemoved: removed, note: nil
        ))
        return AgentHookInstallResult(
            profileID: profileID,
            state: .installed,
            changedFiles: finalRecords.map(\.path),
            legacyReferencesRemoved: removed
        )
    }

    public func rollback(entryID: UUID, ownerID: String) throws -> AgentHookInstallResult {
        let ledger = try loadLedger()
        guard let entry = ledger.entries.last(where: { $0.id == entryID }), !entry.files.isEmpty else {
            throw AgentHookInstallationError.rollbackUnavailable
        }
        for record in entry.files {
            guard let expected = record.finalHash else { continue }
            let current = (try? Data(contentsOf: URL(fileURLWithPath: record.path))) ?? Data()
            guard Self.hash(current) == expected else {
                throw AgentHookInstallationError.concurrentModification(record.path)
            }
        }
        try restore(entry.files)
        try appendLedger(AgentHookLedgerEntry(
            id: entry.id, profileID: entry.profileID, schemaVersion: entry.schemaVersion,
            state: .rolledBack, createdAt: Date(), files: entry.files,
            legacyReferencesRemoved: 0, note: "restored exact per-file backup"
        ))
        try leaseStore.release(ownerID: ownerID)
        return AgentHookInstallResult(
            profileID: entry.profileID,
            state: .rolledBack,
            changedFiles: entry.files.map(\.path),
            legacyReferencesRemoved: 0
        )
    }

    public func remove(profileID: String, schemaVersion: Int) throws -> AgentHookInstallResult {
        guard let profile = AgentIntegrationRegistry.profile(id: profileID) else {
            throw AgentHookInstallationError.unknownProfile
        }
        let targets = try stagedTargets(
            profile: profile,
            command: bridgeCommand(profile: profile, schemaVersion: schemaVersion),
            schemaVersion: schemaVersion,
            installing: false
        )
        let changedTargets = targets.filter { $0.originalData != $0.stagedData }
        let entryID = UUID()
        var records: [AgentHookFileRecord] = []
        if !changedTargets.isEmpty {
            try fileManager.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        for target in changedTargets {
            let backupURL = backupDirectory.appendingPathComponent(
                "\(entryID.uuidString)-\(records.count).backup"
            )
            try target.originalData.write(to: backupURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            try writePrivate(target.stagedData, to: target.url)
            records.append(AgentHookFileRecord(
                path: target.url.path,
                backupPath: backupURL.path,
                originalExisted: target.originalExisted,
                beforeHash: Self.hash(target.originalData),
                stagedHash: Self.hash(target.stagedData),
                finalHash: Self.hash(target.stagedData)
            ))
        }
        try appendLedger(AgentHookLedgerEntry(
            id: entryID, profileID: profileID, schemaVersion: schemaVersion,
            state: .removed, createdAt: Date(), files: records,
            legacyReferencesRemoved: 0, note: "removed only exact N1KO managed entries"
        ))
        return AgentHookInstallResult(
            profileID: profileID,
            state: .removed,
            changedFiles: records.map(\.path),
            legacyReferencesRemoved: 0
        )
    }

    public func loadLedger() throws -> AgentHookMigrationLedger {
        guard fileManager.fileExists(atPath: ledgerURL.path) else { return AgentHookMigrationLedger() }
        return try JSONDecoder.agentHook.decode(
            AgentHookMigrationLedger.self,
            from: Data(contentsOf: ledgerURL)
        )
    }

    public func bridgeCommand(profile: AgentIntegrationProfile, schemaVersion: Int) -> String {
        var arguments = [
            Self.shellQuote(bridgeURL.path),
            "--provider", Self.shellQuote(profile.provider.rawValue),
            "--profile", Self.shellQuote(profile.id),
            "--managed-by", "com.n1ko.state.agent",
            "--schema-version", String(schemaVersion)
        ]
        if profile.capabilities.contains(.inlineResponse) {
            arguments.append("--expects-response")
        }
        return arguments.joined(separator: " ")
    }

    private struct StagedTarget {
        let url: URL
        let kind: AgentHookInstallationKind
        let originalData: Data
        let stagedData: Data
        let originalExisted: Bool
        let installedSchemaVersion: Int?
    }

    private func stagedTargets(
        profile: AgentIntegrationProfile,
        command: String,
        schemaVersion: Int,
        installing: Bool = true
    ) throws -> [StagedTarget] {
        let configuredURL = profile.configurationURL(homeDirectory: homeDirectory)
        let primaryURL: URL
        switch profile.installationKind {
        case .pluginDirectory:
            primaryURL = configuredURL.appendingPathComponent(
                profile.provider == .hermes ? "__init__.py" : "index.ts"
            )
        case .hookDirectory:
            primaryURL = configuredURL.appendingPathComponent("handler.ts")
        default:
            primaryURL = configuredURL
        }
        let originalExisted = fileManager.fileExists(atPath: primaryURL.path)
        let original = (try? Data(contentsOf: primaryURL)) ?? Data()
        let staged = try updatedPrimaryData(
            original,
            profile: profile,
            command: command,
            schemaVersion: schemaVersion,
            installing: installing
        )
        var targets = [StagedTarget(
            url: primaryURL,
            kind: profile.installationKind,
            originalData: original,
            stagedData: staged,
            originalExisted: originalExisted,
            installedSchemaVersion: Self.managedSchemaVersion(in: original)
        )]
        for (name, data) in Self.managedSidecarFiles(
            profile: profile,
            schemaVersion: schemaVersion,
            installing: installing
        ) {
            let url = configuredURL.appendingPathComponent(name)
            let existed = fileManager.fileExists(atPath: url.path)
            let originalData = (try? Data(contentsOf: url)) ?? Data()
            let stagedData: Data
            if !installing,
               !Self.containsExactN1KOFileMarker(originalData, profileID: profile.id) {
                stagedData = originalData
            } else {
                stagedData = data
            }
            targets.append(StagedTarget(
                url: url,
                kind: profile.installationKind,
                originalData: originalData,
                stagedData: stagedData,
                originalExisted: existed,
                installedSchemaVersion: Self.managedSchemaVersion(in: originalData)
            ))
        }
        if let activationURL = profile.activationConfigurationURL(homeDirectory: homeDirectory) {
            let activationExists = fileManager.fileExists(atPath: activationURL.path)
            let activationOriginal = (try? Data(contentsOf: activationURL)) ?? Data()
            let activationStaged = try updatedActivationData(
                activationOriginal,
                profile: profile,
                pluginURL: primaryURL,
                installing: installing
            )
            targets.append(StagedTarget(
                url: activationURL,
                kind: .json,
                originalData: activationOriginal,
                stagedData: activationStaged,
                originalExisted: activationExists,
                installedSchemaVersion: Self.managedSchemaVersion(in: activationOriginal)
            ))
        }
        return targets
    }

    private func updatedPrimaryData(
        _ existing: Data,
        profile: AgentIntegrationProfile,
        command: String,
        schemaVersion: Int,
        installing: Bool
    ) throws -> Data {
        switch profile.installationKind {
        case .json:
            var root = try jsonObject(existing)
            if profile.protocolFamily == .copilot { root["version"] = 1 }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for event in profile.events {
                var entries = hooks[event.name] as? [Any] ?? []
                entries.removeAll { Self.containsN1KOManagedMarker($0, profileID: profile.id) }
                if installing {
                    if profile.protocolFamily == .copilot {
                        var entry: [String: Any] = [
                            "type": "command",
                            "bash": command + " --event " + Self.shellQuote(event.name),
                            "n1koManagedSchema": schemaVersion
                        ]
                        if let timeout = event.timeoutSeconds { entry["timeoutSec"] = timeout }
                        entries.append(entry)
                    } else {
                        var commandEntry: [String: Any] = [
                            "type": "command",
                            "command": command,
                            "n1koManagedSchema": schemaVersion
                        ]
                        if let timeout = event.timeoutSeconds { commandEntry["timeout"] = timeout }
                        for template in event.templates {
                            switch template {
                            case .plain:
                                entries.append(["hooks": [commandEntry]])
                            case .matcher(let matcher):
                                entries.append(["matcher": matcher, "hooks": [commandEntry]])
                            case .direct:
                                entries.append(commandEntry)
                            }
                        }
                    }
                }
                if entries.isEmpty { hooks.removeValue(forKey: event.name) }
                else { hooks[event.name] = entries }
            }
            root["hooks"] = hooks
            return try jsonData(root)
        case .toml:
            return Self.updatedManagedText(
                existing,
                block: profile.events.map { event in
                    var fields = [
                        "[[hooks]]",
                        "event = \"\(Self.tomlEscape(event.name))\"",
                        "command = \"\(Self.tomlEscape(command))\"",
                        "n1ko_managed_schema = \(schemaVersion)"
                    ]
                    if case .matcher(let matcher)? = event.templates.first {
                        fields.append("matcher = \"\(Self.tomlEscape(matcher))\"")
                    }
                    if let timeout = event.timeoutSeconds { fields.append("timeout = \(timeout)") }
                    return fields.joined(separator: "\n")
                }.joined(separator: "\n"),
                installing: installing
            )
        case .pluginFile, .pluginDirectory, .hookDirectory:
            guard installing else {
                return Self.containsExactN1KOFileMarker(existing, profileID: profile.id)
                    ? Data()
                    : existing
            }
            let source = Self.managedPluginSource(
                profile: profile,
                command: command,
                schemaVersion: schemaVersion
            )
            return Data(source.utf8)
        }
    }

    private func updatedActivationData(
        _ existing: Data,
        profile: AgentIntegrationProfile,
        pluginURL: URL,
        installing: Bool
    ) throws -> Data {
        var root = try jsonObject(existing)
        if profile.installationKind == .pluginFile {
            var plugins = root["plugin"] as? [String] ?? []
            let value = pluginURL.absoluteURL.absoluteString
            plugins.removeAll { $0 == value }
            if installing { plugins.append(value) }
            root["plugin"] = plugins
        } else if profile.installationKind == .hookDirectory {
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            var internalHooks = hooks["internal"] as? [String: Any] ?? [:]
            var entries = internalHooks["entries"] as? [String: Any] ?? [:]
            var entry = entries["n1ko-state"] as? [String: Any] ?? [:]
            entry["enabled"] = installing
            entries["n1ko-state"] = entry
            internalHooks["entries"] = entries
            if installing { internalHooks["enabled"] = true }
            hooks["internal"] = internalHooks
            root["hooks"] = hooks
        }
        return try jsonData(root)
    }

    private func removingLegacyReferences(
        from data: Data,
        kind: AgentHookInstallationKind
    ) throws -> (data: Data, removed: Int) {
        if kind == .toml {
            return Self.removingLegacyTOMLHooks(from: data)
        }
        guard kind == .json else { return (data, 0) }
        var root = try jsonObject(data)
        var removed = 0
        root = Self.removingLegacy(in: root, count: &removed) as? [String: Any] ?? root
        return (try jsonData(root), removed)
    }

    private static func removingLegacy(in value: Any, count: inout Int) -> Any? {
        if let string = value as? String {
            if AgentLegacyIdentityAllowlist.isLegacyManagedReference(string) {
                count += 1
                return nil
            }
            return string
        }
        if let array = value as? [Any] {
            let kept: [Any] = array.compactMap { nested -> Any? in
                if containsLegacyManagedReference(nested) {
                    count += 1
                    return nil
                }
                return removingLegacy(in: nested, count: &count)
            }
            return kept
        }
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, nested) in dictionary {
                if AgentLegacyIdentityAllowlist.isLegacyManagedReference(key) {
                    count += 1
                } else if let kept = removingLegacy(in: nested, count: &count) {
                    result[key] = kept
                }
            }
            return result
        }
        return value
    }

    private static func containsLegacyManagedReference(_ value: Any) -> Bool {
        if let string = value as? String {
            return AgentLegacyIdentityAllowlist.isLegacyManagedReference(string)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsLegacyManagedReference)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsLegacyManagedReference)
        }
        return false
    }

    private static func removingLegacyTOMLHooks(from data: Data) -> (data: Data, removed: Int) {
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var block: [String] = []
        var inHook = false
        var removed = 0

        func flushHook() {
            guard !block.isEmpty else { return }
            let value = block.joined(separator: "\n")
            if AgentLegacyIdentityAllowlist.isLegacyManagedReference(value) {
                removed += 1
            } else {
                output.append(contentsOf: block)
            }
            block.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[[hooks]]") {
                if inHook { flushHook() }
                inHook = true
                block = [line]
            } else if inHook, trimmed.hasPrefix("[") {
                flushHook()
                inHook = false
                output.append(line)
            } else if inHook {
                block.append(line)
            } else {
                output.append(line)
            }
        }
        if inHook { flushHook() }
        return (Data(output.joined(separator: "\n").utf8), removed)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentHookInstallationError.invalidConfiguration("invalid JSON")
        }
        return object
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if data.isEmpty {
            try? fileManager.removeItem(at: url)
            return
        }
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func restore(_ records: [AgentHookFileRecord]) throws {
        for record in records {
            let url = URL(fileURLWithPath: record.path)
            if record.originalExisted {
                let backup = try Data(contentsOf: URL(fileURLWithPath: record.backupPath))
                try writePrivate(backup, to: url)
            } else {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func appendLedger(_ entry: AgentHookLedgerEntry) throws {
        var ledger = try loadLedger()
        ledger.entries.append(entry)
        try fileManager.createDirectory(
            at: ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder.agentHook.encode(ledger).write(to: ledgerURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledgerURL.path)
    }

    private static func containsN1KOManagedMarker(_ value: Any, profileID: String) -> Bool {
        if let string = value as? String {
            return string.contains("com.n1ko.state.agent")
                && string.contains("--profile")
                && string.contains(profileID)
        }
        if let array = value as? [Any] {
            return array.contains { containsN1KOManagedMarker($0, profileID: profileID) }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains { containsN1KOManagedMarker($0, profileID: profileID) }
        }
        return false
    }

    private static func containsExactN1KOFileMarker(_ data: Data, profileID: String) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("com.n1ko.state.agent") && text.contains("profile \(profileID)")
    }

    private static func managedSchemaVersion(in data: Data) -> Int? {
        guard let text = String(data: data, encoding: .utf8),
              let range = text.range(of: #"--schema-version[ '\"]+([0-9]+)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(text[range])
        return match.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
    }

    private static func updatedManagedText(_ data: Data, block: String, installing: Bool) -> Data {
        let begin = "# BEGIN N1KO-STATE MANAGED AGENT HOOKS"
        let end = "# END N1KO-STATE MANAGED AGENT HOOKS"
        var text = String(data: data, encoding: .utf8) ?? ""
        if let start = text.range(of: begin),
           let finish = text.range(of: end, range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<finish.upperBound)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if installing {
            if !text.isEmpty { text += "\n\n" }
            text += "\(begin)\n\(block)\n\(end)\n"
        } else if !text.isEmpty {
            text += "\n"
        }
        return Data(text.utf8)
    }

    private static func managedPluginSource(
        profile: AgentIntegrationProfile,
        command: String,
        schemaVersion: Int
    ) -> String {
        let quotedCommand = javascriptString(command)
        let header = "N1KO-STATE managed Agent integration schema \(schemaVersion); com.n1ko.state.agent; profile \(profile.id)"
        switch profile.provider {
        case .hermes:
            let pythonCommand = javascriptString(command)
            return """
            # \(header)
            import json
            import subprocess

            N1KO_STATE_BRIDGE = \(pythonCommand)

            def _n1ko_state_forward(event_name, payload):
                body = dict(payload or {})
                body.setdefault("hook_event_name", event_name)
                subprocess.run(
                    ["/bin/sh", "-lc", N1KO_STATE_BRIDGE],
                    input=json.dumps(body).encode("utf-8"),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )

            def on_session_start(context): _n1ko_state_forward("SessionStart", context)
            def pre_llm_call(context): _n1ko_state_forward("UserPromptSubmit", context)
            def pre_tool_call(context): _n1ko_state_forward("PreToolUse", context)
            def post_tool_call(context): _n1ko_state_forward("PostToolUse", context)
            def post_llm_call(context): _n1ko_state_forward("Stop", context)
            def on_session_end(context): _n1ko_state_forward("SessionEnd", context)
            """
        case .pi:
            return """
            // \(header)
            import { spawn } from "node:child_process";
            const N1KO_STATE_BRIDGE = \(quotedCommand);
            function forward(eventName, payload = {}) {
              const child = spawn("/bin/sh", ["-lc", N1KO_STATE_BRIDGE], { stdio: ["pipe", "ignore", "ignore"] });
              child.stdin.end(JSON.stringify({ ...payload, hook_event_name: eventName }));
            }
            export default function n1koStateExtension(pi) {
              const events = ["session_start", "agent_start", "tool_call", "tool_result", "agent_end", "session_shutdown", "session_compact"];
              for (const name of events) pi.on(name, (event, ctx) => forward(name, { ...event, cwd: ctx?.cwd }));
            }
            """
        case .openCode:
            return """
            // \(header)
            import { spawn } from "node:child_process";
            const N1KO_STATE_BRIDGE = \(quotedCommand);
            function forward(payload) {
              const child = spawn("/bin/sh", ["-lc", N1KO_STATE_BRIDGE], { stdio: ["pipe", "ignore", "ignore"] });
              child.stdin.end(JSON.stringify(payload));
            }
            export const N1KOState = async () => ({
              event: async ({ event }) => forward({ ...event, hook_event_name: event?.type ?? "event" })
            });
            export default N1KOState;
            """
        case .openClaw:
            return """
            // \(header)
            import { spawn } from "node:child_process";
            const N1KO_STATE_BRIDGE = \(quotedCommand);
            export default async function n1koStateHook(event) {
              const child = spawn("/bin/sh", ["-lc", N1KO_STATE_BRIDGE], { stdio: ["pipe", "ignore", "ignore"] });
              child.stdin.end(JSON.stringify({ ...event, hook_event_name: event?.type ?? "event" }));
            }
            """
        default:
            return """
            // \(header)
            export const n1koStateBridge = \(quotedCommand);
            """
        }
    }

    private static func managedSidecarFiles(
        profile: AgentIntegrationProfile,
        schemaVersion: Int,
        installing: Bool
    ) -> [(String, Data)] {
        guard installing else {
            if profile.provider == .hermes { return [("plugin.yaml", Data())] }
            if profile.provider == .openClaw { return [("HOOK.md", Data())] }
            return []
        }
        let marker = "N1KO-STATE managed Agent integration schema \(schemaVersion); com.n1ko.state.agent; profile \(profile.id)"
        if profile.provider == .hermes {
            let yaml = """
            # \(marker)
            name: n1ko_state
            version: 1.0.0
            description: Forward Hermes Agent hooks to N1KO-STATE
            provides_hooks:
              - on_session_start
              - pre_llm_call
              - pre_tool_call
              - post_tool_call
              - post_llm_call
              - on_session_end
            """
            return [("plugin.yaml", Data(yaml.utf8))]
        }
        if profile.provider == .openClaw {
            let markdown = """
            ---
            name: n1ko-state
            description: "Forward OpenClaw internal events to N1KO-STATE"
            metadata: { "openclaw": { "events": ["command", "message", "session"] } }
            ---

            <!-- \(marker) -->
            """
            return [("HOOK.md", Data(markdown.utf8))]
        }
        return []
    }

    private static func hash(_ data: Data) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(format: "%016llx", value)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func tomlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func javascriptString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(text.dropFirst().dropLast())
    }
}

private extension JSONEncoder {
    static var agentHook: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var agentHook: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
