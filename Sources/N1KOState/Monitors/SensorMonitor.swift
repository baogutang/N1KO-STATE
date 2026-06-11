import Foundation
import Combine
import Darwin
import SMCKit

/// A single temperature sensor reading.
struct TemperatureReading: Identifiable, Hashable {
    let id: String          // unique id
    let label: String       // localizable bucket/name key
    let celsius: Double
    /// When a bucket has several sensors, a 1-based index for disambiguation.
    var ordinal: Int? = nil
}

/// Reads hardware temperature sensors. (Fans are handled by `FanController`.)
///
/// Two data sources are used, in priority order:
/// 1. **IOHIDEventSystem** (Apple Silicon + Intel T2): real on-die / battery /
///    SSD temperatures. Cryptic per-sensor names (e.g. `PMU tdie3`) are grouped
///    into readable buckets (SoC, Battery, SSD, …).
/// 2. **SMC** (vendored `SMCKit`): Intel-era named keys (TC0P, TG0P, …) used as
///    a fallback when no HID sensors exist. Fans are always read from the SMC.
///
/// Reading needs no sandbox exception and no root.
final class SensorMonitor: ObservableObject {

    @Published private(set) var temperatures: [TemperatureReading] = []
    /// Every individual sensor (ungrouped), hottest first. This is the most
    /// granular view the OS exposes — note Apple Silicon does NOT publish a
    /// temperature per logical CPU core, so this lists SoC/cluster/GPU/battery/
    /// SSD die sensors rather than one-per-core.
    @Published private(set) var detailedTemperatures: [TemperatureReading] = []
    @Published private(set) var isAvailable = false
    @Published private(set) var lastError: String?
    /// Hottest individual sensor in °C (for the card header / summaries).
    @Published private(set) var peakCelsius: Double?

    /// Shared serial queue so the SMC connection (global static state) is never
    /// hit concurrently by the sensor and fan readers.
    private let queue = smcAccessQueue
    private var didOpen = false
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 2.0
    private var inFlight = false
    /// Discovered once: only the SMC sensors actually present on this Mac.
    private var presentSensors: [TemperatureSensor]?
    /// HID temperature reader (nil on platforms that don't expose it).
    private var hid: IOHIDSensors?

    init() {
        open()
    }

    deinit {
        if didOpen { SMCKit.close() }
    }

    private func open() {
        DiagLog.log("SensorMonitor", "initializing temperature backends")
        queue.async { [weak self] in
            let hid = IOHIDSensors()
            let smcOK: Bool
            do {
                try SMCKit.open()
                smcOK = true
                DiagLog.log("SensorMonitor", "SMCKit.open succeeded")
            } catch {
                smcOK = false
                DiagLog.log("SensorMonitor", "SMCKit.open failed: \(error)")
            }
            if hid != nil {
                DiagLog.log("SensorMonitor", "IOHID temperature path available")
            }
            DispatchQueue.main.async {
                self?.hid = hid
                self?.didOpen = smcOK
                self?.isAvailable = (hid != nil) || smcOK
                self?.lastError = (hid == nil && !smcOK)
                    ? "No temperature sensors available."
                    : nil
            }
        }
    }

    /// Sample temperatures + fans. Throttled, safe to call every tick.
    func refresh() {
        guard isAvailable else { return }
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= minInterval, !inFlight else { return }
        lastRun = now
        inFlight = true
        queue.async { [weak self] in
            guard let self else { return }

            var raw = self.hid?.readAll() ?? []
            var temps: [TemperatureReading]
            var detailed: [TemperatureReading]

            if !raw.isEmpty {
                temps = SensorMonitor.grouped(raw)
                detailed = SensorMonitor.individual(raw)
            } else {
                // Intel SMC fallback: discover present keys once, then read.
                if self.presentSensors == nil {
                    if let cached = Self.loadCachedSensors() {
                        self.presentSensors = cached
                    } else if let discovered = try? SMCKit.allKnownTemperatureSensors(), !discovered.isEmpty {
                        self.presentSensors = discovered
                        Self.saveCachedSensors(discovered)
                    } else {
                        self.presentSensors = []
                    }
                }
                temps = SensorMonitor.readTemperatures(self.presentSensors ?? [])
                detailed = temps
                raw = temps.map { ($0.label, $0.celsius) }
            }

            let peak = raw.map(\.1).max()
            DispatchQueue.main.async {
                self.temperatures = temps
                self.detailedTemperatures = detailed
                self.peakCelsius = peak
                self.inFlight = false
            }
        }
    }

    // MARK: - Grouping (IOHID)

