import Combine
import Foundation

/// Stable settings destinations owned by the single AppKit settings window.
/// Agent Center and Integrations join this router in their dependency-ordered
/// work packages rather than creating another settings authority.
enum SettingsTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case menuBar = "Menu Bar"
    case popover = "Quick Panel"
    case sampling = "Monitoring"
    case sensors = "Sensors & Fans"
    case alerts = "Alerts"
    case agentCenter = "Agent Center"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .menuBar: return "menubar.rectangle"
        case .popover: return "rectangle.on.rectangle"
        case .sampling: return "waveform.path.ecg"
        case .sensors: return "thermometer.medium"
        case .alerts: return "bell.badge"
        case .agentCenter: return "terminal"
        case .advanced: return "slider.horizontal.3"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .overview: return .general
        case .menuBar, .popover: return .display
        case .sampling: return .monitoring
        case .sensors, .alerts: return .safety
        case .agentCenter: return .agent
        case .advanced: return .system
        }
    }

    static var grouped: [(group: SettingsGroup, tabs: [SettingsTab])] {
        SettingsGroup.allCases.compactMap { group in
            let tabs = allCases.filter { $0.group == group }
            return tabs.isEmpty ? nil : (group, tabs)
        }
    }
}

enum SettingsGroup: String, CaseIterable {
    case general
    case display
    case monitoring
    case safety
    case agent
    case system

    var title: String {
        switch self {
        case .general: return "General".loc
        case .display: return "Display".loc
        case .monitoring: return "Monitoring".loc
        case .safety: return "Safety".loc
        case .agent: return "Agent".loc
        case .system: return "Advanced".loc
        }
    }
}

enum SettingsControlID: String, CaseIterable {
    case overviewPreview
    case menuBarMetrics
    case menuBarAppearance
    case quickPanelLayout
    case quickPanelModules
    case refreshProfile
    case monitoringCost
    case temperatureDisplay
    case fanHelper
    case fanCurve
    case alertMaster
    case alertThresholds
    case agentBehavior
    case agentPresentation
    case agentIslandSettings
    case agentSounds
    case agentMascots
    case agentTargetDisplay
    case agentSessions
    case agentIntegrations
    case agentCapabilities
    case agentLegacyImport
    case language
    case appAppearance
    case accentColor
    case launchAtLogin
    case updates
    case diagnostics
}

struct SettingsSearchItem: Identifiable, Equatable {
    let control: SettingsControlID
    let title: String
    let detail: String
    let tab: SettingsTab
    let keywords: [String]

    var id: SettingsControlID { control }

    fileprivate var searchableText: String {
        ([title, title.loc, detail, detail.loc, tab.rawValue, tab.rawValue.loc] + keywords)
            .joined(separator: " ")
            .lowercased()
    }
}

