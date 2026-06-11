import Foundation

// ============================================================================
// Shared XPC contract between the N1KO-STATE app (client) and the privileged
// fan-control daemon (server). Both targets depend on this library so the
// protocol, wire types, and well-known paths stay in exact lockstep.
// ============================================================================

/// Well-known identifiers and paths for the privileged helper. Kept in one
/// place so the daemon, the installer, and the client can never disagree.
public enum FanXPC {

    /// Mach service the daemon vends and the client connects to. Must match the
    /// `MachServices` key in the LaunchDaemon plist exactly.
    public static let machServiceName = "com.n1ko.state.monitor.helper"

    /// launchd Label for the daemon (also the plist filename stem).
    public static let helperLabel = "com.n1ko.state.monitor.helper"

    /// Where the privileged binary is installed (root:wheel, 0544).
    public static let helperToolPath = "/Library/PrivilegedHelperTools/com.n1ko.state.monitor.helper"

    /// Where the LaunchDaemon plist is installed (root:wheel, 0644).
    public static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.n1ko.state.monitor.helper.plist"

    /// Code-signing requirement the daemon enforces on connecting clients.
    ///
    /// Ad-hoc signing (no Developer ID) cannot satisfy a Team-ID / `anchor apple`
    /// requirement, but an ad-hoc signature *does* embed the signing identifier,
    /// so `identifier "…"` is the strongest build-stable check available. It is a
    /// sanity filter, not a hard trust boundary — see the threat-model note in
    /// the daemon. The blast radius (fan RPM only) is intentionally small.
    public static let clientRequirement = "identifier \"com.n1ko.state.monitor\""

    /// Helper protocol version. Bumped whenever the installed binary's behaviour
    /// changes so the client can detect a stale daemon and reinstall.
    /// v2: Apple Silicon manual mode rework — Ftst unlock, verified mode engage,
    /// periodic re-assert against thermalmonitord reclaim.
    public static let version = 2
}

/// The privileged operations the daemon exposes over XPC. Every signature is
/// Objective-C representable (required by NSXPC): primitives, `Data`, and
/// `@escaping` reply closures only.
@objc public protocol FanControlHelperProtocol {

    /// Force `fanIndex` to `rpm` (clamped to the fan's min/max). Replies `true`
    /// on success.
    func setFanSpeed(_ fanIndex: Int, rpm: Int, reply: @escaping (Bool) -> Void)

    /// Switch global fan mode: `manual == false` returns *all* fans to automatic
    /// (writes `FS! = 0`). Manual mode is engaged per-fan via `setFanSpeed`.
    func setFanMode(_ manual: Bool, reply: @escaping (Bool) -> Void)

    /// Return every fan to automatic control (`FS! = 0`).
    func resetAllFans(reply: @escaping (Bool) -> Void)

    /// Current SMC fan state as a JSON-encoded `FanStatePayload` (nil on read
    /// failure). Sent as `Data` rather than `[String: Any]` to keep the NSXPC
    /// interface free of class-whitelisting and fully type-checked.
    func getCurrentFanState(reply: @escaping (Data?) -> Void)

    /// The running daemon's `FanXPC.version`, for stale-helper detection.
    func getVersion(reply: @escaping (Int) -> Void)
}

/// One fan's live values as read from the SMC float keys. Mirrors the app-side
/// `FanInfo` but lives here so it can cross the XPC boundary.
public struct FanReadingPayload: Codable {
    public let id: Int
    public let current: Double
    public let min: Double
    public let max: Double
    public let target: Double
    public let forced: Bool

    public init(id: Int, current: Double, min: Double, max: Double, target: Double, forced: Bool) {
        self.id = id
        self.current = current
        self.min = min
        self.max = max
        self.target = target
        self.forced = forced
    }
}

/// Snapshot of fan state returned by `getCurrentFanState`.
public struct FanStatePayload: Codable {
    /// Raw `FS! ` value: 0 = automatic, i+1 = fan `i` forced manual. -1 if the
    /// machine has no global mode switch.
    public let mode: Int
    public let fans: [FanReadingPayload]

    public init(mode: Int, fans: [FanReadingPayload]) {
        self.mode = mode
        self.fans = fans
    }
}
