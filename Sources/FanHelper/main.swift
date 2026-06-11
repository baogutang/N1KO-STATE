import Foundation
import Security
import SMCKit
import FanXPCShared
import XPCAuditShim

// ============================================================================
// com.n1ko.state.monitor.helper — privileged fan-control LaunchDaemon.
//
// Runs as root, installed once into /Library/PrivilegedHelperTools by the app
// (single admin prompt). Vends `FanControlHelperProtocol` over a Mach service
// so the app can force fan speeds / return to auto with **no further password
// prompts**.
//
// Safety: each client connection's invalidationHandler returns the fans to
// automatic when the app process dies for ANY reason (clean quit, crash,
// SIGKILL, shutdown) — this is kernel-driven Mach port death, so it is the real
// guarantee that `FS!` never gets stuck in manual overnight.
//
// Threat model: with ad-hoc signing (no Developer ID) the strongest client
// check available is an `identifier "…"` code requirement. Anyone could ad-hoc
// sign a binary with the same identifier, so this is a sanity filter rather
// than a hard trust boundary. The exposed surface is deliberately tiny (fan RPM
// and auto/manual only), bounding the blast radius.
// ============================================================================

/// All SMC access funnels through one serial queue (the SMC connection is
/// global static state in SMCKit).
private let smcQueue = DispatchQueue(label: "com.n1ko.state.monitor.helper.smc", qos: .userInitiated)

private func log(_ msg: String) {
    FileHandle.standardError.write(Data(("n1ko-helper: " + msg + "\n").utf8))
}

private let fanDirtyPath = "/var/db/com.n1ko.state.monitor/fan.dirty"
private let fanDirtyDir = "/var/db/com.n1ko.state.monitor"

private func markFanDirty() {
    try? FileManager.default.createDirectory(atPath: fanDirtyDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: fanDirtyPath, contents: Data(), attributes: nil)
}

private func clearFanDirty() {
    do {
        try FileManager.default.removeItem(atPath: fanDirtyPath)
    } catch {
        log("clearFanDirty failed: \(error)")
    }
}

private func recoverDirtyFansIfNeeded() {
    guard FileManager.default.fileExists(atPath: fanDirtyPath) else { return }
    log("dirty marker found — returning fans to automatic")
    try? SMCKit.autoAllFans()
    clearFanDirty()
}

// MARK: - Service implementation (one instance per client connection)

final class HelperService: NSObject, FanControlHelperProtocol {

    /// Whether this connection has forced any fan, so we only reset on
    /// disconnect when we actually changed something.
    private var didForce = false
    /// Forced targets to re-assert periodically — thermalmonitord reclaims
    /// fan control within seconds unless the mode/target keys are kept
    /// written. smcQueue only.
    private var forcedTargets: [Int: Double] = [:]
    private var reassertTimer: DispatchSourceTimer?
    private var reassertFailures = 0

    func setFanSpeed(_ fanIndex: Int, rpm: Int, reply: @escaping (Bool) -> Void) {
        smcQueue.async {
            do {
                markFanDirty()
                try SMCKit.forceFan(fanIndex, rpm: Double(rpm))
                self.didForce = true
                self.forcedTargets[fanIndex] = Double(rpm)
                self.startReassertLocked()
                reply(true)
            } catch {
                log("setFanSpeed(\(fanIndex), \(rpm)) failed: \(error)")
                reply(false)
            }
        }
    }

    /// smcQueue only. Re-apply forced targets every 5 s so the OS thermal
    /// daemon's reclaim (and the firmware's Ftst reset on sleep) never leaves
    /// the UI claiming manual while the hardware drifted back to auto.
    private func startReassertLocked() {
        guard reassertTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: smcQueue)
        t.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.reassertLocked() }
        reassertTimer = t
        t.resume()
    }

    private func reassertLocked() {
        guard !forcedTargets.isEmpty else {
            reassertTimer?.cancel()
            reassertTimer = nil
            return
        }
        var anyFailed = false
        for (id, rpm) in forcedTargets {
            do { try SMCKit.forceFan(id, rpm: rpm) } catch {
                anyFailed = true
                log("reassert fan \(id) failed: \(error)")
            }
        }
        if anyFailed {
            reassertFailures += 1
            // The firmware keeps refusing manual mode — stop pretending.
            // Returning to auto keeps hardware truth and UI in agreement
            // (the app's reconcile loop picks the change up within 30 s).
            if reassertFailures >= 3 {
                log("manual mode rejected \(reassertFailures)x — giving up, back to auto")
                stopForcingLocked()
                try? SMCKit.autoAllFans()
                clearFanDirty()
                didForce = false
            }
        } else {
            reassertFailures = 0
        }
    }

    /// smcQueue only.
    private func stopForcingLocked() {
        forcedTargets.removeAll()
        reassertTimer?.cancel()
        reassertTimer = nil
    }

    func setFanMode(_ manual: Bool, reply: @escaping (Bool) -> Void) {
        // Engaging manual without a target is meaningless on the FS! model, so
        // `manual == true` is a no-op success; the real manual write happens via
        // setFanSpeed. `manual == false` returns everything to automatic.
        if manual {
            reply(true)
            return
        }
        smcQueue.async {
            do {
                self.stopForcingLocked()
                try SMCKit.autoAllFans()
                clearFanDirty()
                self.didForce = false
                reply(true)
            } catch {
                log("setFanMode(auto) failed: \(error)")
                reply(false)
            }
        }
    }

    func resetAllFans(reply: @escaping (Bool) -> Void) {
        smcQueue.async {
            do {
                self.stopForcingLocked()
                try SMCKit.autoAllFans()
                clearFanDirty()
                self.didForce = false
                reply(true)
            } catch {
                log("resetAllFans failed: \(error)")
                reply(false)
            }
        }
    }

    func getCurrentFanState(reply: @escaping (Data?) -> Void) {
        smcQueue.async {
            let mode = SMCKit.readFanModeSwitch().map { Int($0) } ?? -1
            let fans = SMCKit.readFloatFans().map {
                FanReadingPayload(id: $0.id, current: $0.current, min: $0.min,
                                  max: $0.max, target: $0.target, forced: $0.forced)
            }
            let payload = FanStatePayload(mode: mode, fans: fans)
            reply(try? JSONEncoder().encode(payload))
        }
    }

    func getVersion(reply: @escaping (Int) -> Void) {
        reply(FanXPC.version)
    }

    /// Called when the owning connection drops. Returns fans to automatic if
    /// this client had forced any — the overnight-stuck-in-manual safeguard.
    /// `didForce` is only ever touched on `smcQueue`, so check it there too.
    func connectionDidEnd() {
        smcQueue.async {
            self.stopForcingLocked()
            guard self.didForce else { return }
            self.didForce = false
            do {
                try SMCKit.autoAllFans()
                clearFanDirty()
            } catch { log("auto-reset on disconnect failed: \(error)") }
        }
    }
}

