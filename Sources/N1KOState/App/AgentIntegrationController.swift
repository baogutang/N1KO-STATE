import AppKit
import Combine
import N1KOAgentCore

private struct AgentLegacyImportLedgerEntry: Codable {
    let importedAt: Date
    let sourceSignature: String
    let sources: [String]
    let preferredProfileIDs: [String]
}

private struct AgentLegacyImportLedger: Codable {
    var formatVersion = 1
    var entries: [AgentLegacyImportLedgerEntry] = []
}

/// Application-side adapter for user-initiated integrations. Agent Core keeps
/// session ownership; this object only performs explicit configuration and
/// focus actions through public APIs.
final class AgentIntegrationController: ObservableObject {
    static let shared = AgentIntegrationController()
    static let hookSchemaVersion = 1

    @Published private(set) var installedProfileIDs: Set<String> = []
    @Published private(set) var legacyDiscovery: AgentLegacyImportDiscovery
    @Published private(set) var isBusy = false
    @Published private(set) var operationMessage: String?

    private weak var coordinator: AgentSessionCoordinator?
    private let legacyImportService: AgentLegacyImportService
    private let supportDirectory: URL
    private let ownerID = "n1ko-state-\(getpid())"

    private init(
        legacyImportService: AgentLegacyImportService = AgentLegacyImportService(),
        supportDirectory: URL = AgentRuntimePaths.n1koDefault().applicationSupportDirectory
    ) {
        self.legacyImportService = legacyImportService
        self.supportDirectory = supportDirectory
        legacyDiscovery = legacyImportService.discover()
        refreshInstalledProfiles()
    }

    func configure(coordinator: AgentSessionCoordinator?) {
        self.coordinator = coordinator
        legacyDiscovery = legacyImportService.discover()
        refreshInstalledProfiles()
    }

    func shutdown() {
        guard let installer = makeInstaller() else { return }
        try? installer.leaseStore.release(ownerID: ownerID)
    }

    func installWithConfirmation(profile: AgentIntegrationProfile) {
        guard profile.managedHookAvailable, !isBusy else { return }
        let alert = NSAlert()
        alert.messageText = "Install %@ integration?".locf(profile.displayName)
        alert.informativeText = "N1KO-STATE will back up every touched file, preserve unrelated entries, install its private bridge, prove ingress, and only then remove recognized legacy managed references.".loc
        alert.addButton(withTitle: "Install".loc)
        alert.addButton(withTitle: "Cancel".loc)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(profile: profile)
    }