enum SettingsSearchIndex {
    static let items: [SettingsSearchItem] = [
        .init(control: .overviewPreview, title: "Live Preview", detail: "Current status and display summary", tab: .overview, keywords: ["status", "summary"]),
        .init(control: .menuBarMetrics, title: "Menu bar metrics", detail: "CPU, GPU, memory, network, battery", tab: .menuBar, keywords: ["order", "width"]),
        .init(control: .menuBarAppearance, title: "Menu bar appearance", detail: "Layout, font, size, and color", tab: .menuBar, keywords: ["compact", "stacked", "minimal"]),
        .init(control: .quickPanelLayout, title: "Quick Panel layout", detail: "Health summary, module rows, and chart range", tab: .popover, keywords: ["popover", "details", "charts"]),
        .init(control: .quickPanelModules, title: "Quick Panel modules", detail: "Visible modules and ordering", tab: .popover, keywords: ["cpu", "gpu", "disk", "battery", "sensors"]),
        .init(control: .refreshProfile, title: "Refresh interval", detail: "Quiet, low impact, balanced, or real time", tab: .sampling, keywords: ["sampling", "cadence", "performance"]),
        .init(control: .monitoringCost, title: "Monitoring cost", detail: "Background and visible acquisition cadence", tab: .sampling, keywords: ["process", "history", "network"]),
        .init(control: .temperatureDisplay, title: "Temperature display", detail: "Fahrenheit and detailed sensors", tab: .sensors, keywords: ["celsius", "smc"]),
        .init(control: .fanHelper, title: "Fan control helper", detail: "Install, status, and automatic reset", tab: .sensors, keywords: ["authorization", "rpm", "manual"]),
        .init(control: .fanCurve, title: "Automatic fan curve", detail: "Temperature targets and fan speed", tab: .sensors, keywords: ["thermal", "rpm"]),
        .init(control: .alertMaster, title: "Enable alerts", detail: "Notification permission and monitoring", tab: .alerts, keywords: ["notification"]),
        .init(control: .alertThresholds, title: "Alert thresholds", detail: "CPU, memory, temperature, disk, and battery", tab: .alerts, keywords: ["warning", "limit"]),
        .init(control: .agentBehavior, title: "Agent behavior", detail: "Coding-agent session awareness", tab: .agentCenter, keywords: ["coding", "sessions", "core"]),
        .init(control: .agentPresentation, title: "Agent Island presentation", detail: "Desktop Island and fullscreen reveal", tab: .agentCenter, keywords: ["top edge", "fullscreen", "motion"]),
        .init(control: .agentIslandSettings, title: "Island behavior and display", detail: "Auto-hide, surface mode, width, usage, and panel sizing", tab: .agentCenter, keywords: ["notch", "floating pet", "compact", "font", "height"]),
        .init(control: .agentSounds, title: "Agent sounds and theme packs", detail: "System, 8-bit, and OpenPeon / CESP event sounds", tab: .agentCenter, keywords: ["sound", "audio", "openpeon", "cesp", "pack"]),
        .init(control: .agentMascots, title: "Provider mascots", detail: "Per-client mascot mapping and status preview", tab: .agentCenter, keywords: ["pet", "mascot", "client", "preview"]),
        .init(control: .agentTargetDisplay, title: "Agent target display", detail: "Automatic or selected screen", tab: .agentCenter, keywords: ["monitor", "screen", "notch"]),
        .init(control: .agentSessions, title: "Agent sessions", detail: "Current sessions and token usage", tab: .agentCenter, keywords: ["claude", "codex", "usage"]),
        .init(control: .agentIntegrations, title: "Provider integrations", detail: "Managed hooks and runtime clients", tab: .agentCenter, keywords: ["gemini", "qwen", "kimi", "qoder", "codebuddy", "cursor", "copilot"]),
        .init(control: .agentCapabilities, title: "Agent capabilities", detail: "Focus, tmux, remote SSH, and symbolic companion", tab: .agentCenter, keywords: ["terminal", "ide", "remote", "permission"]),
        .init(control: .agentLegacyImport, title: "Legacy Agent import", detail: "Optional compatible settings, associations, and usage", tab: .agentCenter, keywords: ["migration", "backup", "rollback"]),
        .init(control: .language, title: "Language", detail: "System, English, Simplified Chinese, Traditional Chinese", tab: .advanced, keywords: ["localization", "中文"]),
        .init(control: .appAppearance, title: "Appearance", detail: "System, light, or dark", tab: .advanced, keywords: ["theme"]),
        .init(control: .accentColor, title: "Accent color", detail: "Selection and primary action color", tab: .advanced, keywords: ["tint"]),
        .init(control: .launchAtLogin, title: "Launch at login", detail: "Start N1KO-STATE automatically", tab: .advanced, keywords: ["startup"]),
        .init(control: .updates, title: "Check for updates", detail: "Application maintenance", tab: .advanced, keywords: ["version"]),
        .init(control: .diagnostics, title: "Diagnostics", detail: "Logs and diagnostic export", tab: .advanced, keywords: ["support", "report"])
    ]

    static func search(_ query: String) -> [SettingsSearchItem] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return [] }
        return items.filter { item in terms.allSatisfy(item.searchableText.contains) }
    }
}

/// One router instance is shared by every settings entry point. It persists
/// only navigation state; preference values remain owned by `AppSettings`.
final class SettingsNavigationModel: ObservableObject {
    static let lastDestinationKey = "settings.lastDestination"

    @Published var selectedTab: SettingsTab {
        didSet { defaults.set(selectedTab.rawValue, forKey: Self.lastDestinationKey) }
    }
    @Published var pendingControlID: SettingsControlID?

    private let defaults: UserDefaults

    init(selectedTab: SettingsTab? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let selectedTab {
            self.selectedTab = selectedTab
        } else if let raw = defaults.string(forKey: Self.lastDestinationKey),
                  let restored = SettingsTab(rawValue: raw) {
            self.selectedTab = restored
        } else {
            self.selectedTab = .overview
        }
        defaults.set(self.selectedTab.rawValue, forKey: Self.lastDestinationKey)
    }

    func navigate(to item: SettingsSearchItem) {
        selectedTab = item.tab
        pendingControlID = item.control
    }
}