// MARK: - Listener delegate (validates and wires up each connection)

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isClientTrusted(newConnection) else {
            log("rejected connection: client failed code requirement")
            return false
        }

        let service = HelperService()
        newConnection.exportedInterface = NSXPCInterface(with: FanControlHelperProtocol.self)
        newConnection.exportedObject = service

        bumpConnections()
        newConnection.invalidationHandler = {
            service.connectionDidEnd()
            dropConnection()
        }
        newConnection.interruptionHandler = {
            service.connectionDidEnd()
            dropConnection()
        }

        newConnection.resume()
        return true
    }

    /// Validate the caller's code signature against `FanXPC.clientRequirement`
    /// using its audit token (race-free, unlike PID-based checks).
    private func isClientTrusted(_ connection: NSXPCConnection) -> Bool {
        guard let tokenData = XPCAuditCopyAuditTokenData(connection) else {
            log("no audit token available for connection")
            return false
        }
        let attrs: [CFString: Any] = [kSecGuestAttributeAudit: tokenData]
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs as CFDictionary, [], &code) == errSecSuccess,
              let code else {
            return false
        }
        var requirement: SecRequirement?
        let requirementText = clientRequirementString()
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func clientRequirementString() -> String {
        if let team = ProcessInfo.processInfo.environment["N1KO_TEAM_ID"], !team.isEmpty {
            return "identifier \"com.n1ko.state.monitor\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        }
        return FanXPC.clientRequirement
    }
}

// MARK: - Idle exit (release SMC when no clients)

/// Connection bookkeeping state. XPC invokes the listener delegate and the
/// invalidation handlers on arbitrary threads, so all access is funneled
/// through `smcQueue`.
private var activeConnections = 0
private var idleTimer: DispatchSourceTimer?

private func bumpConnections() {
    smcQueue.async {
        activeConnections += 1
        idleTimer?.cancel()
        idleTimer = nil
    }
}

private func dropConnection() {
    smcQueue.async {
        activeConnections = max(0, activeConnections - 1)
        scheduleIdleExitIfNeeded()
    }
}

private func scheduleIdleExitIfNeeded() {
    guard activeConnections == 0 else { return }
    let timer = DispatchSource.makeTimerSource(queue: smcQueue)
    timer.schedule(deadline: .now() + 300)
    timer.setEventHandler {
        guard activeConnections == 0 else { return }
        if SMCKit.readFloatFans().contains(where: { $0.forced }) {
            log("idle timeout deferred — forced fans still active")
            scheduleIdleExitIfNeeded()
            return
        }
        log("idle timeout — exiting")
        _ = SMCKit.close()
        exit(EXIT_SUCCESS)
    }
    idleTimer?.cancel()
    idleTimer = timer
    timer.resume()
}

// MARK: - Bootstrap

do { try SMCKit.open() } catch {
    log("FATAL: could not open SMC: \(error)")
    exit(EXIT_FAILURE)
}

recoverDirtyFansIfNeeded()

// Belt-and-suspenders: on a clean daemon shutdown (launchctl bootout / SIGTERM)
// make sure we never leave the fans pinned. DispatchSourceSignal handlers run
// on the daemon's run loop, so this is async-signal-safe.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: smcQueue)
sigterm.setEventHandler {
    try? SMCKit.autoAllFans()
    _ = SMCKit.close()
    exit(EXIT_SUCCESS)
}
sigterm.resume()

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: FanXPC.machServiceName)
listener.delegate = delegate
listener.resume()

log("listening on \(FanXPC.machServiceName) (v\(FanXPC.version))")
RunLoop.main.run()
