import Foundation

// Apple Silicon (and recent Intel) Macs expose fan keys as IEEE-754 floats
// ("flt ") rather than the legacy fpe2 encoding the original SMCKit assumes:
//
//   FS!  ui8    global mode: 0 = auto, 1 = manual fan 0, 2 = manual fan 1, …
//   F<i>Ac float   actual RPM (read)
//   F<i>Tg float   target RPM (write, manual)
//   F<i>Mn float   minimum RPM
//   F<i>Mx float   maximum RPM
//
// Per-fan F<i>Md exists on some machines but FS! is the authoritative switch on
// Apple Silicon. Writes require root (privileged helper).

/// A live snapshot of one fan read via the float keys.
public struct FanFloatReading {
    public let id: Int
    public let current: Double
    public let min: Double
    public let max: Double
    public let target: Double
    public let forced: Bool
}

public extension SMCKit {

    private static let fltType = DataType(type: FourCharCode(fromStaticString: "flt "), size: 4)
    /// SMC keys are always four characters; the fan mode switch is `FS!` padded.
    private static let fsModeKey = "FS! "

    private static func readFloat(_ code: String) throws -> Double {
        let key = SMCKey(code: FourCharCode(fromString: code), info: fltType)
        let d = try readData(key)
        var bits = UInt32(d.0)
        bits |= UInt32(d.1) << 8
        bits |= UInt32(d.2) << 16
        bits |= UInt32(d.3) << 24
        return Double(Float(bitPattern: bits))
    }

    private static func readUInt8(_ code: String) throws -> UInt8 {
        let key = SMCKey(code: FourCharCode(fromString: code), info: DataTypes.UInt8)
        return try readData(key).0
    }

    private static func writeFloat(_ code: String, _ value: Double) throws {
        let bits = Float(value).bitPattern
        var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        bytes.0 = UInt8(bits & 0xff)
        bytes.1 = UInt8((bits >> 8) & 0xff)
        bytes.2 = UInt8((bits >> 16) & 0xff)
        bytes.3 = UInt8((bits >> 24) & 0xff)
        let key = SMCKey(code: FourCharCode(fromString: code), info: fltType)
        try writeData(key, data: bytes)
    }

    private static func writeUInt8(_ code: String, _ value: UInt8) throws {
        var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        bytes.0 = value
        let key = SMCKey(code: FourCharCode(fromString: code), info: DataTypes.UInt8)
        try writeData(key, data: bytes)
    }

    /// True when this Mac exposes float-encoded fan keys (Apple Silicon / recent).
    static func hasFloatFans() -> Bool {
        (try? keyInformation(FourCharCode(fromString: "F0Ac"))) != nil
    }

    /// `Ftst` (force/test) diagnostic flag. On M3/M4-era firmwares
    /// thermalmonitord blocks fan mode writes until this is set to 1; absent on
    /// M1 and M5 firmwares. See github.com/agoodkind/macos-smc-fan.
    private static let ftstKey = "Ftst"

    private static func hasKey(_ code: String) -> Bool {
        (try? keyInformation(FourCharCode(fromString: code))) != nil
    }

    /// Per-fan mode key with casing resolved at runtime: older firmwares use
    /// `F0Md`, M5-era (macOS 26 firmwares) renamed it to `F0md`. Cached —
    /// all SMC access is already serialized by the callers' queues.
    private static var modeKeyCache: [Int: String?] = [:]

    static func fanModeKey(_ id: Int) -> String? {
        if let cached = modeKeyCache[id] { return cached }
        let resolved = ["F\(id)Md", "F\(id)md"].first(where: hasKey)
        modeKeyCache[id] = resolved
        return resolved
    }

    /// True when the global `FS!` fan-mode key exists on this machine.
    static func hasFSModeSwitch() -> Bool {
        (try? keyInformation(FourCharCode(fromString: fsModeKey))) != nil
    }

