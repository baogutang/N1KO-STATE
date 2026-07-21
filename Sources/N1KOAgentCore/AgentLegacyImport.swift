import Foundation

public enum AgentLegacyImportAuthorization: Sendable {
    case denied
    case approved
}

public enum AgentLegacyImportError: Error, Equatable {
    case authorizationRequired
    case invalidAssociations
    case invalidUsage
}

public struct AgentLegacyImportDiscovery: Equatable, Sendable {
    public let hasDefaultsDomain: Bool
    public let hasAssociations: Bool
    public let hasUsage: Bool
    public let hasUsageCache: Bool

    public var hasImportableData: Bool {
        hasDefaultsDomain || hasAssociations || hasUsage || hasUsageCache
    }
}

public struct AgentLegacyImportPayload: Equatable, Sendable {
    public let associations: [String: AgentSessionKey]
    public let usage: [AgentProvider: AgentUsage]
    public let preferredProfileIDs: Set<String>
    public let sourceFiles: [String]

    public init(
        associations: [String: AgentSessionKey],
        usage: [AgentProvider: AgentUsage],
        preferredProfileIDs: Set<String> = [],
        sourceFiles: [String]
    ) {
        self.associations = associations
        self.usage = usage
        self.preferredProfileIDs = preferredProfileIDs
        self.sourceFiles = sourceFiles
    }
}

