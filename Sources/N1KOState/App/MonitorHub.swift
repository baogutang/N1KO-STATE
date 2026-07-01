import Foundation
import Combine

/// Which consumers are actively viewing monitor data — drives sampling pruning.
struct MonitorVisibility {
    var popoverOpen = false
    var menuBarMetrics: Set<MenuBarMetric> = []
    var popoverModules: Set<Module> = []

    func popoverShows(_ module: Module) -> Bool {
        popoverOpen && popoverModules.contains(module)
    }

    func needsNetworkRates(menuBarHasNet: Bool) -> Bool {
        popoverShows(.network) || menuBarHasNet
    }

    func needsNetworkInfo(menuBarHasNet: Bool) -> Bool {
        popoverShows(.network) || menuBarHasNet
    }

    func needsGPU(menuBarHasGPU: Bool) -> Bool {
        popoverShows(.gpu) || menuBarHasGPU
    }

    func needsBattery(menuBarHasBattery: Bool) -> Bool {
        popoverShows(.battery) || menuBarHasBattery
    }

}

struct MonitorDisplaySnapshot {
    var cpuUsage: Double = 0
    var cpuLoadAverageOne: Double = 0
    var cpuCoreCount: Int = 0
    var cpuUptime: TimeInterval = 0

    var gpuUtilization: Double = 0
    var gpuVRAMUsed: Double = 0
    var gpuVRAMTotal: Double = 0
    var gpuName: String = "GPU"
    var gpuIsAvailable = false

    var memoryUsed: Double = 0
    var memoryFree: Double = 0
    var memoryTotal: Double = 0
    var memoryPressureLevel: MemoryPressureLevel = .low
    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    var diskPrimaryFree: Double?
    var diskPrimaryFraction: Double?
    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0

    var networkDownloadRate: Double = 0
    var networkUploadRate: Double = 0
    var networkLocalIP: String?
    var networkIsConnected = false

    var batteryIsPresent = false
    var batteryPercentage: Double = 0
    var batteryIsCharging = false
    var batteryIsCharged = false
    var batteryOnACPower = false
    var batteryHealthFraction: Double?
    var batteryCycleCount: Int?

    var sensorPeakCelsius: Double?
    var sensorsIsAvailable = false
    var fansIsAvailable = false
    var fanCount = 0
    var firstFanRPM: Int?
}

/// Owns every monitor and drives them from a single timer so sampling stays
/// coordinated and the app's own overhead is minimal.
final class MonitorHub: ObservableObject {

    let cpu = CPUMonitor()
    let gpu = GPUMonitor()
    let memory = MemoryMonitor()
    let disk = DiskMonitor()
    let network = NetworkMonitor()
    let sensors = SensorMonitor()
    let fans = FanController()
    let processes = ProcessMonitor()
    let battery = BatteryMonitor()
    let alerts = AlertManager()

    @Published private(set) var snapshot = MonitorDisplaySnapshot()

    @Published var interval: TimeInterval = 1.0 {
        didSet { if timer != nil { restart() } }
    }

    private var visibility = MonitorVisibility()
    private var timer: Timer?
    private var tickCount = 0
    private var cancellables = Set<AnyCancellable>()
    private var lastCurveTemp: Double?
    private var lastCurveApply = Date.distantPast
    private let curveHysteresis = 3.0
    private let curveMinInterval: TimeInterval = 15
    private var lastHistorySample = Date.distantPast

