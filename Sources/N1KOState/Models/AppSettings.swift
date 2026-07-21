import SwiftUI
import Combine

/// User preferences, persisted to `UserDefaults`. A single shared instance is
/// observed across the popover, menu bar and settings window.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    static let notchModuleWidthRange =
        AppSettingsStore.minimumNotchModuleWidth...AppSettingsStore.maximumNotchModuleWidth
    private static var bundledSoundCache: [String: NSSound] = [:]

    static var soundEnabled: Bool {
        get { shared.soundEnabled }
        set { shared.soundEnabled = newValue }
    }

    static var soundVolume: Double {
        get { shared.soundVolume }
        set { shared.soundVolume = newValue }
    }

    static var soundThemeMode: SoundThemeMode {
        get { shared.soundThemeMode }
        set { shared.soundThemeMode = newValue }
    }

    static var selectedSoundPackPath: String {
        get { shared.selectedSoundPackPath }
        set { shared.selectedSoundPackPath = newValue }
    }

    static func isNotificationMuteActive(until date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return date > now
    }

    static func muteReminderNotifications(for duration: TimeInterval, now: Date = Date()) {
        shared.agentNotificationMuteUntil = now.addingTimeInterval(duration)
    }

    static func clearReminderNotificationMute() {
        shared.agentNotificationMuteUntil = nil
    }

    static func playDetachedCapsuleSound() {
        guard soundEnabled else { return }
        if !playBundledSound(named: Island8BitSound.bubblePop.rawValue) {
            playSound(named: NotificationSound.pop.soundName)
        }
    }

    @MainActor
    static func playSound(for event: NotificationEvent) {
        guard soundEnabled, isSoundEnabled(for: event) else { return }
        guard !shared.agentNotificationsTemporarilyMuted else { return }

        switch soundThemeMode {
        case .builtIn:
            playSound(named: sound(for: event).soundName)
        case .island8Bit:
            if !playBundledSound(named: bundledSound(for: event).rawValue) {
                playSound(named: sound(for: event).soundName)
            }
        case .soundPack:
            if SoundPackCatalog.shared.play(
                event: event,
                packPath: selectedSoundPackPath,
                volume: Float(soundVolume)
            ) {
                return
            }
            playSound(named: sound(for: event).soundName)
        }
    }

    static func isSoundEnabled(for event: NotificationEvent) -> Bool {
        switch event {
        case .processingStarted: return shared.processingStartSoundEnabled
        case .attentionRequired: return shared.attentionRequiredSoundEnabled
        case .taskCompleted: return shared.taskCompletedSoundEnabled
        case .taskError: return shared.taskErrorSoundEnabled
        case .resourceLimit: return shared.resourceLimitSoundEnabled
        }
    }

    static func setSoundEnabled(_ enabled: Bool, for event: NotificationEvent) {
        switch event {
        case .processingStarted: shared.processingStartSoundEnabled = enabled
        case .attentionRequired: shared.attentionRequiredSoundEnabled = enabled
        case .taskCompleted: shared.taskCompletedSoundEnabled = enabled
        case .taskError: shared.taskErrorSoundEnabled = enabled
        case .resourceLimit: shared.resourceLimitSoundEnabled = enabled
        }
    }

    static func sound(for event: NotificationEvent) -> NotificationSound {
        switch event {
        case .processingStarted: return shared.processingStartSound
        case .attentionRequired: return shared.attentionRequiredSound
        case .taskCompleted: return shared.taskCompletedSound
        case .taskError: return shared.taskErrorSound
        case .resourceLimit: return shared.resourceLimitSound
        }
    }

    static func setSound(_ sound: NotificationSound, for event: NotificationEvent) {
        switch event {
        case .processingStarted: shared.processingStartSound = sound
        case .attentionRequired: shared.attentionRequiredSound = sound
        case .taskCompleted: shared.taskCompletedSound = sound
        case .taskError: shared.taskErrorSound = sound
        case .resourceLimit: shared.resourceLimitSound = sound
        }
    }

    static func bundledSound(for event: NotificationEvent) -> Island8BitSound {
        switch event {
        case .processingStarted: return shared.island8BitProcessingStartSound
        case .attentionRequired: return shared.island8BitAttentionRequiredSound
        case .taskCompleted: return shared.island8BitTaskCompletedSound
        case .taskError: return shared.island8BitTaskErrorSound
        case .resourceLimit: return shared.island8BitResourceLimitSound
        }
    }

    static func setBundledSound(_ sound: Island8BitSound, for event: NotificationEvent) {
        switch event {
        case .processingStarted: shared.island8BitProcessingStartSound = sound
        case .attentionRequired: shared.island8BitAttentionRequiredSound = sound
        case .taskCompleted: shared.island8BitTaskCompletedSound = sound
        case .taskError: shared.island8BitTaskErrorSound = sound
        case .resourceLimit: shared.island8BitResourceLimitSound = sound
        }
    }

    static func playNotificationSound(_ sound: NotificationSound? = nil) {
        playSound(named: (sound ?? shared.taskCompletedSound).soundName)
    }

    static func playClientStartupSound() {
        guard soundEnabled else { return }
        if !playBundledSound(named: Island8BitSound.powerUp.rawValue) {
            playSound(named: NotificationSound.pop.soundName)
        }
    }

    static var bundledAudioAvailable: Bool {
        bundledSoundURL(named: Island8BitSound.powerUp.rawValue) != nil
    }

    private static func playSound(named soundName: String?) {
        guard soundEnabled, let soundName,
              let sound = NSSound(named: NSSound.Name(soundName)) else { return }
        AppSoundPlayback.shared.play(sound, volume: Float(soundVolume))
    }

    @discardableResult
    private static func playBundledSound(named resourceName: String) -> Bool {
        guard let sound = bundledSoundCache[resourceName] ?? loadBundledSound(named: resourceName) else {
            return false
        }
        bundledSoundCache[resourceName] = sound
        return AppSoundPlayback.shared.play(sound, volume: Float(soundVolume))
    }

    private static func loadBundledSound(named resourceName: String) -> NSSound? {
        guard let url = bundledSoundURL(named: resourceName) else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }

    private static func bundledSoundURL(named resourceName: String) -> URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "wav")
    }

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

    /// Compatibility projection used by the selectively migrated Island UI.
    /// N1KO remains the only language/settings authority.
    var locale: Locale {
        switch language {
        case "en": return Locale(identifier: "en")
        case "zh-Hans": return Locale(identifier: "zh-Hans")
        case "zh-Hant": return Locale(identifier: "zh-Hant")
        default: return Locale.current
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
    @Published var menuCompact: Bool {
        didSet {
            d.set(menuCompact, forKey: K.mCompact)
            if menuCompact, menuBarLayout == MenuBarLayout.standard.rawValue {
                menuBarLayout = MenuBarLayout.compact.rawValue
            } else if !menuCompact, menuBarLayout == MenuBarLayout.compact.rawValue {
                menuBarLayout = MenuBarLayout.standard.rawValue
            }
        }
    }
    /// Menu-bar rendering mode. Keeps the legacy `menuCompact` key in sync so
    /// older installs and downgraded builds retain a sensible appearance.
    @Published var menuBarLayout: String {
        didSet {
            let layout = MenuBarLayout.normalized(menuBarLayout, legacyCompact: menuCompact)
            if layout.rawValue != menuBarLayout {
                menuBarLayout = layout.rawValue
                return
            }
            d.set(menuBarLayout, forKey: K.mLayout)
            let compact = layout == .compact
            if menuCompact != compact { menuCompact = compact }
        }
    }
    /// Display order of menu-bar metrics (raw values of `MenuBarMetric`).
    @Published var menuBarOrder: [String] { didSet { d.set(menuBarOrder, forKey: K.mOrder) } }
    @Published var menuBarFontStyle: String {
        didSet {
            let normalized = MenuBarFontStyle.normalized(menuBarFontStyle).rawValue
            if normalized != menuBarFontStyle {
                menuBarFontStyle = normalized
                return
            }
            d.set(menuBarFontStyle, forKey: K.mFontStyle)
        }
    }
    @Published var menuBarColorMode: String {
        didSet {
            let normalized = MenuBarColorMode.normalized(menuBarColorMode).rawValue
            if normalized != menuBarColorMode {
                menuBarColorMode = normalized
                return
            }
            d.set(menuBarColorMode, forKey: K.mColorMode)
        }
    }
    @Published var menuBarFontSize: Double {
        didSet {
            let clamped = Self.clampMenuBarFontSize(menuBarFontSize)
            if abs(clamped - menuBarFontSize) > 0.01 {
                menuBarFontSize = clamped
                return
            }
            d.set(menuBarFontSize, forKey: K.mFontSize)
        }
    }

    var resolvedMenuBarLayout: MenuBarLayout {
        MenuBarLayout.normalized(menuBarLayout, legacyCompact: menuCompact)
    }

    var resolvedMenuBarFontStyle: MenuBarFontStyle {
        MenuBarFontStyle.normalized(menuBarFontStyle)
    }

    var resolvedMenuBarColorMode: MenuBarColorMode {
        MenuBarColorMode.normalized(menuBarColorMode)
    }

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

    // MARK: Agent Center
    static let automaticDisplaySelection = "automatic"

    /// Agent Core remains the sole session owner. This preference controls
    /// whether the core starts on the next launch; turning it off also hides
    /// presentation immediately without tearing down ownership mid-response.
    @Published var agentBehaviorEnabled: Bool {
        didSet { d.set(agentBehaviorEnabled, forKey: K.agentBehaviorEnabled) }
    }
    @Published var agentPresentationEnabled: Bool {
        didSet { d.set(agentPresentationEnabled, forKey: K.agentPresentationEnabled) }
    }
    @Published var agentFullscreenRevealEnabled: Bool {
        didSet { d.set(agentFullscreenRevealEnabled, forKey: K.agentFullscreenRevealEnabled) }
    }
    @Published var agentTargetDisplayUUID: String {
        didSet { d.set(agentTargetDisplayUUID, forKey: K.agentTargetDisplayUUID) }
    }
    @Published var agentEnabledProfileIDs: [String] {
        didSet {
            let normalized = Array(Set(agentEnabledProfileIDs)).sorted()
            if normalized != agentEnabledProfileIDs {
                agentEnabledProfileIDs = normalized
                return
            }
            d.set(agentEnabledProfileIDs, forKey: K.agentEnabledProfileIDs)
        }
    }
    @Published var agentFocusEnabled: Bool {
        didSet { d.set(agentFocusEnabled, forKey: K.agentFocusEnabled) }
    }
    @Published var agentTMUXEnabled: Bool {
        didSet { d.set(agentTMUXEnabled, forKey: K.agentTMUXEnabled) }
    }
    @Published var agentRemoteSSHEnabled: Bool {
        didSet { d.set(agentRemoteSSHEnabled, forKey: K.agentRemoteSSHEnabled) }
    }
    @Published var agentSymbolicCompanionEnabled: Bool {
        didSet { d.set(agentSymbolicCompanionEnabled, forKey: K.agentSymbolicCompanionEnabled) }
    }
    @Published var agentNotificationMuteUntil: Date? {
        didSet {
            if let agentNotificationMuteUntil {
                d.set(agentNotificationMuteUntil, forKey: K.agentNotificationMuteUntil)
            } else {
                d.removeObject(forKey: K.agentNotificationMuteUntil)
            }
        }
    }
    // Pinned Island sound model, persisted under N1KO's single settings
    // authority and N1KO-owned preference namespace.
    @Published var soundEnabled: Bool {
        didSet { d.set(soundEnabled, forKey: K.soundEnabled) }
    }
    @Published var soundVolume: Double {
        didSet {
            let clamped = min(max(soundVolume, 0), 1)
            if soundVolume != clamped { soundVolume = clamped; return }
            d.set(soundVolume, forKey: K.soundVolume)
        }
    }
    @Published var processingStartSound: NotificationSound {
        didSet { d.set(processingStartSound.rawValue, forKey: K.processingStartSound) }
    }
    @Published var attentionRequiredSound: NotificationSound {
        didSet { d.set(attentionRequiredSound.rawValue, forKey: K.attentionRequiredSound) }
    }
    @Published var taskCompletedSound: NotificationSound {
        didSet { d.set(taskCompletedSound.rawValue, forKey: K.taskCompletedSound) }
    }
    @Published var taskErrorSound: NotificationSound {
        didSet { d.set(taskErrorSound.rawValue, forKey: K.taskErrorSound) }
    }
    @Published var resourceLimitSound: NotificationSound {
        didSet { d.set(resourceLimitSound.rawValue, forKey: K.resourceLimitSound) }
    }
    @Published var processingStartSoundEnabled: Bool {
        didSet { d.set(processingStartSoundEnabled, forKey: K.processingStartSoundEnabled) }
    }
    @Published var attentionRequiredSoundEnabled: Bool {
        didSet { d.set(attentionRequiredSoundEnabled, forKey: K.attentionRequiredSoundEnabled) }
    }
    @Published var taskCompletedSoundEnabled: Bool {
        didSet { d.set(taskCompletedSoundEnabled, forKey: K.taskCompletedSoundEnabled) }
    }
    @Published var taskErrorSoundEnabled: Bool {
        didSet { d.set(taskErrorSoundEnabled, forKey: K.taskErrorSoundEnabled) }
    }
    @Published var resourceLimitSoundEnabled: Bool {
        didSet { d.set(resourceLimitSoundEnabled, forKey: K.resourceLimitSoundEnabled) }
    }
    @Published var island8BitProcessingStartSound: Island8BitSound {
        didSet { d.set(island8BitProcessingStartSound.rawValue, forKey: K.island8BitProcessingStartSound) }
    }
    @Published var island8BitAttentionRequiredSound: Island8BitSound {
        didSet { d.set(island8BitAttentionRequiredSound.rawValue, forKey: K.island8BitAttentionRequiredSound) }
    }
    @Published var island8BitTaskCompletedSound: Island8BitSound {
        didSet { d.set(island8BitTaskCompletedSound.rawValue, forKey: K.island8BitTaskCompletedSound) }
    }
    @Published var island8BitTaskErrorSound: Island8BitSound {
        didSet { d.set(island8BitTaskErrorSound.rawValue, forKey: K.island8BitTaskErrorSound) }
    }
    @Published var island8BitResourceLimitSound: Island8BitSound {
        didSet { d.set(island8BitResourceLimitSound.rawValue, forKey: K.island8BitResourceLimitSound) }
    }
    @Published var soundThemeMode: SoundThemeMode {
        didSet { d.set(soundThemeMode.rawValue, forKey: K.soundThemeMode) }
    }
    @Published var selectedSoundPackPath: String {
        didSet { d.set(selectedSoundPackPath, forKey: K.selectedSoundPackPath) }
    }
    /// Compatibility aliases for pre-source-migration N1KO callers. The
    /// canonical state above remains the only persisted sound authority.
    var agentSoundsEnabled: Bool {
        get { soundEnabled }
        set { soundEnabled = newValue }
    }
    var agentCompletionSoundName: String {
        get { taskCompletedSound.rawValue }
        set { taskCompletedSound = NotificationSound(rawValue: newValue) ?? .glass }
    }
    var agentAttentionSoundName: String {
        get { attentionRequiredSound.rawValue }
        set { attentionRequiredSound = NotificationSound(rawValue: newValue) ?? .funk }
    }
    var agentSoundMode: String {
        get {
            switch soundThemeMode {
            case .builtIn: return "system"
            case .island8Bit: return "island8Bit"
            case .soundPack: return "soundPack"
            }
        }
        set {
            switch newValue {
            case "soundPack": soundThemeMode = .soundPack
            case "island8Bit": soundThemeMode = .island8Bit
            default: soundThemeMode = .builtIn
            }
        }
    }
    var agentSoundPackPath: String? {
        get { selectedSoundPackPath.isEmpty ? nil : selectedSoundPackPath }
        set { selectedSoundPackPath = newValue ?? "" }
    }
    @Published var agentNotificationAutoOpen: Bool {
        didSet { d.set(agentNotificationAutoOpen, forKey: K.agentNotificationAutoOpen) }
    }
    @Published var agentMascotAnimationsEnabled: Bool {
        didSet { d.set(agentMascotAnimationsEnabled, forKey: K.agentMascotAnimationsEnabled) }
    }
    @Published var agentMascotOverrides: [String: String] {
        didSet { d.set(agentMascotOverrides, forKey: K.agentMascotOverrides) }
    }
    @Published var agentShowUsage: Bool {
        didSet { d.set(agentShowUsage, forKey: K.agentShowUsage) }
    }

    // MARK: Pinned-source surface compatibility
    // These four values are observed through Combine by the pinned Island view
    // model. They remain properties of N1KO's single settings authority.
    @Published var hideInFullscreen: Bool {
        didSet { d.set(hideInFullscreen, forKey: K.islandHideInFullscreen) }
    }
    @Published var autoHideWhenIdle: Bool {
        didSet { d.set(autoHideWhenIdle, forKey: K.islandAutoHideWhenIdle) }
    }
    @Published var maxPanelHeight: Double {
        didSet {
            let clamped = min(max(maxPanelHeight, 480), 700)
            if clamped != maxPanelHeight { maxPanelHeight = clamped; return }
            d.set(maxPanelHeight, forKey: K.islandMaxPanelHeight)
        }
    }
    @Published var notchModuleWidth: Double {
        didSet {
            let clamped = AppSettingsStore.normalizedNotchModuleWidth(notchModuleWidth)
            if clamped != notchModuleWidth { notchModuleWidth = clamped; return }
            d.set(notchModuleWidth, forKey: K.islandNotchModuleWidth)
        }
    }

    var temporarilyMuteNotificationsUntil: Date? {
        get { agentNotificationMuteUntil }
        set { agentNotificationMuteUntil = newValue }
    }
    var areNotificationsMutedTemporarily: Bool { agentNotificationsTemporarilyMuted }
    var autoCollapseOnLeave: Bool {
        get { d.object(forKey: K.islandAutoCollapseOnLeave) as? Bool ?? true }
        set { objectWillChange.send(); d.set(newValue, forKey: K.islandAutoCollapseOnLeave) }
    }
    var smartSuppression: Bool {
        get { d.object(forKey: K.islandSmartSuppression) as? Bool ?? true }
        set { objectWillChange.send(); d.set(newValue, forKey: K.islandSmartSuppression) }
    }
    var autoOpenCompletionPanel: Bool {
        get { d.object(forKey: K.islandAutoOpenCompletionPanel) as? Bool ?? agentNotificationAutoOpen }
        set { objectWillChange.send(); d.set(newValue, forKey: K.islandAutoOpenCompletionPanel) }
    }
    var autoOpenCompactedNotificationPanel: Bool {
        get { d.object(forKey: K.islandAutoOpenCompactedNotificationPanel) as? Bool ?? agentNotificationAutoOpen }
        set { objectWillChange.send(); d.set(newValue, forKey: K.islandAutoOpenCompactedNotificationPanel) }
    }
    var showAgentDetail: Bool {
        get { d.object(forKey: K.islandShowAgentDetail) as? Bool ?? true }
        set { objectWillChange.send(); d.set(newValue, forKey: K.islandShowAgentDetail) }
    }
    var showUsage: Bool {
        get { agentShowUsage }
        set { agentShowUsage = newValue }
    }
    var usageValueMode: UsageValueMode {
        get { UsageValueMode(rawValue: d.string(forKey: K.islandUsageValueMode) ?? "") ?? .remaining }
        set { objectWillChange.send(); d.set(newValue.rawValue, forKey: K.islandUsageValueMode) }
    }
    var contentFontSize: Double {
        get { d.object(forKey: K.islandContentFontSize) as? Double ?? 13 }
        set {
            objectWillChange.send()
            d.set(min(max(newValue, 11), 17), forKey: K.islandContentFontSize)
        }
    }
    var notchPetStyle: NotchPetStyle {
        get { NotchPetStyle(rawValue: d.string(forKey: K.islandNotchPetStyle) ?? "") ?? .crab }
        set { objectWillChange.send(); d.set(newValue.rawValue, forKey: K.islandNotchPetStyle) }
    }
    @Published var notchDisplayMode: NotchDisplayMode {
        didSet { d.set(notchDisplayMode.rawValue, forKey: K.islandNotchDisplayMode) }
    }
    var closedNotchTrailingContentMode: ClosedNotchTrailingContentMode {
        get { ClosedNotchTrailingContentMode(rawValue: d.string(forKey: K.islandClosedTrailingMode) ?? "") ?? .sessionCount }
        set { objectWillChange.send(); d.set(newValue.rawValue, forKey: K.islandClosedTrailingMode) }
    }
    @Published var surfaceMode: IslandSurfaceMode {
        didSet { d.set(surfaceMode.rawValue, forKey: K.islandSurfaceMode) }
    }
    @Published var floatingPetSizeMode: FloatingPetSizeMode {
        didSet { d.set(floatingPetSizeMode.rawValue, forKey: K.islandFloatingPetSizeMode) }
    }
    var floatingPetSettingsHintPending: Bool {
        get { d.object(forKey: K.islandFloatingPetSettingsHintPending) as? Bool ?? true }
        set { objectWillChange.send(); d.set(newValue, forKey: K.islandFloatingPetSettingsHintPending) }
    }
    var floatingPetAnchor: FloatingPetAnchor? {
        get {
            guard let data = d.data(forKey: K.islandFloatingPetAnchor) else { return nil }
            return try? JSONDecoder().decode(FloatingPetAnchor.self, from: data)
        }
        set {
            objectWillChange.send()
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                d.set(data, forKey: K.islandFloatingPetAnchor)
            } else {
                d.removeObject(forKey: K.islandFloatingPetAnchor)
            }
        }
    }
    var notchDetachmentHintPending: Bool {
        get { d.bool(forKey: K.islandNotchDetachmentHintPending) }
        set { objectWillChange.send(); d.set(newValue, forKey: K.islandNotchDetachmentHintPending) }
    }
    var subagentVisibilityMode: SubagentVisibilityMode { .visible }
    var effectiveRoutePromptsToTerminal: Bool { false }
    var idleAutoRoutePromptsToTerminalActive: Bool { false }

    func shortcut(for action: GlobalShortcutAction) -> GlobalShortcut? { action.defaultShortcut }

    func mascotOverride(for client: MascotClient) -> MascotKind? {
        agentMascotOverrides[client.rawValue].flatMap(MascotKind.init(rawValue:))
    }

    func mascotKind(for client: MascotClient) -> MascotKind {
        mascotOverride(for: client) ?? client.defaultMascotKind
    }

    func mascotKind(for client: MascotClient?) -> MascotKind {
        client.map(mascotKind(for:)) ?? .claude
    }

    var customizedMascotClientCount: Int {
        MascotClient.allCases.filter(hasCustomMascot(for:)).count
    }

    func hasCustomMascot(for client: MascotClient) -> Bool {
        mascotOverride(for: client) != nil
    }

    func setMascotOverride(_ mascot: MascotKind?, for client: MascotClient) {
        setAgentMascotOverride(mascot?.rawValue, providerRawValue: client.rawValue)
    }

    func resetMascotOverrides() {
        resetAgentMascotOverrides()
    }
    var agentNotificationsTemporarilyMuted: Bool {
        guard let until = agentNotificationMuteUntil else { return false }
        return until > Date()
    }

    func toggleAgentNotificationMute(duration: TimeInterval = 10 * 60) {
        agentNotificationMuteUntil = agentNotificationsTemporarilyMuted
            ? nil
            : Date().addingTimeInterval(duration)
    }

    func setAgentMascotOverride(_ mascotRawValue: String?, providerRawValue: String) {
        if let mascotRawValue, !mascotRawValue.isEmpty {
            agentMascotOverrides[providerRawValue] = mascotRawValue
        } else {
            agentMascotOverrides.removeValue(forKey: providerRawValue)
        }
    }

    func resetAgentMascotOverrides() {
        agentMascotOverrides.removeAll()
    }

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
            guard fanCurve != oldValue else { return }
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
    static let menuBarFontSizeRange: ClosedRange<Double> = 8...13
    static let menuBarRecommendedMaxWidth: CGFloat = 220

    var accent: Color { Color(hex: accentHex) }

    static func clampMenuBarFontSize(_ value: Double) -> Double {
        min(max(value, menuBarFontSizeRange.lowerBound), menuBarFontSizeRange.upperBound)
    }

    private let d = UserDefaults.standard

    private init() {
        // Registered defaults are not user choices. Capture the persistent
        // domain first so legacy N1KO sound selections migrate only when they
        // were actually stored; untouched installs receive the pinned source
        // defaults (Glass attention, Blow completion).
        let persistedValues: [String: Any]
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            persistedValues = d.persistentDomain(forName: bundleIdentifier) ?? [:]
        } else {
            persistedValues = [:]
        }

        // Register defaults first so first-launch reads are sensible.
        d.register(defaults: [
            K.refresh: 1.0, K.accent: Int(0x5E5CE6), K.fahrenheit: false,
            K.sDetail: false, K.lang: LocalizationManager.system,
            K.cCPU: true, K.cGPU: true, K.cMem: true, K.cDisk: true, K.cNet: true, K.cSens: true,
            K.cBat: true,
            K.cOrder: Module.allCases.map { $0.rawValue },
            K.mCPU: true, K.mGPU: true, K.mMem: false, K.mNet: false,             K.mBat: false,
            K.mOrder: MenuBarMetric.allCases.map(\.rawValue),
            K.mFontStyle: MenuBarFontStyle.rounded.rawValue,
            K.mColorMode: MenuBarColorMode.colorful.rawValue,
            K.mFontSize: 11.0,
            K.popStyle: "cards",
            K.agentBehaviorEnabled: true,
            K.agentPresentationEnabled: true,
            K.agentFullscreenRevealEnabled: true,
            K.agentTargetDisplayUUID: Self.automaticDisplaySelection,
            K.agentEnabledProfileIDs: [],
            K.agentFocusEnabled: false,
            K.agentTMUXEnabled: false,
            K.agentRemoteSSHEnabled: false,
            K.agentSymbolicCompanionEnabled: false,
            K.agentSoundsEnabled: true,
            K.agentNotificationAutoOpen: true,
            K.agentMascotAnimationsEnabled: true,
            K.agentMascotOverrides: [:],
            K.agentCompletionSoundName: "Glass",
            K.agentAttentionSoundName: "Funk",
            K.agentSoundMode: "system",
            K.agentShowUsage: true,
            K.islandHideInFullscreen: true,
            K.islandAutoHideWhenIdle: false,
            K.islandMaxPanelHeight: 560.0,
            K.islandNotchModuleWidth: AppSettingsStore.defaultNotchModuleWidth,
            K.islandNotchDisplayMode: NotchDisplayMode.detailed.rawValue,
            K.islandSurfaceMode: IslandSurfaceMode.notch.rawValue,
            K.islandFloatingPetSizeMode: FloatingPetSizeMode.automatic.rawValue,
            K.islandFloatingPetSettingsHintPending: true,
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
        let storedMenuCompact = d.bool(forKey: K.mCompact)
        let storedMenuLayout = MenuBarLayout
            .normalized(d.object(forKey: K.mLayout) as? String, legacyCompact: storedMenuCompact)
        menuCompact = storedMenuLayout == .compact
        menuBarLayout = storedMenuLayout.rawValue
        menuBarOrder = (d.array(forKey: K.mOrder) as? [String]) ?? MenuBarMetric.allCases.map(\.rawValue)
        menuBarFontStyle = MenuBarFontStyle.normalized(d.string(forKey: K.mFontStyle)).rawValue
        menuBarColorMode = MenuBarColorMode.normalized(d.string(forKey: K.mColorMode)).rawValue
        menuBarFontSize = Self.clampMenuBarFontSize(d.object(forKey: K.mFontSize) as? Double ?? 11.0)
        popoverStyle = d.string(forKey: K.popStyle) ?? "cards"
        agentBehaviorEnabled = d.bool(forKey: K.agentBehaviorEnabled)
        agentPresentationEnabled = d.bool(forKey: K.agentPresentationEnabled)
        agentFullscreenRevealEnabled = d.bool(forKey: K.agentFullscreenRevealEnabled)
        agentTargetDisplayUUID = d.string(forKey: K.agentTargetDisplayUUID)
            ?? Self.automaticDisplaySelection
        agentEnabledProfileIDs = d.stringArray(forKey: K.agentEnabledProfileIDs) ?? []
        agentFocusEnabled = d.bool(forKey: K.agentFocusEnabled)
        agentTMUXEnabled = d.bool(forKey: K.agentTMUXEnabled)
        agentRemoteSSHEnabled = d.bool(forKey: K.agentRemoteSSHEnabled)
        agentSymbolicCompanionEnabled = d.bool(forKey: K.agentSymbolicCompanionEnabled)
        agentNotificationMuteUntil = d.object(forKey: K.agentNotificationMuteUntil) as? Date
        soundEnabled = d.object(forKey: K.soundEnabled) as? Bool
            ?? d.bool(forKey: K.agentSoundsEnabled)
        soundVolume = d.object(forKey: K.soundVolume) as? Double ?? 0.9
        processingStartSound = NotificationSound(
            rawValue: d.string(forKey: K.processingStartSound) ?? ""
        ) ?? .tink
        attentionRequiredSound = NotificationSound(
            rawValue: d.string(forKey: K.attentionRequiredSound)
                ?? (persistedValues[K.agentAttentionSoundName] as? String)
                ?? ""
        ) ?? .glass
        taskCompletedSound = NotificationSound(
            rawValue: d.string(forKey: K.taskCompletedSound)
                ?? (persistedValues[K.agentCompletionSoundName] as? String)
                ?? ""
        ) ?? .blow
        taskErrorSound = NotificationSound(
            rawValue: d.string(forKey: K.taskErrorSound) ?? ""
        ) ?? .basso
        resourceLimitSound = NotificationSound(
            rawValue: d.string(forKey: K.resourceLimitSound) ?? ""
        ) ?? .morse
        processingStartSoundEnabled = d.object(forKey: K.processingStartSoundEnabled) as? Bool ?? true
        attentionRequiredSoundEnabled = d.object(forKey: K.attentionRequiredSoundEnabled) as? Bool ?? true
        taskCompletedSoundEnabled = d.object(forKey: K.taskCompletedSoundEnabled) as? Bool ?? true
        taskErrorSoundEnabled = d.object(forKey: K.taskErrorSoundEnabled) as? Bool ?? true
        resourceLimitSoundEnabled = d.object(forKey: K.resourceLimitSoundEnabled) as? Bool ?? true
        island8BitProcessingStartSound = Island8BitSound(
            rawValue: d.string(forKey: K.island8BitProcessingStartSound) ?? ""
        ) ?? .menuSelect
        island8BitAttentionRequiredSound = Island8BitSound(
            rawValue: d.string(forKey: K.island8BitAttentionRequiredSound) ?? ""
        ) ?? .approvalAlert
        island8BitTaskCompletedSound = Island8BitSound(
            rawValue: d.string(forKey: K.island8BitTaskCompletedSound) ?? ""
        ) ?? .submitBlip
        island8BitTaskErrorSound = Island8BitSound(
            rawValue: d.string(forKey: K.island8BitTaskErrorSound) ?? ""
        ) ?? .hurt
        island8BitResourceLimitSound = Island8BitSound(
            rawValue: d.string(forKey: K.island8BitResourceLimitSound) ?? ""
        ) ?? .completeDing
        let migratedSoundMode = d.string(forKey: K.soundThemeMode)
            ?? d.string(forKey: K.agentSoundMode)
        switch migratedSoundMode {
        case "soundPack": soundThemeMode = .soundPack
        case "island8Bit": soundThemeMode = .island8Bit
        default: soundThemeMode = .builtIn
        }
        selectedSoundPackPath = d.string(forKey: K.selectedSoundPackPath)
            ?? d.string(forKey: K.agentSoundPackPath)
            ?? ""
        agentNotificationAutoOpen = d.bool(forKey: K.agentNotificationAutoOpen)
        agentMascotAnimationsEnabled = d.bool(forKey: K.agentMascotAnimationsEnabled)
        agentMascotOverrides = d.dictionary(forKey: K.agentMascotOverrides) as? [String: String] ?? [:]
        agentShowUsage = d.bool(forKey: K.agentShowUsage)
        hideInFullscreen = d.bool(forKey: K.islandHideInFullscreen)
        autoHideWhenIdle = d.bool(forKey: K.islandAutoHideWhenIdle)
        maxPanelHeight = d.double(forKey: K.islandMaxPanelHeight)
        notchModuleWidth = AppSettingsStore.normalizedNotchModuleWidth(
            d.double(forKey: K.islandNotchModuleWidth)
        )
        notchDisplayMode = NotchDisplayMode(
            rawValue: d.string(forKey: K.islandNotchDisplayMode) ?? ""
        ) ?? .detailed
        surfaceMode = IslandSurfaceMode(
            rawValue: d.string(forKey: K.islandSurfaceMode) ?? ""
        ) ?? .notch
        floatingPetSizeMode = FloatingPetSizeMode(
            rawValue: d.string(forKey: K.islandFloatingPetSizeMode) ?? ""
        ) ?? .automatic
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
        static let mBat = "menuBattery", mCompact = "menuCompact"
        static let mLayout = "menuBarLayout", mOrder = "menuBarOrder"
        static let mFontStyle = "menuBarFontStyle", mColorMode = "menuBarColorMode"
        static let mFontSize = "menuBarFontSize"
        static let popStyle = "popoverStyle"
        static let agentBehaviorEnabled = "agent.behavior.enabled"
        static let agentPresentationEnabled = "agent.presentation.enabled"
        static let agentFullscreenRevealEnabled = "agent.presentation.fullscreenRevealEnabled"
        static let agentTargetDisplayUUID = "agent.presentation.targetDisplayUUID"
        static let agentEnabledProfileIDs = "agent.integration.enabledProfiles"
        static let agentFocusEnabled = "agent.integration.focusEnabled"
        static let agentTMUXEnabled = "agent.integration.tmuxEnabled"
        static let agentRemoteSSHEnabled = "agent.integration.remoteSSHEnabled"
        static let agentSymbolicCompanionEnabled = "agent.integration.symbolicCompanionEnabled"
        static let agentNotificationMuteUntil = "agent.presentation.notificationMuteUntil"
        static let agentSoundsEnabled = "agent.presentation.soundsEnabled"
        static let soundEnabled = "agent.sound.enabled"
        static let soundVolume = "agent.sound.volume"
        static let processingStartSound = "agent.sound.processingStarted.system"
        static let attentionRequiredSound = "agent.sound.attentionRequired.system"
        static let taskCompletedSound = "agent.sound.taskCompleted.system"
        static let taskErrorSound = "agent.sound.taskError.system"
        static let resourceLimitSound = "agent.sound.resourceLimit.system"
        static let processingStartSoundEnabled = "agent.sound.processingStarted.enabled"
        static let attentionRequiredSoundEnabled = "agent.sound.attentionRequired.enabled"
        static let taskCompletedSoundEnabled = "agent.sound.taskCompleted.enabled"
        static let taskErrorSoundEnabled = "agent.sound.taskError.enabled"
        static let resourceLimitSoundEnabled = "agent.sound.resourceLimit.enabled"
        static let island8BitProcessingStartSound = "agent.sound.processingStarted.island8Bit"
        static let island8BitAttentionRequiredSound = "agent.sound.attentionRequired.island8Bit"
        static let island8BitTaskCompletedSound = "agent.sound.taskCompleted.island8Bit"
        static let island8BitTaskErrorSound = "agent.sound.taskError.island8Bit"
        static let island8BitResourceLimitSound = "agent.sound.resourceLimit.island8Bit"
        static let soundThemeMode = "agent.sound.themeMode"
        static let selectedSoundPackPath = "agent.sound.selectedPackPath"
        static let agentNotificationAutoOpen = "agent.presentation.notificationAutoOpen"
        static let agentMascotAnimationsEnabled = "agent.presentation.mascotAnimationsEnabled"
        static let agentMascotOverrides = "agent.presentation.mascotOverrides"
        static let agentCompletionSoundName = "agent.presentation.completionSoundName"
        static let agentAttentionSoundName = "agent.presentation.attentionSoundName"
        static let agentSoundMode = "agent.presentation.soundMode"
        static let agentSoundPackPath = "agent.presentation.soundPackPath"
        static let agentShowUsage = "agent.presentation.showUsage"
        static let islandHideInFullscreen = "agent.island.hideInFullscreen"
        static let islandAutoHideWhenIdle = "agent.island.autoHideWhenIdle"
        static let islandAutoCollapseOnLeave = "agent.island.autoCollapseOnLeave"
        static let islandSmartSuppression = "agent.island.smartSuppression"
        static let islandAutoOpenCompletionPanel = "agent.island.autoOpenCompletionPanel"
        static let islandAutoOpenCompactedNotificationPanel = "agent.island.autoOpenCompactedNotificationPanel"
        static let islandShowAgentDetail = "agent.island.showAgentDetail"
        static let islandUsageValueMode = "agent.island.usageValueMode"
        static let islandContentFontSize = "agent.island.contentFontSize"
        static let islandMaxPanelHeight = "agent.island.maxPanelHeight"
        static let islandNotchModuleWidth = "agent.island.notchModuleWidth"
        static let islandNotchPetStyle = "agent.island.notchPetStyle"
        static let islandNotchDisplayMode = "agent.island.notchDisplayMode"
        static let islandClosedTrailingMode = "agent.island.closedTrailingMode"
        static let islandSurfaceMode = "agent.island.surfaceMode"
        static let islandFloatingPetSizeMode = "agent.island.floatingPetSizeMode"
        static let islandFloatingPetSettingsHintPending = "agent.island.floatingPetSettingsHintPending"
        static let islandFloatingPetAnchor = "agent.island.floatingPetAnchor"
        static let islandNotchDetachmentHintPending = "agent.island.notchDetachmentHintPending"
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