    /// Global fan mode from `FS!` (nil if key missing — fall back to per-fan `F*Md`).
    static func readFanModeSwitch() -> UInt8? {
        guard hasFSModeSwitch() else { return nil }
        return try? readUInt8(fsModeKey)
    }

    static func writeFanModeSwitch(_ value: UInt8) throws {
        try writeUInt8(fsModeKey, value)
    }

    /// Read all fans via the float keys. Returns [] if unavailable.
    static func readFloatFans() -> [FanFloatReading] {
        guard let count = try? fanCount(), count > 0 else { return [] }
        let fsMode = readFanModeSwitch()
        var out: [FanFloatReading] = []
        for i in 0..<count {
            guard let cur = try? readFloat("F\(i)Ac") else { continue }
            let mn = (try? readFloat("F\(i)Mn")) ?? 0
            let mx = (try? readFloat("F\(i)Mx")) ?? 0
            let tg = (try? readFloat("F\(i)Tg")) ?? 0
            let md = fanModeKey(i).flatMap { try? readUInt8($0) } ?? 0
            let forced: Bool
            if let fs = fsMode {
                forced = fs == UInt8(i + 1)
            } else {
                forced = (md & 1) == 1
            }
            out.append(FanFloatReading(id: i, current: cur, min: mn, max: mx,
                                       target: tg, forced: forced))
        }
        return out
    }

    /// Force one fan to a target RPM (clamped). Requires root.
    ///
    /// Intel: the global `FS!` bitmask switch.
    /// Apple Silicon: thermalmonitord/RTKit own the fans. Where the `Ftst`
    /// diagnostic flag exists (M3/M4) it must be set first so the daemon
    /// yields — which takes seconds — and some firmwares silently discard the
    /// mode write, so the engage is verified by read-back and retried until a
    /// deadline. See github.com/agoodkind/macos-smc-fan.
    static func forceFan(_ id: Int, rpm: Double) throws {
        let mn = (try? readFloat("F\(id)Mn")) ?? 0
        guard let mx = try? readFloat("F\(id)Mx") else {
            throw SMCError.unsafeFanSpeed
        }
        let clamped = Swift.min(Swift.max(rpm, mn), mx)

        if hasFSModeSwitch() {
            try writeFloat("F\(id)Tg", clamped)
            try writeFanModeSwitch(UInt8(id + 1))
            return
        }

        guard let mk = fanModeKey(id) else {
            throw SMCError.keyNotFound(code: "F\(id)Md")
        }

        if hasKey(ftstKey) { try? writeUInt8(ftstKey, 1) }
        try? writeFloat("F\(id)Tg", clamped)

        var engaged = (try? readUInt8(mk)) == 1
        let deadline = Date().addingTimeInterval(6)
        while !engaged && Date() < deadline {
            try? writeUInt8(mk, 1)
            Thread.sleep(forTimeInterval: 0.15)
            engaged = (try? readUInt8(mk)) == 1
        }
        guard engaged else { throw SMCError.fanModeRejected }

        // Re-write the target now that manual mode actually holds.
        try writeFloat("F\(id)Tg", clamped)
    }

    /// Return every fan to automatic control. Requires root.
    static func autoAllFans() throws {
        if hasFSModeSwitch() {
            try writeFanModeSwitch(0)
            return
        }
        let count = (try? fanCount()) ?? 0
        for i in 0..<count {
            if let mk = fanModeKey(i) { try? writeUInt8(mk, 0) }
        }
        // Hand control back to thermalmonitord on Ftst firmwares.
        if hasKey(ftstKey) { try? writeUInt8(ftstKey, 0) }
    }

    /// Return one fan slot to automatic (uses global auto when `FS!` is present).
    static func autoFan(_ id: Int) throws {
        if hasFSModeSwitch() {
            try autoAllFans()
        } else if let mk = fanModeKey(id) {
            try writeUInt8(mk, 0)
        }
    }
}
