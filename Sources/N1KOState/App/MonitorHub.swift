import Foundation
import Combine

/// Which consumers are actively viewing monitor data — drives sampling pruning.
struct MonitorVisibility: Equatable {
    var popoverOpen = false
    var settingsOpen = false
    var menuBarMetrics: Set<MenuBarMetric> = []
    var popoverModules: Set<Module> = []

    func popoverShows(_ module: Module) -> Bool {
        (popoverOpen || settingsOpen) && popoverModules.contains(module)
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

struct MonitorDisplaySnapshot: Equatable {
    var generationID: UInt64 = 0
    var sampledAtUptimeNanoseconds: UInt64 = 0
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
    private let planner = SamplingPlanner()
    private let lifecyclePolicy = MonitorLifecyclePolicy()
    private let acquisitionQueue = DispatchQueue(label: "com.n1ko-state.monitor-acquisition",
                                                 qos: .utility)
    private var acquisitionInFlight = false
    private var pendingFullRefresh = false
    private var fullRefreshCompletions: [(MonitorDisplaySnapshot) -> Void] = []
    private var generationID: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()
    private var lastCurveTemp: Double?
    private var lastCurveApply = Date.distantPast
    private let curveHysteresis = 3.0
    private let curveMinInterval: TimeInterval = 15

    private struct AcquisitionBatch {
        var cpu: CPUModuleSnapshot?
        var memory: MemoryModuleSnapshot?
        var network: NetworkModuleSnapshot?
        var gpu: GPUModuleSnapshot?
        var disk: DiskModuleSnapshot?
    }

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
        lifecyclePolicy.onChange = { [weak self] previous, current in
            guard let self else { return }
            let resumed = (!previous.presentationAllowed && current.presentationAllowed)
            if resumed {
                self.recoverAfterWake()
            }
        }
        lifecyclePolicy.start()
        syncVisibilityFromSettings()
        reconcileBatterySettings()
        tick(full: true)
        restart()
    }

    func setPopoverVisible(_ visible: Bool) {
        visibility.popoverOpen = visible
        syncVisibilityFromSettings()
        if visible {
            battery.refreshSmartBattery(force: true)
            processes.refresh(force: true)
            tick(full: true)
        }
    }

    func setSettingsVisible(_ visible: Bool) {
        visibility.settingsOpen = visible
        syncVisibilityFromSettings()
        if visible { tick(full: true) }
    }

    /// Resets rate baselines and requests a complete coherent generation. The
    /// acquisition queue ordering guarantees the reset happens before sampling.
    /// Repeated requests coalesce without dropping the full refresh.
    func recoverAfterWake(completion: ((MonitorDisplaySnapshot) -> Void)? = nil) {
        if let completion { fullRefreshCompletions.append(completion) }
        acquisitionQueue.async { [weak self] in
            self?.network.resetBaseline()
            self?.disk.resetBaseline()
        }
        planner.reset()
        tick(full: true)
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
        planner.reset()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick(full: false)
        }
        t.tolerance = min(interval * 0.2, 0.5)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick(full: Bool) {
        let planningInterval = PerformanceDiagnostics.begin(.schedulingPlan)
        let s = AppSettings.shared
        let alertMetrics = alerts.requiredMetrics
        let plan = planner.makePlan(input: SamplingPlanInput(
            fullRefresh: full,
            refreshInterval: interval,
            presentationAllowed: lifecyclePolicy.state.presentationAllowed,
            visibility: visibility,
            alertMetrics: alertMetrics,
            fanSafetyActive: fans.mode == .curve || fans.mode == .manual,
            fanCurveEnabled: s.fanCurveEnabled,
            batteryPresent: battery.isPresent
        ))
        PerformanceDiagnostics.end(planningInterval)

        // SMC/IOHID operations retain their dedicated serial queues and never
        // wait for the general acquisition batch.
        if plan.contains(.sensors) { sensors.refresh() }
        if plan.contains(.fans) {
            fans.refresh()
            applyFanCurveIfNeeded()
        }
        if full || plan.contains(.sensors) {
            fans.enforceThermalSafety(peakCelsius: sensors.peakCelsius)
        }

        let popoverNeedsBattery = visibility.popoverShows(.battery)
        if plan.contains(.battery),
           battery.shouldPollFromTick(popoverOpen: popoverNeedsBattery,
                                      menuBarShowsBattery: visibility.menuBarMetrics.contains(.battery),
                                      alertNeedsBattery: alertMetrics.contains(.battery)) {
            battery.refreshFromTick(popoverOpen: popoverNeedsBattery)
        }
        if plan.contains(.processes) { processes.refresh(force: full) }

        let hasAcquisition = plan.contains(.cpu) || plan.contains(.memory)
            || plan.contains(.network) || plan.contains(.gpu)
            || plan.contains(.diskIO) || plan.contains(.diskVolumes)
        guard hasAcquisition else {
            finish(plan: plan, batch: AcquisitionBatch())
            return
        }

        // Avoid piling work up when a slow IOKit read crosses a timer boundary.
        guard !acquisitionInFlight else {
            if full { pendingFullRefresh = true }
            return
        }
        acquisitionInFlight = true
        acquisitionQueue.async { [weak self] in
            guard let self else { return }
            var batch = AcquisitionBatch()
            if plan.contains(.cpu) { batch.cpu = self.cpu.sample() }
            if plan.contains(.memory) { batch.memory = self.memory.sample() }
            if plan.contains(.network) {
                batch.network = self.network.sample(
                    updateInterfaceInfo: plan.contains(.networkInterfaceInfo)
                )
            }
            if plan.contains(.gpu) { batch.gpu = self.gpu.sample() }
            if plan.contains(.diskIO) || plan.contains(.diskVolumes) {
                batch.disk = self.disk.sampleIO(includeVolumes: plan.contains(.diskVolumes))
            }
            DispatchQueue.main.async { [weak self] in
                self?.finish(plan: plan, batch: batch)
            }
        }
    }

    private func finish(plan: SamplingPlan, batch: AcquisitionBatch) {
        acquisitionInFlight = false
        if let value = batch.cpu { cpu.apply(value) }
        if let value = batch.memory { memory.apply(value) }
        if let value = batch.network { network.apply(value) }
        if let value = batch.gpu { gpu.apply(value) }
        if let value = batch.disk { disk.apply(value) }

        if plan.contains(.history) {
            let memFrac = memory.total > 0 ? memory.used / memory.total : 0
            HistoryStore.shared.record(cpu: cpu.totalUsage,
                                       memory: memFrac,
                                       netDown: network.downloadRate,
                                       netUp: network.uploadRate)
        }
        if plan.contains(.alerts), AppSettings.shared.alertsEnabled { evaluateAlerts() }
        if plan.contains(.snapshot) { publishSnapshot() }
        if plan.isFullRefresh, !pendingFullRefresh, !fullRefreshCompletions.isEmpty {
            let callbacks = fullRefreshCompletions
            fullRefreshCompletions.removeAll()
            callbacks.forEach { $0(snapshot) }
        }

        if pendingFullRefresh {
            pendingFullRefresh = false
            planner.reset()
            DispatchQueue.main.async { [weak self] in self?.tick(full: true) }
        }
    }

    private func publishSnapshot() {
        PerformanceDiagnostics.measure(.snapshotCommit) {
            generationID &+= 1
            let primaryVolume = disk.volumes.first { $0.id == "/" } ?? disk.volumes.first
            snapshot = MonitorDisplaySnapshot(
                generationID: generationID,
                sampledAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
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

    deinit {
        timer?.invalidate()
        lifecyclePolicy.stop()
    }
}
