import AppKit
import N1KOAgentCore
import SwiftUI
import UserNotifications

/// Owns the shared monitor hub, menu-bar status item, and popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {

    let hub: MonitorHub
    private var menuBar: MenuBarStatusController!
    private var presentation: PresentationCoordinator!
    private var agentCoordinator: AgentSessionCoordinator?
    private var performanceLifecycleCyclesCompleted = 0
    private var performanceSoakSamplingActive = false
    private var performanceSoakSampleInterval: TimeInterval = 60
    private var performanceSoakSamplesURL: URL?
    private var systemSleepEvents = 0
    private var systemWakeEvents = 0
    private var sessionInactiveEvents = 0
    private var sessionActiveEvents = 0
    private var screenSleepEvents = 0
    private var screenWakeEvents = 0
    private let settingsMigrationMessage: String

    override init() {
        do {
            let result = try SettingsMigrationService().migrate()
            settingsMigrationMessage = "preference migration result=\(result)"
        } catch {
            settingsMigrationMessage = "preference migration failed type=\(String(describing: type(of: error)))"
        }
        hub = MonitorHub()
        super.init()
    }

    /// `atexit` can't capture `self`; route the last-ditch reset through a
    /// process-global weak reference. This is a best-effort backstop only — the
    /// real guarantee that `FS!` returns to 0 on any exit (including SIGKILL) is
    /// the daemon's connection-invalidation handler.
    static weak var sharedFans: FanControlService?
    static weak var sharedHub: MonitorHub?

    func applicationWillTerminate(_ notification: Notification) {
        AgentIntegrationController.shared.shutdown()
        let agentShutdown = agentCoordinator?.shutdown()
        if let agentShutdown {
            DiagLog.log(
                "AgentCore",
                "shutdown socket=\(agentShutdown.socketsClosed) watchers=\(agentShutdown.watchersClosed) " +
                "transports=\(agentShutdown.transportsClosed) tasks=\(agentShutdown.tasksCancelled) " +
                "subprocesses=\(agentShutdown.subprocessesTerminated) remaining=\(agentShutdown.remainingRunningResources)"
            )
        }
        presentation?.shutdown()
        hub.flushHistory()
        hub.fans.resetAllFansSync()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagLog.bootstrap()
        DiagLog.log("AppDelegate", "applicationDidFinishLaunching")
        DiagLog.log("Migration", settingsMigrationMessage)
        NSApp.setActivationPolicy(.accessory)
        setupAgentCore()

        if AlertManager.notificationsSupported {
            UNUserNotificationCenter.current().delegate = self
        }

        hub.start()
        let performanceHeadless = ProcessInfo.processInfo.environment["N1KO_PERF_HEADLESS"] == "1"
        setupMenuBar()
        if performanceHeadless {
            menuBar.removeForPerformanceBenchmark()
        }
        setupPresentation(installSurfaces: !performanceHeadless)
        UpdateController.shared.configure(agentCoordinator: agentCoordinator)
        UpdateController.shared.start()
        LicenseService.shared.refresh()

        // Bug-1: initialise UI from the real SMC FS! value (not any persisted
        // preference), and re-sync after the machine wakes from sleep.
        hub.fans.syncFromSMC()
        AppDelegate.sharedFans = hub.fans
        AppDelegate.sharedHub = hub
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(userSessionBecameInactive),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(userSessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        atexit { AppDelegate.sharedFans?.resetAllFansSync(timeout: 1.5) }

        let performanceBenchmarkActive = startPerformanceBenchmarkIfRequested()
        if !performanceBenchmarkActive {
            // Preserve the pinned Island startup cue without importing its
            // AppDelegate. Playback still runs through N1KO's sole settings
            // and sound authority; benchmark launches stay deterministic.
            DispatchQueue.main.async {
                AppSettings.playClientStartupSound()
            }
        }
        if !performanceBenchmarkActive, !UserDefaults.standard.bool(forKey: "didShowOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.activate(ignoringOtherApps: true)
                OnboardingWindowController.shared.show(hub: self.hub)
            }
        } else if !performanceBenchmarkActive {
            DispatchQueue.main.async {
                LicenseWindowController.shared.showIfNeeded()
            }
        }
        hub.fans.refreshHelperStatus()
    }

    @objc private func systemDidWake() {
        systemWakeEvents += 1
        hub.fans.syncFromSMC()
        agentCoordinator?.applyLifecycle(.active)
    }

    @objc private func systemWillSleep() {
        systemSleepEvents += 1
        agentCoordinator?.applyLifecycle(.systemSleeping)
    }

    @objc private func userSessionBecameInactive() {
        sessionInactiveEvents += 1
        agentCoordinator?.applyLifecycle(.userSessionInactive)
    }

    @objc private func userSessionBecameActive() {
        sessionActiveEvents += 1
        agentCoordinator?.applyLifecycle(.active)
    }

    @objc private func screenDidSleep() {
        screenSleepEvents += 1
        agentCoordinator?.applyLifecycle(.screenLocked)
    }

    @objc private func screenDidWake() {
        screenWakeEvents += 1
        agentCoordinator?.applyLifecycle(.active)
    }

    private func setupMenuBar() {
        menuBar = MenuBarStatusController(hub: hub)
        menuBar.install()
    }

    private func setupPresentation(installSurfaces: Bool = true) {
        presentation = PresentationCoordinator(
            hub: hub,
            menuBar: menuBar,
            agentCoordinator: agentCoordinator
        )
        if installSurfaces {
            presentation.install()
        }
    }

    private func setupAgentCore() {
        let environment = ProcessInfo.processInfo.environment
        let enabled: Bool
        if let override = environment["N1KO_AGENT_ENABLED"] {
            enabled = override != "0" && override.lowercased() != "false"
        } else if UserDefaults.standard.object(forKey: "agent.behavior.enabled") != nil {
            enabled = UserDefaults.standard.bool(forKey: "agent.behavior.enabled")
        } else {
            enabled = true
        }

        do {
            let defaultPaths = AgentRuntimePaths.n1koDefault()
            let runtimeDirectory = environment["N1KO_AGENT_RUNTIME_DIRECTORY"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? defaultPaths.runtimeDirectory
            let supportDirectory = environment["N1KO_AGENT_SUPPORT_DIRECTORY"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? defaultPaths.applicationSupportDirectory
            let rolloutRoot = environment["N1KO_CODEX_ROLLOUT_DIRECTORY"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex/sessions", isDirectory: true)
            let codexTransport = enabled
                ? CodexAppServerStdioTransport(environment: environment)
                : nil
            let nativeRuntime = codexTransport.map {
                AgentNativeRuntimeController(codexTransport: $0, environment: environment)
            }
            let extraSources: [AgentIngressSource] = codexTransport.map {
                [CodexAppServerIngressSource(
                    transport: $0,
                    ownerID: CodexAppServerStdioTransport.defaultOwnerID
                )]
            } ?? []
            let coordinator = try AgentSessionCoordinator(
                configuration: AgentCoreConfiguration(
                    enabled: enabled,
                    runtimePaths: AgentRuntimePaths(
                        runtimeDirectory: runtimeDirectory,
                        applicationSupportDirectory: supportDirectory
                    ),
                    codexRolloutRoot: rolloutRoot
                ),
                extraSources: extraSources,
                nativeRuntime: nativeRuntime
            )
            try coordinator.start()
            agentCoordinator = coordinator
            AgentIntegrationController.shared.configure(coordinator: coordinator)
            DiagLog.log(
                "AgentCore",
                "started enabled=\(enabled) restoredSessions=\(coordinator.snapshot.sessions.count)"
            )
        } catch {
            agentCoordinator = nil
            AgentIntegrationController.shared.configure(coordinator: nil)
            DiagLog.log(
                "AgentCore",
                "start failed type=\(String(describing: type(of: error)))"
            )
        }
    }

    // MARK: - WP0 performance benchmark driver

    /// Opt-in, environment-driven automation for optimized-build baselines.
    /// Normal launches never enter this path. The external runner backs up and
    /// restores UserDefaults before enabling it.
    private func startPerformanceBenchmarkIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["N1KO_PERF_SCENARIO"], !scenario.isEmpty else {
            return false
        }

        // Keep formal scenarios deterministic even if the user clicks the
        // status item while a long trace is running. Scenario automation calls
        // the presentation methods directly and does not use this callback.
        menuBar.onClick = {
            DiagLog.log("Performance", "ignored status-item click during benchmark")
        }

        let warmup = max(TimeInterval(environment["N1KO_PERF_WARMUP_SECONDS"] ?? "120") ?? 120, 0)
        let duration = max(TimeInterval(environment["N1KO_PERF_DURATION_SECONDS"] ?? "600") ?? 600, 1)
        DiagLog.log("Performance", "benchmark scenario=\(scenario) warmup=\(warmup)s duration=\(duration)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.configurePerformanceScenario(scenario)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + warmup) { [weak self] in
            guard let self else { return }
            PerformanceDiagnostics.reset()
            AgentCoreDiagnostics.reset()
            AgentSurfaceDiagnostics.reset()
            self.startReleaseSoakSamplingIfRequested(environment)
            if let readyPath = environment["N1KO_PERF_READY_PATH"] {
                try? Data().write(to: URL(fileURLWithPath: readyPath), options: .atomic)
            }
            if scenario == "panel-settings-100-cycles" {
                // Give the external runner time to capture the true pre-cycle
                // footprint before the first window allocation starts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.beginMeasuredPerformanceScenario(scenario)
                }
            } else {
                self.beginMeasuredPerformanceScenario(scenario)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + warmup + duration) { [weak self] in
            guard let self else { return }
            self.stopReleaseSoakSampling()
            if let outputPath = environment["N1KO_PERF_OUTPUT_PATH"] {
                do {
                    let resources = self.agentCoordinator?.resourceSnapshot
                    let historyCounts = HistoryStore.shared.snapshot().mapValues(\.count)
                    try PerformanceDiagnostics.writeSnapshot(
                        to: URL(fileURLWithPath: outputPath),
                        metadata: [
                            "scenario": scenario,
                            "warmupSeconds": String(warmup),
                            "measurementSeconds": String(duration),
                            "pid": String(ProcessInfo.processInfo.processIdentifier),
                            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
                            "scenarioStateValidAtEnd": String(self.performanceScenarioStateIsValid(scenario)),
                            "lifecycleCyclesCompleted": String(self.performanceLifecycleCyclesCompleted),
                            "agentEnabled": String(self.agentCoordinator?.configuration.enabled ?? false),
                            "agentSessionCount": String(self.agentCoordinator?.snapshot.sessions.count ?? 0),
                            "agentIngressCount": String(
                                AgentCoreDiagnostics.snapshot().counters[.ingress] ?? 0
                            ),
                            "agentSurfaceVisible": String(self.presentation.agentSurfacesVisible),
                            "agentSurfaceSnapshotCompositions": String(
                                AgentSurfaceDiagnostics.snapshot().counters["snapshotComposition"] ?? 0
                            ),
                            "agentSurfaceActiveGlobalMonitors": String(
                                AgentSurfaceDiagnostics.snapshot().activeGlobalMonitors
                            ),
                            "agentSurfaceActiveRetryTasks": String(
                                AgentSurfaceDiagnostics.snapshot().activeRetryTasks
                            ),
                            "agentSockets": String(resources?.sockets ?? 0),
                            "agentWatchers": String(resources?.watchers ?? 0),
                            "agentTransports": String(resources?.transports ?? 0),
                            "agentRegisteredTasks": String(resources?.registeredTasks ?? 0),
                            "agentActiveTasks": String(resources?.activeTasks ?? 0),
                            "agentRegisteredSubprocesses": String(resources?.registeredSubprocesses ?? 0),
                            "agentActiveSubprocesses": String(resources?.activeSubprocesses ?? 0),
                            "agentPendingResponseRoutes": String(resources?.pendingResponseRoutes ?? 0),
                            "agentSnapshotObservers": String(resources?.snapshotObservers ?? 0),
                            "historyCPUCount": String(historyCounts["cpu"] ?? 0),
                            "historyMemoryCount": String(historyCounts["memory"] ?? 0),
                            "historyNetDownCount": String(historyCounts["netDown"] ?? 0),
                            "historyNetUpCount": String(historyCounts["netUp"] ?? 0),
                            "systemSleepEvents": String(self.systemSleepEvents),
                            "systemWakeEvents": String(self.systemWakeEvents),
                            "sessionInactiveEvents": String(self.sessionInactiveEvents),
                            "sessionActiveEvents": String(self.sessionActiveEvents),
                            "screenSleepEvents": String(self.screenSleepEvents),
                            "screenWakeEvents": String(self.screenWakeEvents)
                        ]
                    )
                } catch {
                    DiagLog.log("Performance", "failed to write counter snapshot: \(error)")
                }
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private func startReleaseSoakSamplingIfRequested(_ environment: [String: String]) {
        guard let path = environment["N1KO_SOAK_SAMPLES_PATH"], !path.isEmpty else { return }
        performanceSoakSamplesURL = URL(fileURLWithPath: path)
        performanceSoakSampleInterval = max(
            TimeInterval(environment["N1KO_SOAK_SAMPLE_SECONDS"] ?? "60") ?? 60,
            1
        )
        performanceSoakSamplingActive = true
        writeReleaseSoakSample(scheduleNext: true)
    }

    private func stopReleaseSoakSampling() {
        guard performanceSoakSamplingActive else { return }
        performanceSoakSamplingActive = false
        writeReleaseSoakSample(scheduleNext: false)
    }

    private func writeReleaseSoakSample(scheduleNext: Bool) {
        guard let url = performanceSoakSamplesURL else { return }
        let histories = HistoryStore.shared.snapshot()
        let resources = agentCoordinator?.resourceSnapshot
        let surface = AgentSurfaceDiagnostics.snapshot()
        let sample = ReleaseSoakSample(
            wallTimeSeconds: Date().timeIntervalSince1970,
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            historyCPUCount: histories["cpu"]?.count ?? 0,
            historyMemoryCount: histories["memory"]?.count ?? 0,
            historyNetDownCount: histories["netDown"]?.count ?? 0,
            historyNetUpCount: histories["netUp"]?.count ?? 0,
            agentSessionCount: agentCoordinator?.snapshot.sessions.count ?? 0,
            agentSockets: resources?.sockets ?? 0,
            agentWatchers: resources?.watchers ?? 0,
            agentTransports: resources?.transports ?? 0,
            agentRegisteredTasks: resources?.registeredTasks ?? 0,
            agentActiveTasks: resources?.activeTasks ?? 0,
            agentRegisteredSubprocesses: resources?.registeredSubprocesses ?? 0,
            agentActiveSubprocesses: resources?.activeSubprocesses ?? 0,
            agentPendingResponseRoutes: resources?.pendingResponseRoutes ?? 0,
            agentSnapshotObservers: resources?.snapshotObservers ?? 0,
            surfaceGlobalMonitors: surface.activeGlobalMonitors,
            surfaceRetryTasks: surface.activeRetryTasks,
            systemSleepEvents: systemSleepEvents,
            systemWakeEvents: systemWakeEvents,
            sessionInactiveEvents: sessionInactiveEvents,
            sessionActiveEvents: sessionActiveEvents,
            screenSleepEvents: screenSleepEvents,
            screenWakeEvents: screenWakeEvents
        )
        do {
            try ReleaseSoakDiagnostics.append(sample, to: url)
        } catch {
            DiagLog.log("Performance", "failed to write soak sample: \(error)")
        }

        if scheduleNext, performanceSoakSamplingActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + performanceSoakSampleInterval) { [weak self] in
                guard let self, self.performanceSoakSamplingActive else { return }
                self.writeReleaseSoakSample(scheduleNext: true)
            }
        }
    }

    private func configurePerformanceScenario(_ scenario: String) {
        presentation.closeQuickPanel()
        SettingsWindowController.shared.closeForPerformanceBenchmark()

        switch scenario {
        case "menu-bar-only", "agent-core-idle", "agent-surface-hidden", "settings-used-then-closed", "panel-settings-100-cycles":
            if scenario == "agent-surface-hidden" {
                AppSettings.shared.agentPresentationEnabled = false
            }
            if scenario == "settings-used-then-closed" {
                presentation.showSettings(tab: .overview)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    SettingsWindowController.shared.closeForPerformanceBenchmark()
                }
            } else if scenario == "panel-settings-100-cycles" {
                // Prime repeated surface construction so measured footprint
                // growth represents steady state, not SwiftUI/AppKit caches.
                runPerformanceWarmupLifecycleCycle(remaining: 10)
            }
        case "quick-panel-cards":
            AppSettings.shared.popoverStyle = "cards"
            presentation.showQuickPanelForPerformanceBenchmark()
        case "quick-panel-gauges":
            AppSettings.shared.popoverStyle = "gauges"
            presentation.showQuickPanelForPerformanceBenchmark()
        default:
            if let tab = performanceSettingsTab(for: scenario) {
                presentation.showSettings(tab: tab)
            }
        }
    }

    private func performanceScenarioStateIsValid(_ scenario: String) -> Bool {
        switch scenario {
        case "quick-panel-cards", "quick-panel-gauges":
            return presentation.isQuickPanelVisible
        case "settings-used-then-closed", "menu-bar-only", "agent-core-idle", "agent-surface-hidden", "panel-settings-100-cycles":
            return !presentation.isQuickPanelVisible
                && !SettingsWindowController.shared.isVisibleForPerformanceBenchmark
                && !presentation.agentSurfacesVisible
        default:
            return SettingsWindowController.shared.isVisibleForPerformanceBenchmark
        }
    }

    private func beginMeasuredPerformanceScenario(_ scenario: String) {
        guard scenario == "panel-settings-100-cycles" else { return }
        runPerformanceLifecycleCycle(remaining: 100)
    }

    private func runPerformanceWarmupLifecycleCycle(remaining: Int) {
        guard remaining > 0 else { return }
        presentation.showQuickPanelForPerformanceBenchmark()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.presentation.closeQuickPanel()
            self.presentation.showSettings(tab: .overview)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                SettingsWindowController.shared.closeForPerformanceBenchmark()
                self?.runPerformanceWarmupLifecycleCycle(remaining: remaining - 1)
            }
        }
    }

    private func runPerformanceLifecycleCycle(remaining: Int) {
        guard remaining > 0 else { return }
        presentation.showQuickPanelForPerformanceBenchmark()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.presentation.closeQuickPanel()
            self.presentation.showSettings(tab: .overview)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                SettingsWindowController.shared.closeForPerformanceBenchmark()
                self?.performanceLifecycleCyclesCompleted += 1
                self?.runPerformanceLifecycleCycle(remaining: remaining - 1)
            }
        }
    }

    private func performanceSettingsTab(for scenario: String) -> SettingsTab? {
        switch scenario {
        case "settings-overview": return .overview
        case "settings-menu-bar": return .menuBar
        case "settings-popover": return .popover
        case "settings-sampling": return .sampling
        case "settings-sensors": return .sensors
        case "settings-alerts": return .alerts
        case "settings-agent-center": return .agentCenter
        case "settings-advanced": return .advanced
        default: return nil
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
