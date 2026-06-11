import Foundation
import Combine
import SMCKit
import FanXPCShared

/// Privileged fan writes via a persistent root LaunchDaemon over XPC.
///
/// The first write installs the helper with a **single** admin prompt
/// (`ensureHelperInstalled`); every subsequent write — and the reset-to-auto on
/// quit — goes over the Mach service with no further prompts. Reads stay
/// in-process (SMC reads need no privilege), so UI state always reflects the
/// real `FS!` value.
///
/// Fan control mode — single source of truth (replaces bool + manualFanIDs overlap).
enum FanMode: Equatable {
    case auto, manual, curve
}

/// Privileged helper installation / connection state for UI feedback.
///
/// State transitions (all others forbidden):
///   unknown → notInstalled | ready
///   notInstalled → installing
///   installing → ready | failed | declined (user cancel / timeout)
///   failed | declined → installing (user retry)
///   ready → notInstalled (uninstall)
enum HelperState: Equatable {
    case unknown
    case notInstalled
    case installing
    case ready
    case failed(String)
    case declined
}

/// The public surface (published state + method names) is unchanged from the
/// old osascript implementation so the SwiftUI layer needs no changes.
final class FanControlService: ObservableObject {

    @Published private(set) var fans: [FanInfo] = []
    @Published private(set) var manualFanIDs: Set<Int> = []
    @Published private(set) var manualTargets: [Int: Int] = [:]
    /// Fans whose manual RPM has actually been written to SMC.
    @Published private(set) var appliedFanIDs: Set<Int> = []
    @Published private(set) var isAvailable = false
    @Published private(set) var supportsControl = false
    @Published var lastError: String?
    @Published private(set) var isAuthorized = false
    @Published private(set) var helperState: HelperState = .unknown
    @Published private(set) var installedHelperVersion: Int?
    @Published private(set) var mode: FanMode = .auto
    @Published private(set) var curveTargets: [Int: Int] = [:]

    private let queue = smcAccessQueue
    /// Serial queue for all privileged work (install + XPC calls) so the
    /// blocking installer and semaphore waits never touch the main thread.
    private let controlQueue = DispatchQueue(label: "com.n1ko.state.monitor.fanctl", qos: .userInitiated)
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 2.0
    private var inFlight = false
    private var useFloat = false
    private var probed = false

    private var debounceWork: DispatchWorkItem?
    private var pendingApply: (id: Int, rpm: Int)?

    private var reconcileTimer: Timer?

    // XPC connection (created lazily, guarded by controlQueue).
    private var connection: NSXPCConnection?
    private var lastInstallAttempt = Date.distantPast
    private var installingStartedAt: Date?
    private var lastConnectionAttempt = Date.distantPast
    private static let installCooldown: TimeInterval = 60
    private static let connectionBackoff: TimeInterval = 1

    func isManual(_ id: Int) -> Bool {
        mode == .manual && (manualFanIDs.contains(id) || fans.first(where: { $0.id == id })?.forced == true)
    }

    func isCurveControlled(_ id: Int) -> Bool {
        mode == .curve && curveTargets[id] != nil
    }

    func curvePercent(for fan: FanInfo) -> Double? {
        guard let rpm = curveTargets[fan.id], fan.maxRPM > fan.minRPM else { return nil }
        return Double(rpm - fan.minRPM) / Double(fan.maxRPM - fan.minRPM)
    }

    /// Onboarding "Skip" — persist declined so exit/refresh won't retry install.
    func markDeclined() {
        lastInstallAttempt = Date()
        installingStartedAt = nil
        helperState = .declined
    }

    // MARK: - Reading (unprivileged, in-process)

    func refresh() {
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= minInterval, !inFlight else { return }
        lastRun = now
        inFlight = true

        queue.async { [weak self] in
            guard let self else { return }
            if !self.probed, (try? SMCKit.fanCount()) != nil {
                self.useFloat = SMCKit.hasFloatFans()
                self.probed = true
            }

            let infos = self.readFans()

            DispatchQueue.main.async {
                self.fans = infos
                self.isAvailable = !infos.isEmpty
                self.supportsControl = self.useFloat && !infos.isEmpty
                self.inFlight = false
                self.enforceThermalSafety(peakCelsius: nil)
            }
        }
    }