/// Read-only optional import. Source files are never edited or removed, and no
/// transient window/expansion preference is imported. The caller must present
/// authorization and pass `.approved` explicitly.
public struct AgentLegacyImportService {
    public let associationsURL: URL
    public let usageURL: URL
    public let usageCacheURLs: [URL]
    public let legacyDefaultsDomain: () -> [String: Any]?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        legacyDefaultsDomain: @escaping () -> [String: Any]? = {
            UserDefaults.standard.persistentDomain(
                forName: AgentLegacyIdentityAllowlist.bundleIdentifier
            )
        }
    ) {
        associationsURL = homeDirectory
            .appendingPathComponent("Library/Application Support/PingIsland", isDirectory: true)
            .appendingPathComponent("session-associations.json")
        usageURL = homeDirectory
            .appendingPathComponent(".ping-island/usage", isDirectory: true)
            .appendingPathComponent("agent-usage.json")
        let cacheDirectory = homeDirectory.appendingPathComponent(".ping-island/cache", isDirectory: true)
        usageCacheURLs = [
            cacheDirectory.appendingPathComponent("claude-usage.json"),
            cacheDirectory.appendingPathComponent("codex-usage.json")
        ]
        self.legacyDefaultsDomain = legacyDefaultsDomain
    }

    public func discover(fileManager: FileManager = .default) -> AgentLegacyImportDiscovery {
        AgentLegacyImportDiscovery(
            hasDefaultsDomain: legacyDefaultsDomain() != nil,
            hasAssociations: fileManager.fileExists(atPath: associationsURL.path),
            hasUsage: fileManager.fileExists(atPath: usageURL.path),
            hasUsageCache: usageCacheURLs.contains { fileManager.fileExists(atPath: $0.path) }
        )
    }

    public func load(authorization: AgentLegacyImportAuthorization) throws -> AgentLegacyImportPayload {
        guard authorization == .approved else { throw AgentLegacyImportError.authorizationRequired }
        var sources: [String] = []
        let associations: [String: AgentSessionKey]
        if FileManager.default.fileExists(atPath: associationsURL.path) {
            associations = try parseAssociations(Data(contentsOf: associationsURL))
            sources.append(associationsURL.path)
        } else {
            associations = [:]
        }
        let usage: [AgentProvider: AgentUsage]
        if FileManager.default.fileExists(atPath: usageURL.path) {
            usage = try parseUsage(Data(contentsOf: usageURL))
            sources.append(usageURL.path)
        } else {
            usage = [:]
        }
        var combinedUsage = usage
        for cacheURL in usageCacheURLs where FileManager.default.fileExists(atPath: cacheURL.path) {
            let cacheUsage = try parseCachedUsage(Data(contentsOf: cacheURL))
            if let value = cacheUsage {
                let existing = combinedUsage[.legacyImport] ?? AgentUsage()
                combinedUsage[.legacyImport] = AgentUsage(
                    inputTokens: existing.inputTokens + value.inputTokens,
                    cachedInputTokens: existing.cachedInputTokens + value.cachedInputTokens,
                    outputTokens: existing.outputTokens + value.outputTokens
                )
            }
            sources.append(cacheURL.path)
        }
        let preferredProfiles = parsePreferredProfiles(legacyDefaultsDomain())
        if legacyDefaultsDomain() != nil {
            sources.append("defaults://\(AgentLegacyIdentityAllowlist.bundleIdentifier)")
        }
        return AgentLegacyImportPayload(
            associations: associations,
            usage: combinedUsage,
            preferredProfileIDs: preferredProfiles,
            sourceFiles: sources
        )
    }

    private func parseAssociations(_ data: Data) throws -> [String: AgentSessionKey] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentLegacyImportError.invalidAssociations
        }
        var result: [String: AgentSessionKey] = [:]
        for (externalKey, value) in root {
            guard let record = value as? [String: Any],
                  let sessionID = (record["sessionId"] ?? record["sessionID"]) as? String else {
                continue
            }
            let providerRaw = record["provider"] as? String ?? externalKey.split(separator: ":").first.map(String.init)
            let profileID = ((record["clientInfo"] as? [String: Any])?["profileID"] as? String)
            let provider = providerRaw.flatMap(AgentProvider.init(rawValue:))
                ?? profileID.flatMap { AgentIntegrationRegistry.profile(id: $0)?.provider }
                ?? .legacyImport
            result[externalKey] = AgentSessionKey(provider: provider, sessionID: sessionID)
        }
        return result
    }

    private func parseUsage(_ data: Data) throws -> [AgentProvider: AgentUsage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentLegacyImportError.invalidUsage
        }
        let buckets = root["buckets"] as? [String: Any] ?? [:]
        var input = 0
        var cached = 0
        var output = 0
        for value in buckets.values {
            guard let bucket = value as? [String: Any],
                  let totals = bucket["tokenTotals"] as? [String: Any] else { continue }
            input += Self.integer(totals["input"] ?? totals["inputTokens"])
            cached += Self.integer(totals["cachedInput"] ?? totals["cachedInputTokens"])
            output += Self.integer(totals["output"] ?? totals["outputTokens"])
        }
        guard input > 0 || cached > 0 || output > 0 else { return [:] }
        // The legacy aggregate did not retain a reliable per-provider split.
        // Keep it in a visibly imported bucket instead of misattributing it.
        return [.legacyImport: AgentUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output
        )]
    }

    private func parseCachedUsage(_ data: Data) throws -> AgentUsage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw AgentLegacyImportError.invalidUsage
        }
        var totals = (input: 0, cached: 0, output: 0)
        Self.accumulateUsage(root, totals: &totals)
        guard totals.input > 0 || totals.cached > 0 || totals.output > 0 else { return nil }
        return AgentUsage(
            inputTokens: totals.input,
            cachedInputTokens: totals.cached,
            outputTokens: totals.output
        )
    }

    private func parsePreferredProfiles(_ domain: [String: Any]?) -> Set<String> {
        guard let values = domain?["HookInstaller.preferredTargets.v1"] as? [String] else {
            return []
        }
        let aliases = ["qwen-hooks": "qwen-code-hooks"]
        return Set(values.compactMap { value in
            let normalized = aliases[value] ?? value
            return AgentIntegrationRegistry.profile(id: normalized)?.id
        })
    }

    private static func accumulateUsage(
        _ value: Any,
        totals: inout (input: Int, cached: Int, output: Int)
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                switch key.lowercased() {
                case "input", "inputtokens", "input_tokens": totals.input += integer(nested)
                case "cachedinput", "cachedinputtokens", "cached_input_tokens": totals.cached += integer(nested)
                case "output", "outputtokens", "output_tokens": totals.output += integer(nested)
                default: accumulateUsage(nested, totals: &totals)
                }
            }
        } else if let array = value as? [Any] {
            for nested in array { accumulateUsage(nested, totals: &totals) }
        }
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return max(value, 0) }
        if let value = value as? NSNumber { return max(value.intValue, 0) }
        return 0
    }
}
