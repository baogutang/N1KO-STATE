import Foundation
import Combine
import IOKit
import IOKit.ps

/// Battery / power monitor.
///
/// Primary state (charge %, charging, power source, time remaining) comes from
/// the public `IOPowerSources` API; richer detail (cycle count, design vs. max
/// capacity for health, temperature, instantaneous power draw) comes from the
/// `AppleSmartBattery` IORegistry entry. Desktops with no battery report
/// `isPresent == false`, and sampling stops after the first probe.
final class BatteryMonitor: ObservableObject {

    private(set) var isPresent = false
    private(set) var percentage: Double = 0
    private(set) var isCharging = false
    private(set) var isCharged = false
    private(set) var onACPower = false

    private(set) var minutesToEmpty: Int?
    private(set) var minutesToFull: Int?

    private(set) var cycleCount: Int?
    private(set) var healthFraction: Double?
    private(set) var temperatureC: Double?
    private(set) var watts: Double?
    private(set) var designCapacity: Int?
    private(set) var maxCapacity: Int?

    private(set) var history: [Double] = []
    let historyCapacity = 300
    private lazy var historyBuffer = RingBuffer<Double>(capacity: historyCapacity)

    private var desktopConfirmed = false
    private var notificationInstalled = false
    private var powerRunLoopSource: CFRunLoopSource?
    private var lastSmartBatteryRead = Date.distantPast
    private let smartBatteryInterval: TimeInterval = 300
    private let foregroundSmartBatteryInterval: TimeInterval = 60
    private var missingPowerSourceReads = 0
    private let missingPowerSourceConfirmations = 3

    private struct SmartBatterySnapshot {
        var cycleCount: Int?
        var healthFraction: Double?
        var temperatureC: Double?
        var watts: Double?
        var designCapacity: Int?
        var maxCapacity: Int?
    }

    /// Health is considered degraded below this fraction (matches Apple's
    /// "Service Recommended" guidance around 80%).
    var conditionOK: Bool? {
        guard let h = healthFraction else { return nil }
        return h >= 0.80
    }

    deinit {
        if let src = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    func start() {
        readPowerSources()
        if isPresent {
            refreshSmartBattery(force: true)
            installPowerNotification()
        } else {
            desktopConfirmed = true
        }
    }

    func shouldPollFromTick(popoverOpen: Bool, menuBarShowsBattery: Bool, alertNeedsBattery: Bool) -> Bool {
        if desktopConfirmed { return false }
        return popoverOpen || menuBarShowsBattery || alertNeedsBattery
    }

    func refreshFromTick(popoverOpen: Bool) {
        guard !desktopConfirmed else { return }
        PerformanceDiagnostics.measure(.samplerBattery) {
            readPowerSources()
            if isPresent {
                historyBuffer.append(percentage)
                history = historyBuffer.elements
                refreshSmartBattery(foreground: popoverOpen)
                objectWillChange.send()
            }
        }
    }

    func refreshSmartBattery(force: Bool = false, foreground: Bool = false) {
        guard !desktopConfirmed, isPresent else { return }
        let now = Date()
        let interval = foreground ? foregroundSmartBatteryInterval : smartBatteryInterval
        guard force || now.timeIntervalSince(lastSmartBatteryRead) >= interval else { return }
        lastSmartBatteryRead = now
        monitorWorkQueue.async { [weak self] in
            PerformanceDiagnostics.measure(.samplerBattery) {
                let snapshot = Self.readSmartBatterySnapshot()
                DispatchQueue.main.async {
                    self?.applySmartBatterySnapshot(snapshot)
                }
            }
        }
    }

    /// Legacy full refresh.
    func refresh() {
        refreshFromTick(popoverOpen: true)
    }

    private func installPowerNotification() {
        guard !notificationInstalled else { return }
        notificationInstalled = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.readPowerSources()
                monitor.objectWillChange.send()
            }
        }, context)?.takeRetainedValue() else { return }
        powerRunLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    // MARK: - IOPowerSources (charge %, charging, source, time remaining)

    private func readPowerSources() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else {
            missingPowerSourceReads += 1
            if missingPowerSourceReads >= missingPowerSourceConfirmations {
                isPresent = false
                desktopConfirmed = true
            }
            return
        }

        let present = (desc[kIOPSIsPresentKey] as? Bool) ?? false
        guard present else {
            missingPowerSourceReads += 1
            if missingPowerSourceReads >= missingPowerSourceConfirmations {
                isPresent = false
                desktopConfirmed = true
            }
            return
        }
        missingPowerSourceReads = 0
        desktopConfirmed = false
        isPresent = true

        let cur = (desc[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let max = (desc[kIOPSMaxCapacityKey] as? Int) ?? 100
        percentage = max > 0 ? Double(cur) / Double(max) : 0

        isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        isCharged = (desc[kIOPSIsChargedKey] as? Bool) ?? false
        onACPower = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        minutesToEmpty = positiveOrNil(desc[kIOPSTimeToEmptyKey] as? Int)
        minutesToFull = positiveOrNil(desc[kIOPSTimeToFullChargeKey] as? Int)
    }

    /// IOPowerSources reports `-1` while estimating; map that to `nil`.
    private func positiveOrNil(_ v: Int?) -> Int? {
        guard let v, v > 0 else { return nil }
        return v
    }

    // MARK: - AppleSmartBattery (cycles, health, temperature, power)

    private static func readSmartBatterySnapshot() -> SmartBatterySnapshot {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return SmartBatterySnapshot()
        }
        // IOServiceGetMatchingService consumes the matching dictionary reference.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return SmartBatterySnapshot()
        }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return SmartBatterySnapshot()
        }

        let cycleCount = props["CycleCount"] as? Int
        let design = props["DesignCapacity"] as? Int
        let rawMax = (props["AppleRawMaxCapacity"] as? Int)
            ?? (props["NominalChargeCapacity"] as? Int)
            ?? (props["MaxCapacity"] as? Int)
        let health: Double?
        if let d = design, d > 0, let m = rawMax, m > 0 {
            health = min(Double(m) / Double(d), 1.0)
        } else {
            health = nil
        }

        let temperature: Double?
        if let temp = props["Temperature"] as? Int {
            temperature = Double(temp) / 100.0
        } else {
            temperature = nil
        }

        let power: Double?
        if let mV = props["Voltage"] as? Int {
            let mA = (props["Amperage"] as? Int) ?? 0
            power = (Double(mV) / 1000.0) * (Double(mA) / 1000.0)
        } else {
            power = nil
        }

        return SmartBatterySnapshot(cycleCount: cycleCount,
                                    healthFraction: health,
                                    temperatureC: temperature,
                                    watts: power,
                                    designCapacity: design,
                                    maxCapacity: rawMax)
    }

    private func applySmartBatterySnapshot(_ snapshot: SmartBatterySnapshot) {
        cycleCount = snapshot.cycleCount
        healthFraction = snapshot.healthFraction
        temperatureC = snapshot.temperatureC
        watts = snapshot.watts
        designCapacity = snapshot.designCapacity
        maxCapacity = snapshot.maxCapacity
        objectWillChange.send()
    }
}