    func removeWithConfirmation(profile: AgentIntegrationProfile) {
        guard profile.managedHookAvailable, !isBusy else { return }
        let alert = NSAlert()
        alert.messageText = "Remove %@ integration?".locf(profile.displayName)
        alert.informativeText = "Only exact N1KO-managed entries and files will be removed. Other client configuration remains untouched.".loc
        alert.addButton(withTitle: "Remove".loc)
        alert.addButton(withTitle: "Cancel".loc)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let installer = makeInstaller() else {
            operationMessage = "N1KO Agent bridge is unavailable.".loc
            return
        }
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try installer.remove(
                    profileID: profile.id,
                    schemaVersion: Self.hookSchemaVersion
                )
                DispatchQueue.main.async {
                    guard let self else { return }
                    var selected = Set(AppSettings.shared.agentEnabledProfileIDs)
                    selected.remove(profile.id)
                    AppSettings.shared.agentEnabledProfileIDs = Array(selected).sorted()
                    self.isBusy = false
                    self.operationMessage = "Removed %@ integration.".locf(profile.displayName)
                    self.refreshInstalledProfiles()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.finishWithError(error)
                }
            }
        }
    }

    func importLegacyWithConfirmation() {
        legacyDiscovery = legacyImportService.discover()
        guard legacyDiscovery.hasImportableData, !isBusy else { return }
        let alert = NSAlert()
        alert.messageText = "Import legacy Agent data?".loc
        alert.informativeText = "N1KO-STATE will read compatible provider selections, session associations, and aggregate usage. It will not import credentials, hook ownership, telemetry settings, or transient window state, and it will not edit the legacy source.".loc
        alert.addButton(withTitle: "Import".loc)
        alert.addButton(withTitle: "Cancel".loc)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            guard coordinator != nil else {
                operationMessage = "Agent Core is unavailable; legacy data was not imported.".loc
                return
            }
            let payload = try legacyImportService.load(authorization: .approved)
            let signature = Self.signature(for: payload)
            var ledger = try loadLegacyImportLedger()
            if ledger.entries.contains(where: { $0.sourceSignature == signature }) {
                operationMessage = "Legacy Agent data is already imported.".loc
                return
            }
            _ = coordinator?.importLegacy(payload)
            let selected = Set(AppSettings.shared.agentEnabledProfileIDs)
                .union(payload.preferredProfileIDs)
            AppSettings.shared.agentEnabledProfileIDs = Array(selected).sorted()
            ledger.entries.append(AgentLegacyImportLedgerEntry(
                importedAt: Date(),
                sourceSignature: signature,
                sources: payload.sourceFiles,
                preferredProfileIDs: payload.preferredProfileIDs.sorted()
            ))
            try saveLegacyImportLedger(ledger)
            operationMessage = "Imported compatible legacy Agent data.".loc
        } catch {
            finishWithError(error)
        }
    }

    func focus(session: AgentSessionSnapshot) {
        var enabledCapabilities: Set<AgentIntegrationCapability> = []
        if AppSettings.shared.agentFocusEnabled {
            enabledCapabilities.formUnion([.terminalFocus, .ideFocus])
        }
        if AppSettings.shared.agentTMUXEnabled { enabledCapabilities.insert(.tmux) }
        let policy = AgentCapabilityPolicy(enabled: enabledCapabilities)
        do {
            let profile = AgentIntegrationRegistry.profile(provider: session.provider)
            let capability: AgentIntegrationCapability = profile?.capabilities.contains(.ideFocus) == true
                ? .ideFocus : .terminalFocus
            try policy.require(capability)

            if AppSettings.shared.agentTMUXEnabled,
               let target = session.navigation?.tmuxTarget {
                try policy.require(.tmux)
                let validated = try AgentTMUXTarget(
                    session: target.session,
                    window: target.window,
                    pane: target.pane
                )
                guard let tmuxURL = AgentTMUXExecutableResolver.resolve() else {
                    operationMessage = "tmux is unavailable on this Mac.".loc
                    return
                }
                let process = Process()
                process.executableURL = tmuxURL
                process.arguments = validated.focusArguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try process.run()
            }

            let preferredBundles = [session.navigation?.terminalBundleIdentifier]
                .compactMap { $0 } + (profile?.bundleIdentifiers ?? [])
            let terminalBundles = [
                "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                "net.kovidgoyal.kitty", "dev.warp.Warp-Stable"
            ]
            let candidates = capability == .ideFocus ? preferredBundles : preferredBundles + terminalBundles
            if let application = NSWorkspace.shared.runningApplications.first(where: {
                guard let id = $0.bundleIdentifier else { return false }
                return candidates.contains(id)
            }) {
                application.activate(options: [.activateIgnoringOtherApps])
                operationMessage = "Focused the session application.".loc
                return
            }
            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))
                operationMessage = "Opened the session project.".loc
            } else {
                operationMessage = "No focus target is available for this session.".loc
            }
        } catch {
            operationMessage = "Enable session focus before using this action.".loc
        }
    }

    func canSendFollowUp(to session: AgentSessionSnapshot) -> Bool {
        if session.provider == .codex,
           coordinator?.nativeRuntimeAvailable(provider: .codex) == true {
            return true
        }
        if coordinator?.managesNativeSession(
            provider: session.provider,
            sessionID: session.sessionID
        ) == true {
            return true
        }
        return AppSettings.shared.agentTMUXEnabled && session.navigation?.tmuxTarget != nil
    }

    func sendFollowUp(
        _ message: String,
        to session: AgentSessionSnapshot,
        completion: @escaping (Bool) -> Void
    ) {
        if session.provider == .codex,
           coordinator?.nativeRuntimeAvailable(provider: .codex) == true {
            Task { [weak self] in
                do {
                    try await self?.coordinator?.sendNativeMessage(
                        provider: .codex,
                        sessionID: session.sessionID,
                        text: message
                    )
                    await MainActor.run { completion(true) }
                } catch {
                    await MainActor.run { completion(false) }
                }
            }
            return
        }
        if coordinator?.managesNativeSession(
            provider: session.provider,
            sessionID: session.sessionID
        ) == true {
            Task { [weak self] in
                do {
                    try await self?.coordinator?.sendNativeMessage(
                        provider: session.provider,
                        sessionID: session.sessionID,
                        text: message
                    )
                    await MainActor.run { completion(true) }
                } catch {
                    await MainActor.run { completion(false) }
                }
            }
            return
        }
        guard AppSettings.shared.agentTMUXEnabled,
              let target = session.navigation?.tmuxTarget else {
            completion(false)
            return
        }
        let plan: AgentTMUXMessagePlan
        do {
            let validated = try AgentTMUXTarget(
                session: target.session,
                window: target.window,
                pane: target.pane
            )
            plan = try AgentTMUXMessagePlan(
                target: validated,
                message: message,
                policy: AgentCapabilityPolicy(enabled: [.tmux])
            )
        } catch {
            completion(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let sentText = Self.runTMUX(plan.executableURL, arguments: plan.textArguments)
            let sentEnter = sentText
                && Self.runTMUX(plan.executableURL, arguments: plan.enterArguments)
            DispatchQueue.main.async { completion(sentEnter) }
        }
    }

    private static func runTMUX(_ executableURL: URL, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        do {
            try process.run()
            guard completed.wait(timeout: .now() + 2) == .success else {
                process.terminate()
                _ = completed.wait(timeout: .now() + 0.5)
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func install(profile: AgentIntegrationProfile) {
        guard let installer = makeInstaller() else {
            operationMessage = "N1KO Agent bridge is unavailable.".loc
            return
        }
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let runtimeDirectory = coordinator?.configuration.runtimePaths.runtimeDirectory
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try installer.install(
                    profileID: profile.id,
                    schemaVersion: Self.hookSchemaVersion,
                    ownerID: self?.ownerID ?? "n1ko-state",
                    runningBundleIdentifiers: runningBundleIDs,
                    takeOverLegacyReferences: true
                ) { _, _ in
                    Self.runProof(
                        bridgeURL: installer.bridgeURL,
                        profile: profile,
                        runtimeDirectory: runtimeDirectory
                    )
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    var selected = Set(AppSettings.shared.agentEnabledProfileIDs)
                    selected.insert(profile.id)
                    AppSettings.shared.agentEnabledProfileIDs = Array(selected).sorted()
                    self.isBusy = false
                    self.operationMessage = "Installed %@ integration.".locf(profile.displayName)
                    self.refreshInstalledProfiles()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.finishWithError(error)
                }
            }
        }
    }

    private func makeInstaller() -> AgentManagedHookInstaller? {
        guard let bridgeURL = Self.bridgeURL() else { return nil }
        return AgentManagedHookInstaller(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            bridgeURL: bridgeURL,
            applicationSupportDirectory: supportDirectory
        )
    }

    private static func bridgeURL() -> URL? {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/n1ko-agent-bridge"),
            executableDirectory?.appendingPathComponent("N1KOAgentBridge"),
            executableDirectory?.appendingPathComponent("n1ko-agent-bridge")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func runProof(
        bridgeURL: URL,
        profile: AgentIntegrationProfile,
        runtimeDirectory: URL?
    ) -> Bool {
        let process = Process()
        process.executableURL = bridgeURL
        var arguments = [
            "--provider", profile.provider.rawValue,
            "--profile", profile.id,
            "--managed-by", "com.n1ko.state.agent",
            "--schema-version", String(hookSchemaVersion),
            "--probe"
        ]
        if profile.capabilities.contains(.inlineResponse) { arguments.append("--expects-response") }
        if let runtimeDirectory {
            arguments.append(contentsOf: ["--runtime-directory", runtimeDirectory.path])
        }
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        do {
            try process.run()
            guard completed.wait(timeout: .now() + 3) == .success else {
                process.terminate()
                _ = completed.wait(timeout: .now() + 1)
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func refreshInstalledProfiles() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        installedProfileIDs = Set(AgentIntegrationRegistry.profiles.compactMap { profile in
            guard profile.managedHookAvailable else { return nil }
            let configured = profile.configurationURL(homeDirectory: home)
            let primary: URL
            switch profile.installationKind {
            case .pluginDirectory:
                primary = configured.appendingPathComponent(profile.provider == .hermes ? "__init__.py" : "index.ts")
            case .hookDirectory:
                primary = configured.appendingPathComponent("handler.ts")
            default:
                primary = configured
            }
            guard let text = try? String(contentsOf: primary, encoding: .utf8),
                  text.contains("com.n1ko.state.agent"),
                  text.contains(profile.id) else { return nil }
            return profile.id
        })
    }

    private func finishWithError(_ error: Error) {
        isBusy = false
        if error as? AgentHookInstallationError == .conflictingOwner {
            operationMessage = "Integration change blocked while a legacy or another owning application is running.".loc
        } else {
            operationMessage = "Integration change failed: %@".locf(String(describing: error))
        }
        refreshInstalledProfiles()
    }

    private var legacyImportLedgerURL: URL {
        supportDirectory.appendingPathComponent("Migration/legacy-import-ledger.json")
    }

    private func loadLegacyImportLedger() throws -> AgentLegacyImportLedger {
        guard FileManager.default.fileExists(atPath: legacyImportLedgerURL.path) else {
            return AgentLegacyImportLedger()
        }
        return try JSONDecoder().decode(
            AgentLegacyImportLedger.self,
            from: Data(contentsOf: legacyImportLedgerURL)
        )
    }

    private func saveLegacyImportLedger(_ ledger: AgentLegacyImportLedger) throws {
        try FileManager.default.createDirectory(
            at: legacyImportLedgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: legacyImportLedgerURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: legacyImportLedgerURL.path
        )
    }

    private static func signature(for payload: AgentLegacyImportPayload) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        let fileManager = FileManager.default
        let bytes = payload.sourceFiles.sorted().flatMap { source -> [UInt8] in
            guard !source.hasPrefix("defaults://"), fileManager.fileExists(atPath: source),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: source)) else {
                return Array(source.utf8)
            }
            return Array(source.utf8) + Array(data)
        } + Array(payload.preferredProfileIDs.sorted().joined(separator: "|").utf8)
        for byte in bytes {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(format: "%016llx", value)
    }
}
