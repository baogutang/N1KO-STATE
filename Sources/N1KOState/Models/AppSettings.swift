import SwiftUI
import Combine

/// User preferences, persisted to `UserDefaults`. A single shared instance is
/// observed across the popover, menu bar and settings window.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: General
    @Published var refreshInterval: Double { didSet { d.set(refreshInterval, forKey: K.refresh) } }
    @Published var accentHex: UInt32 {
        didSet {
            d.set(Int(accentHex), forKey: K.accent)
            Theme.accent = Color(hex: accentHex)
        }
    }
    @Published var useFahrenheit: Bool { didSet { d.set(useFahrenheit, forKey: K.fahrenheit) } }
    /// Show every individual sensor instead of the grouped buckets.
    @Published var sensorsDetailed: Bool { didSet { d.set(sensorsDetailed, forKey: K.sDetail) } }
    /// "system" / "en" / "zh-Hans" / "zh-Hant". Applied to the localization
    /// bundle immediately so the UI switches language live.
    @Published var language: String {
        didSet {
            d.set(language, forKey: K.lang)
            LocalizationManager.shared.apply(language)
        }
    }

    // MARK: Module cards (popover)
    @Published var showCPU: Bool { didSet { d.set(showCPU, forKey: K.cCPU) } }
    @Published var showGPU: Bool { didSet { d.set(showGPU, forKey: K.cGPU) } }
    @Published var showMemory: Bool { didSet { d.set(showMemory, forKey: K.cMem) } }
    @Published var showDisk: Bool { didSet { d.set(showDisk, forKey: K.cDisk) } }
    @Published var showNetwork: Bool { didSet { d.set(showNetwork, forKey: K.cNet) } }
    @Published var showSensors: Bool { didSet { d.set(showSensors, forKey: K.cSens) } }
    @Published var showBattery: Bool { didSet { d.set(showBattery, forKey: K.cBat) } }

    /// Persisted display order of the popover cards (module raw values).
    @Published var moduleOrder: [String] { didSet { d.set(moduleOrder, forKey: K.cOrder) } }

    /// Modules in the user's order, reconciled with the canonical set so newly
    /// added modules appear (appended) and removed ones are dropped.
    var orderedModules: [Module] {
        var seen = Set<String>()
        var result: [Module] = []
        for raw in moduleOrder {
            if let m = Module(rawValue: raw), !seen.contains(raw) { result.append(m); seen.insert(raw) }
        }
        for m in Module.allCases where !seen.contains(m.rawValue) { result.append(m) }
        return result
    }

    func isVisible(_ m: Module) -> Bool {
        switch m {
        case .cpu: return showCPU
        case .gpu: return showGPU
        case .memory: return showMemory
        case .battery: return showBattery
        case .disk: return showDisk
        case .network: return showNetwork
        case .sensors: return showSensors
        }
    }

    // MARK: Menu-bar items
    @Published var menuCPU: Bool { didSet { d.set(menuCPU, forKey: K.mCPU) } }
    @Published var menuGPU: Bool { didSet { d.set(menuGPU, forKey: K.mGPU) } }
    @Published var menuMemory: Bool { didSet { d.set(menuMemory, forKey: K.mMem) } }
    @Published var menuNetwork: Bool { didSet { d.set(menuNetwork, forKey: K.mNet) } }
    @Published var menuBattery: Bool { didSet { d.set(menuBattery, forKey: K.mBat) } }
    /// Compact menu-bar widget: drop the chip backgrounds and tighten spacing so
    /// the metrics read as one aggregated readout instead of separate chips.
    @Published var menuCompact: Bool { didSet { d.set(menuCompact, forKey: K.mCompact) } }
    /// Display order of menu-bar metrics (raw values of `MenuBarMetric`).
    @Published var menuBarOrder: [String] { didSet { d.set(menuBarOrder, forKey: K.mOrder) } }

    var orderedMenuBarMetrics: [MenuBarMetric] {
        var seen = Set<String>()
        var result: [MenuBarMetric] = []
        for raw in menuBarOrder {
            if let m = MenuBarMetric(rawValue: raw), !seen.contains(raw) { result.append(m); seen.insert(raw) }
        }
        for m in MenuBarMetric.allCases where !seen.contains(m.rawValue) { result.append(m) }
        return result
    }

    // MARK: Popover style
    /// "cards" (scrollable card list) or "gauges" (iStat-style ring gauge grid).
    @Published var popoverStyle: String { didSet { d.set(popoverStyle, forKey: K.popStyle) } }
    /// Chart time window for CPU / memory / network cards: "1m" / "10m" / "1h" / "24h".
    @Published var chartTimeRange: String { didSet { d.set(chartTimeRange, forKey: K.chartRange) } }

    // MARK: Fan curve
    @Published var fanCurveEnabled: Bool {
        didSet {
            d.set(fanCurveEnabled, forKey: K.fanCurveOn)
            // Only tear down fan state if the curve was actually driving it —
            // a user's manual configuration must survive toggling this switch.
            if !fanCurveEnabled, FanCurveController.shared?.mode == .curve {
                FanCurveController.shared?.resetAllFans()
            }
        }
    }
    @Published var fanCurve: [FanCurvePoint] {
        didSet {
            if let data = try? JSONEncoder().encode(fanCurve) {
                d.set(data, forKey: K.fanCurve)
            }
        }
    }

    // MARK: Appearance
    /// "system" / "light" / "dark". Applied immediately to all windows.
    @Published var appTheme: String {
        didSet {
            d.set(appTheme, forKey: K.appTheme)
            Theme.applyAppearance(appTheme)
        }
    }

    // MARK: Alerts (threshold notifications)
    @Published var alertsEnabled: Bool { didSet { d.set(alertsEnabled, forKey: K.aOn) } }
    @Published var cpuAlert: Bool { didSet { d.set(cpuAlert, forKey: K.aCPU) } }
    @Published var cpuThreshold: Double { didSet { d.set(cpuThreshold, forKey: K.aCPUv) } }
    @Published var memAlert: Bool { didSet { d.set(memAlert, forKey: K.aMem) } }
    @Published var memThreshold: Double { didSet { d.set(memThreshold, forKey: K.aMemv) } }
    @Published var tempAlert: Bool { didSet { d.set(tempAlert, forKey: K.aTemp) } }
    @Published var tempThreshold: Double { didSet { d.set(tempThreshold, forKey: K.aTempv) } }
    @Published var diskAlert: Bool { didSet { d.set(diskAlert, forKey: K.aDisk) } }
    /// Fire when *free* disk space falls below this fraction (e.g. 0.10 = 10%).
    @Published var diskFreeThreshold: Double { didSet { d.set(diskFreeThreshold, forKey: K.aDiskv) } }
    @Published var batteryAlert: Bool { didSet { d.set(batteryAlert, forKey: K.aBat) } }
    /// Fire when the charge level falls below this fraction while on battery.
    @Published var batteryThreshold: Double { didSet { d.set(batteryThreshold, forKey: K.aBatv) } }

    /// Curated accent palette (Linear / Apple-ish).
    static let accentPalette: [UInt32] = [
        0x5E5CE6, 0x0A84FF, 0x32D74B, 0xFF9F0A,
        0xFF453A, 0xFF6482, 0xBF5AF2, 0x64D2FF
    ]

    var accent: Color { Color(hex: accentHex) }

    private let d = UserDefaults.standard

    private init() {
        // Register defaults first so first-launch reads are sensible.
        d.register(defaults: [
            K.refresh: 1.0, K.accent: Int(0x5E5CE6), K.fahrenheit: false,
            K.sDetail: false, K.lang: LocalizationManager.system,
            K.cCPU: true, K.cGPU: true, K.cMem: true, K.cDisk: true, K.cNet: true, K.cSens: true,
            K.cBat: true,
            K.cOrder: Module.allCases.map { $0.rawValue },
            K.mCPU: true, K.mGPU: true, K.mMem: false, K.mNet: false,             K.mBat: false,
            K.mCompact: false,
            K.mOrder: MenuBarMetric.allCases.map(\.rawValue),
            K.popStyle: "cards",
            K.chartRange: "1m",
            K.fanCurveOn: false,
            K.appTheme: "system",
            K.aOn: false,
            K.aCPU: true, K.aCPUv: 0.90,
            K.aMem: true, K.aMemv: 0.90,
            K.aTemp: true, K.aTempv: 90.0,
            K.aDisk: true, K.aDiskv: 0.10,
            K.aBat: true, K.aBatv: 0.10
        ])
        refreshInterval = d.double(forKey: K.refresh)
        accentHex = UInt32(d.integer(forKey: K.accent))
        useFahrenheit = d.bool(forKey: K.fahrenheit)
        sensorsDetailed = d.bool(forKey: K.sDetail)
        language = d.string(forKey: K.lang) ?? LocalizationManager.system
        showCPU = d.bool(forKey: K.cCPU)
        showGPU = d.bool(forKey: K.cGPU)
        showMemory = d.bool(forKey: K.cMem)
        showDisk = d.bool(forKey: K.cDisk)
        showNetwork = d.bool(forKey: K.cNet)
        showSensors = d.bool(forKey: K.cSens)
        showBattery = d.bool(forKey: K.cBat)
        moduleOrder = (d.array(forKey: K.cOrder) as? [String]) ?? Module.allCases.map { $0.rawValue }
        menuCPU = d.bool(forKey: K.mCPU)
        menuGPU = d.bool(forKey: K.mGPU)
        menuMemory = d.bool(forKey: K.mMem)
        menuNetwork = d.bool(forKey: K.mNet)
        menuBattery = d.bool(forKey: K.mBat)
        menuCompact = d.bool(forKey: K.mCompact)
        menuBarOrder = (d.array(forKey: K.mOrder) as? [String]) ?? MenuBarMetric.allCases.map(\.rawValue)
        popoverStyle = d.string(forKey: K.popStyle) ?? "cards"
        chartTimeRange = d.string(forKey: K.chartRange) ?? "1m"
        fanCurveEnabled = d.bool(forKey: K.fanCurveOn)
        if let data = d.data(forKey: K.fanCurve),
           let curve = try? JSONDecoder().decode([FanCurvePoint].self, from: data) {
            fanCurve = curve
        } else {
            fanCurve = FanCurveInterpolator.defaultCurve
        }
        appTheme = d.string(forKey: K.appTheme) ?? "system"
        alertsEnabled = d.bool(forKey: K.aOn)
        cpuAlert = d.bool(forKey: K.aCPU)
        cpuThreshold = d.double(forKey: K.aCPUv)
        memAlert = d.bool(forKey: K.aMem)
        memThreshold = d.double(forKey: K.aMemv)
        tempAlert = d.bool(forKey: K.aTemp)
        tempThreshold = d.double(forKey: K.aTempv)
        diskAlert = d.bool(forKey: K.aDisk)
        diskFreeThreshold = d.double(forKey: K.aDiskv)
        batteryAlert = d.bool(forKey: K.aBat)
        batteryThreshold = d.double(forKey: K.aBatv)

        Theme.accent = Color(hex: accentHex)
        Theme.applyAppearance(appTheme)
        LocalizationManager.shared.apply(language)
    }

    private enum K {
        static let refresh = "refreshInterval"
        static let accent = "accentHex"
        static let fahrenheit = "useFahrenheit"
        static let sDetail = "sensorsDetailed"
        static let lang = "language"
        static let cCPU = "showCPU", cGPU = "showGPU", cMem = "showMemory"
        static let cDisk = "showDisk", cNet = "showNetwork", cSens = "showSensors"
        static let cBat = "showBattery"
        static let cOrder = "moduleOrder"
        static let mCPU = "menuCPU", mGPU = "menuGPU", mMem = "menuMemory", mNet = "menuNetwork"
        static let mBat = "menuBattery", mCompact = "menuCompact", mOrder = "menuBarOrder"
        static let popStyle = "popoverStyle", chartRange = "chartTimeRange"
        static let fanCurveOn = "fanCurveEnabled", fanCurve = "fanCurveJSON"
        static let appTheme = "appTheme"
        static let aOn = "alertsEnabled"
        static let aCPU = "cpuAlert", aCPUv = "cpuThreshold"
        static let aMem = "memAlert", aMemv = "memThreshold"
        static let aTemp = "tempAlert", aTempv = "tempThreshold"
        static let aDisk = "diskAlert", aDiskv = "diskFreeThreshold"
        static let aBat = "batteryAlert", aBatv = "batteryThreshold"
    }
}
