import Foundation

/// External preference facade. Domain stores are typed views over the same
/// `AppSettings` authority; they never cache or persist a second copy.
final class AppPreferences {
    static let shared = AppPreferences(root: .shared)

    let root: AppSettings
    let general: GeneralPreferenceStore
    let monitoring: MonitoringPreferenceStore
    let menuBar: MenuBarPreferenceStore
    let quickPanel: QuickPanelPreferenceStore
    let safety: SafetyPreferenceStore
    let agent: AgentPreferenceStore

    init(root: AppSettings) {
        self.root = root
        general = GeneralPreferenceStore(root: root)
        monitoring = MonitoringPreferenceStore(root: root)
        menuBar = MenuBarPreferenceStore(root: root)
        quickPanel = QuickPanelPreferenceStore(root: root)
        safety = SafetyPreferenceStore(root: root)
        agent = AgentPreferenceStore(root: root)
    }
}

class PreferenceDomainStore {
    fileprivate unowned let root: AppSettings
    fileprivate init(root: AppSettings) { self.root = root }
    var rootIdentity: ObjectIdentifier { ObjectIdentifier(root) }
}

final class GeneralPreferenceStore: PreferenceDomainStore {
    var language: String {
        get { root.language }
        set { root.language = newValue }
    }
    var appearance: String {
        get { root.appTheme }
        set { root.appTheme = newValue }
    }
    var accentHex: UInt32 {
        get { root.accentHex }
        set { root.accentHex = newValue }
    }
}

final class MonitoringPreferenceStore: PreferenceDomainStore {
    var refreshInterval: Double {
        get { root.refreshInterval }
        set { root.refreshInterval = newValue }
    }
    var useFahrenheit: Bool {
        get { root.useFahrenheit }
        set { root.useFahrenheit = newValue }
    }
    var sensorsDetailed: Bool {
        get { root.sensorsDetailed }
        set { root.sensorsDetailed = newValue }
    }
}

final class MenuBarPreferenceStore: PreferenceDomainStore {
    var layout: String {
        get { root.menuBarLayout }
        set { root.menuBarLayout = newValue }
    }
    var metricOrder: [String] {
        get { root.menuBarOrder }
        set { root.menuBarOrder = newValue }
    }
}

final class QuickPanelPreferenceStore: PreferenceDomainStore {
    var moduleOrder: [String] {
        get { root.moduleOrder }
        set { root.moduleOrder = newValue }
    }
    func isVisible(_ module: Module) -> Bool { root.isVisible(module) }
}

final class SafetyPreferenceStore: PreferenceDomainStore {
    var alertsEnabled: Bool {
        get { root.alertsEnabled }
        set { root.alertsEnabled = newValue }
    }
    var fanCurveEnabled: Bool {
        get { root.fanCurveEnabled }
        set { root.fanCurveEnabled = newValue }
    }
}

final class AgentPreferenceStore: PreferenceDomainStore {
    var behaviorEnabled: Bool {
        get { root.agentBehaviorEnabled }
        set { root.agentBehaviorEnabled = newValue }
    }
    var presentationEnabled: Bool {
        get { root.agentPresentationEnabled }
        set { root.agentPresentationEnabled = newValue }
    }
    var fullscreenRevealEnabled: Bool {
        get { root.agentFullscreenRevealEnabled }
        set { root.agentFullscreenRevealEnabled = newValue }
    }
    var targetDisplayUUID: String {
        get { root.agentTargetDisplayUUID }
        set { root.agentTargetDisplayUUID = newValue }
    }
    var enabledProfileIDs: [String] {
        get { root.agentEnabledProfileIDs }
        set { root.agentEnabledProfileIDs = newValue }
    }
    var focusEnabled: Bool {
        get { root.agentFocusEnabled }
        set { root.agentFocusEnabled = newValue }
    }
    var tmuxEnabled: Bool {
        get { root.agentTMUXEnabled }
        set { root.agentTMUXEnabled = newValue }
    }
    var remoteSSHEnabled: Bool {
        get { root.agentRemoteSSHEnabled }
        set { root.agentRemoteSSHEnabled = newValue }
    }
    var symbolicCompanionEnabled: Bool {
        get { root.agentSymbolicCompanionEnabled }
        set { root.agentSymbolicCompanionEnabled = newValue }
    }
    var notificationMuteUntil: Date? {
        get { root.agentNotificationMuteUntil }
        set { root.agentNotificationMuteUntil = newValue }
    }
    var soundsEnabled: Bool {
        get { root.agentSoundsEnabled }
        set { root.agentSoundsEnabled = newValue }
    }
    var notificationAutoOpen: Bool {
        get { root.agentNotificationAutoOpen }
        set { root.agentNotificationAutoOpen = newValue }
    }
    var mascotAnimationsEnabled: Bool {
        get { root.agentMascotAnimationsEnabled }
        set { root.agentMascotAnimationsEnabled = newValue }
    }
    var showUsage: Bool {
        get { root.agentShowUsage }
        set { root.agentShowUsage = newValue }
    }
}
