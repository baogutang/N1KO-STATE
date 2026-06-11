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

    private var desktopConfirmed = false
    private var notificationInstalled = false
    private var lastSmartBatteryRead = Date.distantPast
    private let smartBatteryInterval: TimeInterval = 300

    /// Health is considered degraded below this fraction (matches Apple's
    /// "Service Recommended" guidance around 80%).
    var conditionOK: Bool? {
        guard let h = healthFraction else { return nil }
        return h >= 0.80
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
        readPowerSources()
        if isPresent {
            history.append(percentage)
            if history.count > historyCapacity { history.removeFirst(history.count - historyCapacity) }
            refreshSmartBattery(force: popoverOpen)
            objectWillChange.send()
        }
    }

    func refreshSmartBattery(force: Bool = false) {
        guard !desktopConfirmed, isPresent else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSmartBatteryRead) >= smartBatteryInterval else { return }
        lastSmartBatteryRead = now
        monitorWorkQueue.async { [weak self] in
            self?.readSmartBattery()
            DispatchQueue.main.async { self?.objectWillChange.send() }
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
            monitor.readPowerSources()
            DispatchQueue.main.async { monitor.objectWillChange.send() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    // MARK: - IOPowerSources (charge %, charging, source, time remaining)

    private func readPowerSources() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else {
            isPresent = false
            desktopConfirmed = true
            return
        }

        let present = (desc[kIOPSIsPresentKey] as? Bool) ?? false
        guard present else {
            isPresent = false
            desktopConfirmed = true
            return
        }
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

    private func readSmartBattery() {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            cycleCount = nil; healthFraction = nil; temperatureC = nil; watts = nil
            designCapacity = nil; maxCapacity = nil
            return
        }
        // IOServiceGetMatchingService consumes the matching dictionary reference.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            cycleCount = nil; healthFraction = nil; temperatureC = nil; watts = nil
            designCapacity = nil; maxCapacity = nil
            return
        }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return }

        cycleCount = props["CycleCount"] as? Int

        let design = props["DesignCapacity"] as? Int
        let rawMax = (props["AppleRawMaxCapacity"] as? Int)
            ?? (props["NominalChargeCapacity"] as? Int)
            ?? (props["MaxCapacity"] as? Int)
        designCapacity = design
        maxCapacity = rawMax
        if let d = design, d > 0, let m = rawMax, m > 0 {
            healthFraction = min(Double(m) / Double(d), 1.0)
        }

        if let temp = props["Temperature"] as? Int {
            temperatureC = Double(temp) / 100.0
        }

        if let mV = props["Voltage"] as? Int {
            let mA = (props["Amperage"] as? Int) ?? 0
            watts = (Double(mV) / 1000.0) * (Double(mA) / 1000.0)
        }
    }
}