    /// Collapse dozens of cryptic HID sensors into a handful of readable rows.
    /// SoC is averaged across its many die sensors; everything else takes the
    /// hottest reading in its bucket.
    static func grouped(_ raw: [(name: String, celsius: Double)]) -> [TemperatureReading] {
        guard !raw.isEmpty else { return [] }
        var buckets: [String: [Double]] = [:]
        for r in raw {
            buckets[bucket(for: r.name), default: []].append(r.celsius)
        }
        // Fixed display order; only non-empty buckets are emitted.
        let order = ["SoC", "GPU", "Battery", "SSD", "Display", "Airflow", "Power", "Other"]
        var out: [TemperatureReading] = []
        for key in order {
            guard let vals = buckets[key], !vals.isEmpty else { continue }
            let value = (key == "SoC")
                ? vals.reduce(0, +) / Double(vals.count)
                : (vals.max() ?? 0)
            out.append(TemperatureReading(id: key, label: key, celsius: value))
        }
        return out
    }

    /// Individual sensors with human-readable roles (CPU die, GPU, battery, …)
    /// instead of cryptic HID names like "PMU tcal". Sorted hottest first.
    static func individual(_ raw: [(name: String, celsius: Double)]) -> [TemperatureReading] {
        var counts: [String: Int] = [:]
        var out: [TemperatureReading] = []
        for r in raw.sorted(by: { $0.celsius > $1.celsius }) {
            let label = friendlySensorLabel(for: r.name)
            let n = (counts[label] ?? 0) + 1
            counts[label] = n
            let id = n == 1 ? label : "\(label)-\(n)"
            out.append(TemperatureReading(id: id, label: label, celsius: r.celsius,
                                        ordinal: n > 1 ? n : nil))
        }
        return out
    }

    /// Map a raw HID sensor name to a localization key (English lookup key).
    static func friendlySensorLabel(for rawName: String) -> String {
        let n = rawName.lowercased()
        if n.contains("gpu") { return "GPU die" }
        if n.contains("batt") || n.contains("gas gauge") { return "Battery" }
        if n.contains("nand") || n.contains("ssd") || n.contains("flash") { return "SSD" }
        if n.contains("display") || n.contains("lcd") { return "Display panel" }
        if n.contains("airflow") || n.contains("ambient") { return "Ambient" }
        if n.contains("tcal") { return "CPU calibration" }
        if n.contains("tdev") { return "CPU device" }
        if n.contains("tdie") { return "CPU die" }
        if n.hasPrefix("pmu") || n.contains("soc") || n.contains("cpu") { return "CPU die" }
        if n.contains("ane") { return "Neural Engine" }
        if n.contains("pwr") || n.contains("power") { return "Power stage" }
        return "Other sensor"
    }

    /// Heuristic mapping from a raw HID sensor name to a display bucket key.
    /// Keys double as localization keys (`sensor.bucket.<key>`).
    private static func bucket(for rawName: String) -> String {
        let n = rawName.lowercased()
        if n.contains("batt") || n.contains("gas gauge") { return "Battery" }
        if n.contains("nand") || n.contains("ssd") || n.contains("flash") { return "SSD" }
        if n.contains("display") || n.contains("lcd") || n.contains("backlight") { return "Display" }
        if n.contains("airflow") || n.contains("ambient") || n.contains("env") { return "Airflow" }
        if n.contains("gpu") { return "GPU" }
        if n.contains("tdie") || n.contains("tdev") || n.contains("tcal")
            || n.contains("soc") || n.contains("cpu") || n.hasPrefix("pmu") { return "SoC" }
        if n.contains("pwr") || n.contains("power") || n.contains("vrm") { return "Power" }
        return "Other"
    }

    // MARK: - SMC reads (run on `queue`)

    private static func readTemperatures(_ sensors: [TemperatureSensor]) -> [TemperatureReading] {
        var out: [TemperatureReading] = []
        for sensor in sensors {
            guard let c = try? SMCKit.temperature(sensor.code) else { continue }
            // Filter obviously-bogus readings (disconnected sensors report 0/—).
            guard c > 1, c < 130 else { continue }
            out.append(
                TemperatureReading(
                    id: sensor.code.toString(),
                    label: prettify(sensor.name),
                    celsius: c
                )
            )
        }
        return out.sorted { $0.label < $1.label }
    }

    private static func prettify(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    // MARK: - Intel SMC sensor list cache (per machine model)

    private struct SensorCacheFile: Codable {
        var model: String
        var sensors: [CachedSensor]
    }

    private struct CachedSensor: Codable {
        var name: String
        var code: String
    }

    private static var sensorCacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("N1KO-STATE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sensors.json")
    }

    private static func currentModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buf)
    }

    private static func loadCachedSensors() -> [TemperatureSensor]? {
        guard let data = try? Data(contentsOf: sensorCacheURL),
              let file = try? JSONDecoder().decode(SensorCacheFile.self, from: data),
              file.model == currentModel() else { return nil }
        return file.sensors.compactMap { item in
            guard item.code.count == 4 else { return nil }
            return TemperatureSensor(name: item.name, code: FourCharCode(fromString: item.code))
        }
    }

    private static func saveCachedSensors(_ sensors: [TemperatureSensor]) {
        let payload = SensorCacheFile(
            model: currentModel(),
            sensors: sensors.map { CachedSensor(name: $0.name, code: $0.code.toString()) }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: sensorCacheURL, options: .atomic)
    }
}
