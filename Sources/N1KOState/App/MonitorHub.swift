import Foundation
import Combine

/// Which consumers are actively viewing monitor data — drives sampling pruning.
struct MonitorVisibility {
    var popoverOpen = false
    var menuBarMetrics: Set<MenuBarMetric> = []

    func needsNetworkRates(menuBarHasNet: Bool) -> Bool {
        popoverOpen || menuBarHasNet
    }

    func needsNetworkInfo(menuBarHasNet: Bool) -> Bool {
        popoverOpen || menuBarHasNet
    }

    func needsGPU(menuBarHasGPU: Bool) -> Bool {
        popoverOpen || menuBarHasGPU
    }

    func needsBattery(menuBarHasBattery: Bool) -> Bool {
        popoverOpen || menuBarHasBattery
    }

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

    func start() {
        interval = AppSettings.shared.refreshInterval
        AppSettings.shared.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] in self?.interval = $0 }
            .store(in: &cancellables)
        syncVisibilityFromSettings()
        let settingsPub = [
            AppSettings.shared.$menuCPU.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$menuGPU.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$menuMemory.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$menuNetwork.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$menuBattery.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$cpuAlert.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$memAlert.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$tempAlert.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$diskAlert.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$batteryAlert.map { _ in () }.eraseToAnyPublisher(),
            AppSettings.shared.$alertsEnabled.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(settingsPub)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncVisibilityFromSettings() }
            .store(in: &cancellables)
        alerts.onAuthorizationComplete = { [weak self] in self?.evaluateAlerts() }
        alerts.requestAuthorization()
        fans.startReconcileLoop()
        FanCurveController.shared = fans
        disk.startVolumeWatching()
        battery.start()
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
        if s.menuBattery { metrics.insert(.battery) }
        if s.menuNetwork { metrics.insert(.network) }
        visibility.menuBarMetrics = metrics
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

    private func tick(full: Bool) {
        tickCount += 1
        let s = AppSettings.shared
        let vis = visibility
        let alertMetrics = alerts.requiredMetrics
        let menuHasCPU = vis.menuBarMetrics.contains(.cpu)
        let menuHasMemory = vis.menuBarMetrics.contains(.memory)
        let menuHasNet = vis.menuBarMetrics.contains(.network)
        let menuHasGPU = vis.menuBarMetrics.contains(.gpu)
        let menuHasBattery = vis.menuBarMetrics.contains(.battery)
        let needsCPU = full || vis.popoverOpen || menuHasCPU || alertMetrics.contains(.cpu)
        let needsMemory = full || vis.popoverOpen || menuHasMemory || alertMetrics.contains(.memory)
        let historyTick = tickCount % 30 == 0
        // SAFETY: thermal protection + fan curve depend on continuous sensor sampling.
        let needsSensors = full || vis.popoverOpen
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

        if full || vis.popoverOpen || menuHasNet || historyTick {
            if full || vis.popoverOpen || menuHasNet {
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

        if full || vis.popoverOpen || menuHasGPU {
            if full || vis.popoverOpen || (tickCount % 2 == 0) {
                gpu.refresh()
            }
        }

        if battery.shouldPollFromTick(popoverOpen: vis.popoverOpen,
                                      menuBarShowsBattery: menuHasBattery,
                                      alertNeedsBattery: alertMetrics.contains(.battery)) {
            let intervalTicks = vis.popoverOpen ? 2 : 30
            if full || vis.popoverOpen || tickCount % intervalTicks == 0 {
                battery.refreshFromTick(popoverOpen: vis.popoverOpen)
            }
        }

        if full || vis.popoverOpen || needsSensors {
            if full || vis.popoverOpen || (tickCount % 3 == 0) || needsSensors && tickCount % 30 == 0 {
                sensors.refresh()
            }
        }

        if full || needsFans {
            if full || vis.popoverOpen || tickCount % 3 == 0 {
                fans.refresh()
                if needsFans { applyFanCurveIfNeeded() }
            }
        }

        if full || vis.popoverOpen {
            if full || tickCount % 3 == 0 {
                disk.refreshIO()
            }
        }

        if full || vis.popoverOpen {
            if full || tickCount % 5 == 0, s.showCPU || s.showMemory {
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