    /// Re-read the real `FS!` value and reconcile the UI state to it. The SMC is
    /// the source of truth — this clears stale manual flags (e.g. after the
    /// hardware was returned to auto by the daemon while the app was asleep) and
    /// adopts manual flags the hardware actually has. Bug-1 safeguard, driven on
    /// launch, on wake, and by the 30s reconcile timer.
    func syncFromSMC() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.probed, (try? SMCKit.fanCount()) != nil {
                self.useFloat = SMCKit.hasFloatFans()
                self.probed = true
            }
            let infos = self.readFans()
            let mode = self.useFloat ? SMCKit.readFanModeSwitch() : nil

            DispatchQueue.main.async {
                self.fans = infos
                self.isAvailable = !infos.isEmpty
                self.supportsControl = self.useFloat && !infos.isEmpty
                self.reconcile(mode: mode, infos: infos)
            }
        }
    }

    /// Apply the hardware truth to the published manual/applied sets (main actor).
    private func reconcile(mode switchMode: UInt8?, infos: [FanInfo]) {
        let forcedIDs: Set<Int>
        if let switchMode {
            forcedIDs = switchMode == 0 ? [] : [Int(switchMode) - 1]
        } else {
            forcedIDs = Set(infos.filter { $0.forced }.map { $0.id })
        }

        if forcedIDs.isEmpty {
            manualFanIDs.removeAll()
            manualTargets.removeAll()
            appliedFanIDs.removeAll()
            curveTargets.removeAll()
            if mode != .auto { mode = .auto }
        } else {
            switch mode {
            case .auto:
                manualFanIDs = forcedIDs
                for id in forcedIDs where manualTargets[id] == nil {
                    if let f = infos.first(where: { $0.id == id }) {
                        manualTargets[id] = f.targetRPM > 0 ? f.targetRPM : f.rpm
                    }
                }
                appliedFanIDs = forcedIDs
                mode = .manual
            case .manual:
                manualFanIDs = forcedIDs
                for id in forcedIDs where manualTargets[id] == nil {
                    if let f = infos.first(where: { $0.id == id }) {
                        manualTargets[id] = f.targetRPM > 0 ? f.targetRPM : f.rpm
                    }
                }
                appliedFanIDs = forcedIDs
            case .curve:
                appliedFanIDs = forcedIDs
            }
        }
    }

    private func readFans() -> [FanInfo] {
        if useFloat {
            return SMCKit.readFloatFans().map {
                FanInfo(id: $0.id, name: "Fan \($0.id + 1)",
                        rpm: Int($0.current.rounded()),
                        targetRPM: Int($0.target.rounded()),
                        minRPM: Int($0.min.rounded()), maxRPM: Int($0.max.rounded()),
                        forced: $0.forced)
            }
        }
        return FanControlService.readLegacyFans()
    }

    /// Begin the 30s reconcile loop (called once from `MonitorHub.start`).
    func startReconcileLoop() {
        guard reconcileTimer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.syncFromSMC()
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        reconcileTimer = t
    }

    // MARK: - Thermal safety

    /// Call from MonitorHub when sensor peak is known.
    func enforceThermalSafety(peakCelsius: Double?) {
        guard let peak = peakCelsius, peak >= 95, mode != .auto else { return }
        lastError = "Temperature high — fans returned to automatic.".loc
        resetAllFans()
    }

    // MARK: - Manual control (UI intent → privileged writes)

    /// Enter manual mode for one fan (UI only — no privileged write until apply).
    func enableManual(fanId: Int, rpm: Int) {
        if mode == .curve { stopCurveMode(disableSetting: true) }
        mode = .manual
        manualFanIDs.insert(fanId)
        manualTargets[fanId] = rpm
    }

    func enableCurveMode() {
        mode = .curve
        manualFanIDs.removeAll()
        manualTargets.removeAll()
    }

    func disableCurve() {
        stopCurveMode(disableSetting: true)
    }

    private func stopCurveMode(disableSetting: Bool) {
        guard mode == .curve || AppSettings.shared.fanCurveEnabled else { return }
        let hadApplied = !appliedFanIDs.isEmpty
        mode = .auto
        curveTargets.removeAll()
        manualFanIDs.removeAll()
        manualTargets.removeAll()
        appliedFanIDs.removeAll()
        if disableSetting, AppSettings.shared.fanCurveEnabled {
            AppSettings.shared.fanCurveEnabled = false
        }
        if hadApplied { performAutoAll() }
    }

    /// Apply target RPM percent from the temperature curve to every fan.
    func applyCurve(percent: Double) {
        guard mode == .curve, supportsControl, !fans.isEmpty else { return }
        for fan in fans {
            let rpm = FanCurveInterpolator.targetRPM(for: fan, percent: percent)
            applyCurveRPM(fanId: fan.id, rpm: rpm)
        }
    }

    private func applyCurveRPM(fanId: Int, rpm: Int) {
        curveTargets[fanId] = rpm
        appliedFanIDs.insert(fanId)
        scheduleApply(fanId: fanId, rpm: rpm)
    }

    /// Leave manual mode. Returns the fans to automatic if anything was forced.
    func disableManual(fanId: Int) {
        manualFanIDs.remove(fanId)
        manualTargets[fanId] = nil
        let wasApplied = appliedFanIDs.remove(fanId) != nil
        let hwForced = fans.first(where: { $0.id == fanId })?.forced == true
        guard wasApplied || hwForced else { return }
        performAutoAll()
    }

    /// Slider moved — updates target in memory only (no privileged write).
    func updateManualRPM(fanId: Int, rpm: Int) {
        guard manualFanIDs.contains(fanId) else { return }
        manualTargets[fanId] = rpm
    }

    /// User explicitly confirms the manual RPM — triggers the privileged write.
    func applyManualRPM(fanId: Int, rpm: Int) {
        guard manualFanIDs.contains(fanId) else { return }
        manualTargets[fanId] = rpm
        appliedFanIDs.insert(fanId)
        scheduleApply(fanId: fanId, rpm: rpm)
    }

    /// Pre-authorize: install the helper now (one prompt) so later writes are
    /// instant. Safe to call repeatedly — a no-op once installed.
    func warmAuthorization() {
        controlQueue.async { [weak self] in
            let ok = self?.ensureHelperInstalled(userInitiated: true) ?? false
            DispatchQueue.main.async {
                self?.isAuthorized = ok
            }
        }
    }

    /// Probe daemon reachability without triggering install (for settings UI).
    func refreshHelperStatus() {
        DispatchQueue.main.async { [weak self] in
            self?.checkInstallingTimeout()
        }
        controlQueue.async { [weak self] in
            guard let self else { return }
            if let v = self.installedVersion() {
                DispatchQueue.main.async {
                    self.installingStartedAt = nil
                    self.installedHelperVersion = v
                    self.helperState = v >= FanXPC.version ? .ready : .notInstalled
                    self.isAuthorized = v >= FanXPC.version
                }
            } else {
                DispatchQueue.main.async {
                    self.installedHelperVersion = nil
                    if case .installing = self.helperState {
                        self.checkInstallingTimeout()
                        return
                    }
                    if case .declined = self.helperState { return }
                    if case .failed = self.helperState { return }
                    self.helperState = .notInstalled
                    self.isAuthorized = false
                }
            }
        }
    }

    private func checkInstallingTimeout() {
        guard case .installing = helperState,
              let start = installingStartedAt,
              Date().timeIntervalSince(start) > 120 else { return }
        installingStartedAt = nil
        helperState = .failed("Install timed out.".loc)
        lastError = "Install timed out.".loc
        isAuthorized = false
    }

    /// Remove the privileged helper (one admin prompt).
    func uninstallHelper() {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.connection?.invalidate()
            self.connection = nil
            let ok = self.runUninstaller()
            DispatchQueue.main.async {
                if ok {
                    self.helperState = .notInstalled
                    self.installedHelperVersion = nil
                    self.isAuthorized = false
                    self.lastError = nil
                }
            }
        }
    }

    func resetAllFans() {
        mode = .auto
        curveTargets.removeAll()
        let hadForced = fans.contains { $0.forced }
        manualFanIDs.removeAll()
        manualTargets.removeAll()
        let hadApplied = !appliedFanIDs.isEmpty
        appliedFanIDs.removeAll()
        guard hadApplied || hadForced else { return }
        performAutoAll()
    }

    /// Synchronous reset for app teardown (`applicationWillTerminate`). The
    /// persistent helper makes this instant and prompt-free; the daemon's own
    /// connection-invalidation handler is the ultimate guarantee if this is
    /// skipped (crash / SIGKILL).
    func resetAllFansSync(timeout: TimeInterval = 3) {
        guard helperState == .ready,
              !appliedFanIDs.isEmpty || fans.contains(where: { $0.forced }) else { return }
        let sem = DispatchSemaphore(value: 0)
        controlQueue.async { [weak self] in
            _ = self?.callAuto(allowInstall: false, probeTimeout: 0.5)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
    }

    // MARK: - Debounced privileged apply

    private func scheduleApply(fanId: Int, rpm: Int) {
        pendingApply = (fanId, rpm)
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let p = self.pendingApply else { return }
            self.pendingApply = nil
            self.controlQueue.async {
                let ok = self.callSetSpeed(id: p.id, rpm: p.rpm)
                DispatchQueue.main.async {
                    if ok { self.isAuthorized = true; self.lastError = nil }
                    else { self.lastError = self.lastError ?? "Fan control failed.".loc }
                }
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func performAutoAll() {
        controlQueue.async { [weak self] in
            guard let self else { return }
            let ok = self.callAuto()
            DispatchQueue.main.async {
                if ok { self.isAuthorized = true; self.lastError = nil }
            }
        }
    }

    // MARK: - Legacy (fpe2) reads

    private static func readLegacyFans() -> [FanInfo] {
        guard let count = try? SMCKit.fanCount(), count > 0 else { return [] }
        var out: [FanInfo] = []
        for id in 0..<count {
            guard let cur = try? SMCKit.fanCurrentSpeed(id) else { continue }
            let mn = (try? SMCKit.fanMinSpeed(id)) ?? 0
            let mx = (try? SMCKit.fanMaxSpeed(id)) ?? 0
            out.append(FanInfo(id: id, name: "Fan \(id + 1)", rpm: cur, targetRPM: cur,
                               minRPM: mn, maxRPM: mx, forced: false))
        }
        return out
    }

    // MARK: - XPC helper plumbing (controlQueue only)

    /// Existing or freshly created privileged connection. Must be called on
    /// `controlQueue`.
    private func helperConnection() -> NSXPCConnection? {
        if let c = connection { return c }
        let now = Date()
        guard now.timeIntervalSince(lastConnectionAttempt) >= Self.connectionBackoff else { return nil }
        lastConnectionAttempt = now
        let c = NSXPCConnection(machServiceName: FanXPC.machServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: FanControlHelperProtocol.self)
        c.invalidationHandler = { [weak self] in self?.controlQueue.async { self?.connection = nil } }
        c.interruptionHandler = { [weak self] in self?.controlQueue.async { self?.connection = nil } }
        c.resume()
        connection = c
        return c
    }

    private func proxy(timeoutFired: @escaping () -> Void) -> FanControlHelperProtocol? {
        guard let conn = helperConnection() else { return nil }
        return conn.remoteObjectProxyWithErrorHandler { _ in timeoutFired() }
            as? FanControlHelperProtocol
    }

    private func xpcCall(timeout: TimeInterval = 5,
                         _ body: (FanControlHelperProtocol, @escaping (Bool) -> Void) -> Void) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        var finished = false
        let lock = NSLock()
        func finish(_ v: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            ok = v
            sem.signal()
        }
        guard let p = proxy(timeoutFired: { finish(false) }) else { return false }
        body(p) { finish($0) }
        _ = sem.wait(timeout: .now() + timeout)
        return ok
    }

    private func xpcCallVersion(timeout: TimeInterval = 2) -> Int? {
        let sem = DispatchSemaphore(value: 0)
        var result: Int?
        var finished = false
        let lock = NSLock()
        func finish(_ v: Int?) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            result = v
            sem.signal()
        }
        guard let p = proxy(timeoutFired: { finish(nil) }) else { return nil }
        p.getVersion { finish($0) }
        _ = sem.wait(timeout: .now() + timeout)
        return result
    }

    /// Query the running daemon's version (nil if unreachable). controlQueue only.
    private func installedVersion(timeout: TimeInterval = 2) -> Int? {
        xpcCallVersion(timeout: timeout)
    }

    /// Poll the freshly bootstrapped daemon until it answers a version probe.
    /// launchd starts the service on-demand on the first connection, and the
    /// daemon then opens the SMC before it vends the Mach service, so the first
    /// few probes can miss. Rebuild the connection each attempt (bypassing the
    /// idle backoff) until `deadline`. controlQueue only.
    private func probeVersionAfterInstall(deadline: TimeInterval = 12) -> Int? {
        let end = Date().addingTimeInterval(deadline)
        repeat {
            connection?.invalidate()
            connection = nil
            lastConnectionAttempt = .distantPast
            if let v = xpcCallVersion(timeout: 2) { return v }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < end
        return nil
    }

    /// Ensure the helper is installed and current. controlQueue only. Returns
    /// true if the helper is usable afterwards.
    @discardableResult
    private func ensureHelperInstalled(userInitiated: Bool = false,
                                     allowInstall: Bool = true,
                                     probeTimeout: TimeInterval = 2) -> Bool {
        if helperState == .installing { return false }

        if !userInitiated {
            switch helperState {
            case .declined, .failed:
                if Date().timeIntervalSince(lastInstallAttempt) < Self.installCooldown {
                    return false
                }
            default:
                break
            }
        }

        if let v = installedVersion(timeout: probeTimeout), v >= FanXPC.version {
            DispatchQueue.main.async {
                self.installingStartedAt = nil
                self.helperState = .ready
                self.installedHelperVersion = v
                self.isAuthorized = true
            }
            return true
        }

        guard allowInstall else { return false }

        if let v = installedVersion(timeout: probeTimeout), v < FanXPC.version {
            DispatchQueue.main.async {
                self.lastError = "Fan helper needs an update — one administrator password will be requested.".loc
            }
        }

        connection?.invalidate()
        connection = nil
        lastInstallAttempt = Date()
        DispatchQueue.main.async {
            self.helperState = .installing
            self.installingStartedAt = Date()
        }

        guard runInstaller() else {
            DispatchQueue.main.async {
                self.installingStartedAt = nil
                let cancelled = self.lastError == "Authorization cancelled.".loc
                self.helperState = cancelled ? .declined : .failed(self.lastError ?? "Fan control failed.".loc)
            }
            return false
        }

        connection = nil
        if let v = probeVersionAfterInstall(), v >= FanXPC.version {
            DispatchQueue.main.async {
                self.installingStartedAt = nil
                self.helperState = .ready
                self.installedHelperVersion = v
                self.isAuthorized = true
                self.lastError = nil
            }
            return true
        }

        let cmd = "launchctl print system/\(FanXPC.helperLabel)"
        let msg = String(format: "Helper installed but the daemon did not start. Try reinstalling, or run: %@".loc, cmd)
        DispatchQueue.main.async {
            self.installingStartedAt = nil
            self.helperState = .failed(msg)
            self.lastError = msg
            self.isAuthorized = false
        }
        return false
    }

    private func callSetSpeed(id: Int, rpm: Int) -> Bool {
        guard ensureHelperInstalled() else { return false }
        // First engage on Apple Silicon can take ~6 s (thermalmonitord yield +
        // verified retry loop in the daemon) — give the XPC reply headroom.
        return xpcCall(timeout: 12) { proxy, done in
            proxy.setFanSpeed(id, rpm: rpm) { done($0) }
        }
    }

    private func callAuto(allowInstall: Bool = true, probeTimeout: TimeInterval = 2) -> Bool {
        guard ensureHelperInstalled(allowInstall: allowInstall, probeTimeout: probeTimeout) else { return false }
        return xpcCall { proxy, done in
            proxy.resetAllFans { done($0) }
        }
    }

    // MARK: - One-time privileged install (single admin prompt)

    /// Returns the bundled helper binary inside the app.
    private static func bundledHelperURL() -> URL? {
        if let u = Bundle.main.url(forAuxiliaryExecutable: "n1ko-fanctl") { return u }
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            for name in ["n1ko-fanctl", "FanHelper"] {
                let c = dir.appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: c.path) { return c }
            }
        }
        return nil
    }

    /// Install the daemon (binary + LaunchDaemon plist) via one
    /// `osascript ... with administrator privileges` call. controlQueue only.
    private func runInstaller() -> Bool {
        guard let helperSrc = Self.bundledHelperURL() else {
            DispatchQueue.main.async { self.lastError = "Fan helper not found in app bundle.".loc }
            return false
        }

        let plist = Self.launchDaemonPlist()
        let work = NSTemporaryDirectory() + "n1ko-install-" + ProcessInfo.processInfo.globallyUniqueString
        let plistTmp = work + "/helper.plist"
        let scriptTmp = work + "/install.sh"
        let script = Self.installScript(helperSrc: helperSrc.path, plistTmp: plistTmp)

        do {
            try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
            try plist.write(toFile: plistTmp, atomically: true, encoding: .utf8)
            try script.write(toFile: scriptTmp, atomically: true, encoding: .utf8)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            return false
        }
        defer { try? FileManager.default.removeItem(atPath: work) }

        let result = Self.runAsRoot(shellScriptPath: scriptTmp)
        switch result {
        case .success:
            return true
        case .failure(let msg):
            DispatchQueue.main.async { self.lastError = msg }
            return false
        }
    }

    private static func launchDaemonPlist() -> String {
        let team = Bundle.main.object(forInfoDictionaryKey: "N1KOTeamID") as? String
        let teamBlock: String
        if let team, !team.isEmpty {
            teamBlock = """
                <key>EnvironmentVariables</key>
                <dict>
                    <key>N1KO_TEAM_ID</key>
                    <string>\(team)</string>
                </dict>
            """
        } else {
            teamBlock = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(FanXPC.helperLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(FanXPC.helperToolPath)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(FanXPC.machServiceName)</key>
                <true/>
            </dict>
            \(teamBlock)
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
    }

    /// Build the privileged install script. Paths are single-quoted/escaped for
    /// /bin/sh.
    private func runUninstaller() -> Bool {
        let work = NSTemporaryDirectory() + "n1ko-uninstall-" + ProcessInfo.processInfo.globallyUniqueString
        let scriptTmp = work + "/uninstall.sh"
        let script = Self.uninstallScript()
        do {
            try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
            try script.write(toFile: scriptTmp, atomically: true, encoding: .utf8)
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            return false
        }
        defer { try? FileManager.default.removeItem(atPath: work) }
        switch Self.runAsRoot(shellScriptPath: scriptTmp) {
        case .success: return true
        case .failure(let msg):
            DispatchQueue.main.async { self.lastError = msg }
            return false
        }
    }

    private static func uninstallScript() -> String {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        #!/bin/sh
        set -e
        launchctl bootout system/\(FanXPC.helperLabel) 2>/dev/null || true
        rm -f \(q(FanXPC.launchDaemonPlistPath))
        rm -f \(q(FanXPC.helperToolPath))
        exit 0
        """
    }

    private static func installScript(helperSrc: String, plistTmp: String) -> String {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let label = FanXPC.helperLabel
        return """
        #!/bin/sh
        set -e
        mkdir -p /Library/PrivilegedHelperTools
        cp \(q(helperSrc)) \(q(FanXPC.helperToolPath))
        xattr -c \(q(FanXPC.helperToolPath)) 2>/dev/null || true
        chown root:wheel \(q(FanXPC.helperToolPath))
        chmod 544 \(q(FanXPC.helperToolPath))
        cp \(q(plistTmp)) \(q(FanXPC.launchDaemonPlistPath))
        xattr -c \(q(FanXPC.launchDaemonPlistPath)) 2>/dev/null || true
        chown root:wheel \(q(FanXPC.launchDaemonPlistPath))
        chmod 644 \(q(FanXPC.launchDaemonPlistPath))
        set +e
        # Remove any previous instance. launchd tears the job down
        # asynchronously, so wait until it is actually gone — bootstrapping
        # while teardown is in flight fails with "Bootstrap failed: 5:
        # Input/output error".
        launchctl bootout system/\(label) 2>/dev/null
        n=0
        while launchctl print system/\(label) >/dev/null 2>&1; do
            n=$((n+1)); [ "$n" -ge 20 ] && break
            sleep 0.5
        done
        # Clear any persisted disabled override before bootstrapping.
        launchctl enable system/\(label) 2>/dev/null
        n=0
        while :; do
            err=$(launchctl bootstrap system \(q(FanXPC.launchDaemonPlistPath)) 2>&1) && break
            n=$((n+1))
            if [ "$n" -ge 5 ]; then
                echo "bootstrap failed after $n attempts: $err" >&2
                exit 1
            fi
            sleep 1
        done
        exit 0
        """
    }

    private enum RootResult { case success; case failure(String) }

    private static func runAsRoot(shellScriptPath: String) -> RootResult {
        let cmd = "/bin/sh '" + shellScriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let errPipe = Pipe()
        p.standardError = errPipe
        do { try p.run(); p.waitUntilExit() } catch {
            return .failure(error.localizedDescription)
        }
        if p.terminationStatus == 0 { return .success }
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.contains("-128") || raw.lowercased().contains("cancel") {
            return .failure("Authorization cancelled.".loc)
        }
        return .failure(raw.isEmpty ? "Fan control failed.".loc : raw)
    }
}