    func start() {
        interval = AppSettings.shared.refreshInterval
        AppSettings.shared.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] in self?.interval = $0 }
            .store(in: &cancellables)
        syncVisibilityFromSettings()
        let appSettings = AppSettings.shared
        let settingsPub: [AnyPublisher<Void, Never>] = [
            appSettings.$menuCPU.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$menuGPU.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$menuMemory.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$menuNetwork.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$menuBattery.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$showCPU.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$showGPU.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$showMemory.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$showDisk.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$showNetwork.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$showSensors.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$showBattery.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$moduleOrder.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$popoverStyle.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$cpuAlert.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$memAlert.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$tempAlert.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$diskAlert.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$batteryAlert.map { _ in () }.eraseToAnyPublisher(),
            appSettings.$alertsEnabled.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(settingsPub)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncVisibilityFromSettings() }
            .store(in: &cancellables)
        alerts.onAuthorizationComplete = { [weak self] in self?.evaluateAlerts() }
        alerts.refreshAuthorizationStatus()
        FanCurveController.shared = fans
        disk.startVolumeWatching()
        battery.start()
        syncVisibilityFromSettings()
        reconcileBatterySettings()
        tick(full: true)
        restart()
    }

    func setPopoverVisible(_ visible: Bool) {
        visibility.popoverOpen = visible
        syncVisibilityFromSettings()
        if visible {
            disk.refreshVolumesNow()
            battery.refreshSmartBattery(force: true)
            processes.refresh(force: true)
            tick(full: true)
        }
    }

    func flushHistory() {
        HistoryStore.shared.flushSync(timeout: 0.5)
    }

    private func syncVisibilityFromSettings() {
        let s = AppSettings.shared
        var metrics = Set<MenuBarMetric>()
        if s.menuCPU { metrics.insert(.cpu) }
        if s.menuGPU { metrics.insert(.gpu) }
        if s.menuMemory { metrics.insert(.memory) }
        if s.menuBattery, battery.isPresent { metrics.insert(.battery) }
        if s.menuNetwork { metrics.insert(.network) }
        visibility.menuBarMetrics = metrics
        visibility.popoverModules = Set(s.orderedModules.filter { module in
            guard s.isVisible(module) else { return false }
            if module == .battery { return battery.isPresent }
            return true
        })
    }

    private func reconcileBatterySettings() {
        guard !battery.isPresent else { return }
        let s = AppSettings.shared
        if s.menuBattery { s.menuBattery = false }
        if s.showBattery { s.showBattery = false }
    }

    private func restart() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick(full: false)
        }
        t.tolerance = min(interval * 0.2, 0.5)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var menuBarSampleStride: Int {
        if interval < 0.75 { return 1 }
        return max(1, Int(ceil(2.0 / max(interval, 0.1))))
    }

    private func tick(full: Bool) {
        tickCount += 1
        let s = AppSettings.shared
        let vis = visibility
        let alertMetrics = alerts.requiredMetrics
        let menuBarTick = full || vis.popoverOpen || tickCount % menuBarSampleStride == 0
        let menuHasCPU = vis.menuBarMetrics.contains(.cpu)
        let menuHasMemory = vis.menuBarMetrics.contains(.memory)
        let menuHasNet = vis.menuBarMetrics.contains(.network)
        let menuHasGPU = vis.menuBarMetrics.contains(.gpu)
        let menuHasBattery = vis.menuBarMetrics.contains(.battery)
        let popoverNeedsCPU = vis.popoverShows(.cpu)
        let popoverNeedsGPU = vis.popoverShows(.gpu)
        let popoverNeedsMemory = vis.popoverShows(.memory)
        let popoverNeedsBattery = vis.popoverShows(.battery)
        let popoverNeedsDisk = vis.popoverShows(.disk)
        let popoverNeedsNetwork = vis.popoverShows(.network)
        let popoverNeedsSensors = vis.popoverShows(.sensors)
        let popoverNeedsProcesses = popoverNeedsCPU || popoverNeedsMemory
        let menuNeedsCPU = menuHasCPU && menuBarTick
        let menuNeedsMemory = menuHasMemory && menuBarTick
        let menuNeedsNet = menuHasNet && menuBarTick
        let menuNeedsGPU = menuHasGPU && menuBarTick
        let needsCPU = full || popoverNeedsCPU || menuNeedsCPU || alertMetrics.contains(.cpu)
        let needsMemory = full || popoverNeedsMemory || menuNeedsMemory || alertMetrics.contains(.memory)
        let now = Date()
        let historyTick = now.timeIntervalSince(lastHistorySample) >= 30
        if historyTick { lastHistorySample = now }
        var displayChanged = full || vis.popoverOpen || menuNeedsCPU || menuNeedsMemory || menuNeedsNet || menuNeedsGPU
        // SAFETY: thermal protection + fan curve depend on continuous sensor sampling.
        let needsSensors = full || popoverNeedsSensors
            || fans.mode == .curve || fans.mode == .manual
            || s.fanCurveEnabled
            || alertMetrics.contains(.temperature)
        let needsFans = needsSensors

        if needsCPU || historyTick {
            cpu.refresh(publish: needsCPU)
        }
        if needsMemory || historyTick {
            memory.refresh(publish: needsMemory)
        }

        if full || popoverNeedsNetwork || menuNeedsNet || historyTick {
            if full || popoverNeedsNetwork || menuNeedsNet {
                // Interface name/IP strings change rarely — rebuild them at most
                // every 10 ticks; rates stay per-tick fresh.
                network.refresh(includeInterfaceInfo: full || tickCount % 10 == 0)
            } else {
                network.refreshRatesOnly()
            }
        }

        if alertMetrics.contains(.disk), tickCount % 60 == 0 {
            disk.refreshVolumesNow()
        }

        if full || popoverNeedsGPU || menuNeedsGPU {
            gpu.refresh()
        }

        if battery.shouldPollFromTick(popoverOpen: popoverNeedsBattery,
                                      menuBarShowsBattery: menuHasBattery,
                                      alertNeedsBattery: alertMetrics.contains(.battery)) {
            let intervalTicks = popoverNeedsBattery ? 2 : 30
            if full || popoverNeedsBattery || tickCount % intervalTicks == 0 {
                battery.refreshFromTick(popoverOpen: popoverNeedsBattery)
                displayChanged = true
            }
        }

        if full || popoverNeedsSensors || needsSensors {
            if full || popoverNeedsSensors || (tickCount % 3 == 0) || needsSensors && tickCount % 30 == 0 {
                sensors.refresh()
            }
        }

        if full || needsFans {
            if full || popoverNeedsSensors || tickCount % 3 == 0 {
                fans.refresh()
                if needsFans { applyFanCurveIfNeeded() }
            }
        }

        if full || popoverNeedsDisk {
            if full || tickCount % 3 == 0 {
                disk.refreshIO()
                displayChanged = true
            }
        }

        if full || popoverNeedsProcesses {
            if full || tickCount % 5 == 0 {
                processes.refresh()
            }
        }

        if historyTick {
            let memFrac = memory.total > 0 ? memory.used / memory.total : 0
            HistoryStore.shared.record(cpu: cpu.totalUsage,
                                       memory: memFrac,
                                       netDown: network.downloadRate,
                                       netUp: network.uploadRate)
        }

        if full || alertMetrics.contains(.temperature) || needsSensors {
            fans.enforceThermalSafety(peakCelsius: sensors.peakCelsius)
        }
        if s.alertsEnabled {
            evaluateAlerts()
        }
        if displayChanged {
            publishSnapshot()
        }
    }

    private func publishSnapshot() {
        let primaryVolume = disk.volumes.first { $0.id == "/" } ?? disk.volumes.first
        snapshot = MonitorDisplaySnapshot(
            cpuUsage: cpu.totalUsage,
            cpuLoadAverageOne: cpu.loadAverage.one,
            cpuCoreCount: cpu.cores.count,
            cpuUptime: cpu.uptime,
            gpuUtilization: gpu.utilization,
            gpuVRAMUsed: gpu.vramUsed,
            gpuVRAMTotal: gpu.vramTotal,
            gpuName: gpu.name,
            gpuIsAvailable: gpu.isAvailable,
            memoryUsed: memory.used,
            memoryFree: memory.free,
            memoryTotal: memory.total,
            memoryPressureLevel: memory.pressureLevel,
            diskPrimaryFree: primaryVolume?.free,
            diskPrimaryFraction: primaryVolume?.fraction,
            diskReadRate: disk.readRate,
            diskWriteRate: disk.writeRate,
            networkDownloadRate: network.downloadRate,
            networkUploadRate: network.uploadRate,
            networkLocalIP: network.localIP,
            networkIsConnected: network.isConnected,
            batteryIsPresent: battery.isPresent,
            batteryPercentage: battery.percentage,
            batteryIsCharging: battery.isCharging,
            batteryIsCharged: battery.isCharged,
            batteryOnACPower: battery.onACPower,
            batteryHealthFraction: battery.healthFraction,
            batteryCycleCount: battery.cycleCount,
            sensorPeakCelsius: sensors.peakCelsius,
            sensorsIsAvailable: sensors.isAvailable,
            fansIsAvailable: fans.isAvailable,
            fanCount: fans.fans.count,
            firstFanRPM: fans.fans.first?.rpm
        )
    }

    private func evaluateAlerts() {
        let memFraction = memory.total > 0 ? memory.used / memory.total : 0
        let boot = disk.volumes.first { $0.id == "/" } ?? disk.volumes.max { $0.total < $1.total }
        let diskFree = boot.map { $0.total > 0 ? $0.free / $0.total : 1 }
        let batteryLevel = battery.isPresent ? battery.percentage : nil
        alerts.evaluate(cpu: cpu.totalUsage,
                        mem: memFraction,
                        tempC: sensors.peakCelsius,
                        diskFree: diskFree,
                        battery: batteryLevel,
                        batteryCharging: battery.isCharging || battery.onACPower)
    }

    private func applyFanCurveIfNeeded() {
        let s = AppSettings.shared
        guard s.fanCurveEnabled, fans.supportsControl else {
            if fans.mode == .curve { fans.resetAllFans() }
            return
        }
        guard fans.mode != .manual else { return }
        guard let peak = sensors.peakCelsius else { return }

        if fans.mode != .curve { fans.enableCurveMode() }

        if let last = lastCurveTemp, abs(peak - last) < curveHysteresis { return }
        if Date().timeIntervalSince(lastCurveApply) < curveMinInterval { return }

        let pct = FanCurveInterpolator.rpmPercent(for: peak, curve: s.fanCurve)
        fans.applyCurve(percent: pct)
        lastCurveTemp = peak
        lastCurveApply = Date()
    }

    deinit { timer?.invalidate() }
}
