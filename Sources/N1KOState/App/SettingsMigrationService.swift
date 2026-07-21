import Foundation

struct N1KOSettingsMigrationEntry: Codable, Equatable {
    let schemaVersion: Int
    let completedAt: Date
    let backupPath: String
    let steps: [String]
}

struct N1KOSettingsMigrationLedger: Codable, Equatable {
    let formatVersion: Int
    var entries: [N1KOSettingsMigrationEntry]

    init(formatVersion: Int = 1, entries: [N1KOSettingsMigrationEntry] = []) {
        self.formatVersion = formatVersion
        self.entries = entries
    }

    var installedSchemaVersion: Int { entries.map(\.schemaVersion).max() ?? 0 }
}

enum SettingsMigrationResult: Equatable {
    case migrated(schemaVersion: Int, backupPath: String)
    case alreadyCurrent(schemaVersion: Int)
}

/// The only N1KO preference migrator. It writes an exact plist backup before
/// changing defaults and keeps a private, versioned ledger outside defaults so
/// repeated launches cannot re-import or overwrite a user's newer choices.
final class SettingsMigrationService {
    static let currentSchemaVersion = 2
    static let currentDomainName = "com.n1ko.state.monitor"
    static let previousN1KODomainName = "com.n1kostate.menubar.app2026"

    private let defaults: UserDefaults
    private let domainName: String
    private let previousDefaults: UserDefaults?
    private let ledgerURL: URL
    private let backupURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    convenience init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("N1KO-STATE/Migration", isDirectory: true)
        self.init(
            defaults: .standard,
            domainName: Self.currentDomainName,
            previousDefaults: UserDefaults(suiteName: Self.previousN1KODomainName),
            migrationDirectory: support
        )
    }

    init(
        defaults: UserDefaults,
        domainName: String,
        previousDefaults: UserDefaults?,
        migrationDirectory: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.domainName = domainName
        self.previousDefaults = previousDefaults
        ledgerURL = migrationDirectory.appendingPathComponent("preferences-ledger.json")
        backupURL = migrationDirectory.appendingPathComponent(
            "preferences-before-schema-\(Self.currentSchemaVersion).plist"
        )
        self.fileManager = fileManager
        self.now = now
    }

    @discardableResult
    func migrate() throws -> SettingsMigrationResult {
        var ledger = try loadLedger()
        guard ledger.installedSchemaVersion < Self.currentSchemaVersion else {
            return .alreadyCurrent(schemaVersion: ledger.installedSchemaVersion)
        }

        try fileManager.createDirectory(
            at: ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let persistedBeforeMigration = defaults.persistentDomain(forName: domainName) ?? [:]
        if !fileManager.fileExists(atPath: backupURL.path) {
            let data = try PropertyListSerialization.data(
                fromPropertyList: persistedBeforeMigration,
                format: .binary,
                options: 0
            )
            try data.write(to: backupURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }

        var steps: [String] = []
        if !defaults.bool(forKey: "didMigrateV1") {
            let compatibleKeys = [
                "menuCPU", "menuGPU", "menuMemory", "menuNetwork", "menuBattery",
                "menuCompact", "menuBarLayout", "popoverStyle", "refreshInterval",
                "accentHex", "useFahrenheit", "sensorsDetailed", "language",
                "showCPU", "showGPU", "showMemory", "showDisk", "showNetwork",
                "showSensors", "showBattery", "moduleOrder", "alertsEnabled",
                "cpuAlert", "cpuThreshold", "memAlert", "memThreshold",
                "tempAlert", "tempThreshold", "diskAlert", "diskFreeThreshold",
                "batteryAlert", "batteryThreshold"
            ]
            for key in compatibleKeys where persistedBeforeMigration[key] == nil {
                if let value = previousDefaults?.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: "didMigrateV1")
            steps.append("imported-compatible-previous-n1ko-defaults-without-overwrite")
        }

        for key in ["presentationStyle", "agent.presentation.style"]
            where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            steps.append("removed-obsolete-\(key)")
        }
        defaults.set(Self.currentSchemaVersion, forKey: "settings.schemaVersion")
        steps.append("set-settings-schema-version")

        let entry = N1KOSettingsMigrationEntry(
            schemaVersion: Self.currentSchemaVersion,
            completedAt: now(),
            backupPath: backupURL.path,
            steps: steps
        )
        ledger.entries.append(entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: ledgerURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledgerURL.path)
        return .migrated(schemaVersion: Self.currentSchemaVersion, backupPath: backupURL.path)
    }

    func loadLedger() throws -> N1KOSettingsMigrationLedger {
        guard fileManager.fileExists(atPath: ledgerURL.path) else {
            return N1KOSettingsMigrationLedger()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            N1KOSettingsMigrationLedger.self,
            from: Data(contentsOf: ledgerURL)
        )
    }
}
