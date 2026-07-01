import AppKit
import Combine
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case menuBar = "Menu Bar"
    case popover = "Popover"
    case sampling = "Sampling & Performance"
    case sensors = "Sensors & Fans"
    case alerts = "Alerts"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .menuBar: return "menubar.rectangle"
        case .popover: return "rectangle.on.rectangle"
        case .sampling: return "speedometer"
        case .sensors: return "thermometer.medium"
        case .alerts: return "bell.badge"
        case .advanced: return "slider.horizontal.3"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .overview: return .general
        case .menuBar, .popover: return .display
        case .sampling: return .performance
        case .sensors, .alerts: return .hardware
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
    case performance
    case hardware
    case system

    var title: String {
        switch self {
        case .general: return "General".loc
        case .display: return "Display & Popover".loc
        case .performance: return "Performance".loc
        case .hardware: return "Hardware".loc
        case .system: return "System & Advanced".loc
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var chartRange = ChartRangeStore.shared
    @ObservedObject var fans: FanControlService
    var hub: MonitorHub?
    @State private var tab: SettingsTab
    @State private var exportMessage: String?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var moduleFilter = ""
    @State private var settingsSearch = ""

    init(fans: FanControlService, hub: MonitorHub? = nil, initialTab: SettingsTab? = nil) {
        self.fans = fans
        self.hub = hub
        _tab = State(initialValue: initialTab ?? .overview)
    }

    private let languages: [(code: String, label: String)] = [
        (LocalizationManager.system, "System"),
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文")
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.stroke)
            ScrollView(.vertical, showsIndicators: true) {
                page
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
        }
        .frame(minWidth: 900, idealWidth: 980, maxWidth: .infinity,
               minHeight: 600, idealHeight: 720, maxHeight: .infinity)
        .controlSize(.small)
        .background(Theme.surfaceMaterial)
        .id(settings.language)
        .id(settings.appTheme)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("N1KO STATE")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text(loc: "Settings")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 20)

            TextField("Search settings".loc, text: $settingsSearch)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredSidebarGroups, id: \.group) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.group.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.textTertiary)
                                .padding(.horizontal, 10)

                            ForEach(section.tabs) { t in
                                SettingsSidebarItem(tab: t, isSelected: tab == t, accent: settings.accent) {
                                    tab = t
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SettingGroup(title: "Current Cost", compact: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(loc: resourceModeTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        CostBadge(text: resourceModeBadge, color: resourceModeColor)
                    }
                    Text(loc: "Idle work is reduced when the popover is closed.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
    }

    private var filteredSidebarGroups: [(group: SettingsGroup, tabs: [SettingsTab])] {
        let query = settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return SettingsTab.grouped }
        return SettingsTab.grouped.compactMap { section in
            let tabs = section.tabs.filter {
                $0.rawValue.loc.lowercased().contains(query) || section.group.title.lowercased().contains(query)
            }
            return tabs.isEmpty ? nil : (section.group, tabs)
        }
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch tab {
        case .overview: overviewPage
        case .menuBar: menuBarPage
        case .popover: popoverPage
        case .sampling: samplingPage
        case .sensors: sensorsPage
        case .alerts: alertsPage
        case .advanced: advancedPage
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Overview",
                           subtitle: "Menu bar, popover, sampling, and thermal safety at a glance.")

            SettingGroup(title: "Live Preview") {
                MenuBarPreviewView(hub: hub)
            }

            HStack(alignment: .top, spacing: 10) {
                OverviewCard(title: "Sampling",
                             value: resourceModeTitle,
                             detail: resourceModeDetail,
                             badge: resourceModeBadge,
                             color: resourceModeColor,
                             icon: "speedometer")
                OverviewCard(title: "Safety",
                             value: safetyStatusLabel,
                             detail: safetyStatusDetail,
                             badge: safetyStatusBadge,
                             color: safetyStatusColor,
                             icon: "shield.checkered")
                OverviewCard(title: "Attention",
                             value: "\(attentionItems.count)",
                             detail: attentionSummary,
                             badge: attentionItems.isEmpty ? "Clean" : "Review",
                             color: attentionItems.isEmpty ? Theme.ok : Theme.warn,
                             icon: "exclamationmark.triangle")
            }

            SettingGroup(title: "Recommended Actions") {
                VStack(spacing: 0) {
                    OverviewActionRow(icon: "menubar.rectangle",
                                      title: "Menu bar display",
                                      detail: "Preview width, color mode, and visible metrics.",
                                      status: "Active metrics: %d".locf(activeMenuMetricCount)) {
                        tab = .menuBar
                    }
                    SettingsDivider()
                    OverviewActionRow(icon: "speedometer",
                                      title: "Sampling cost",
                                      detail: "Choose the background refresh profile.",
                                      status: resourceModeTitle) {
                        tab = .sampling
                    }
                    SettingsDivider()
                    OverviewActionRow(icon: "thermometer.medium",
                                      title: "Sensors and fans",
                                      detail: "Check helper status and thermal controls.",
                                      status: safetyStatusBadge) {
                        tab = .sensors
                    }
                }
            }
        }
    }

    private var batteryIsAvailable: Bool {
        hub?.battery.isPresent == true
    }

    private var menuBarPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Menu Bar",
                           subtitle: "Choose the always-visible readout and keep it legible in every menu-bar state.")

            HStack(alignment: .top, spacing: 20) {
                SettingGroup(title: "Metrics") {
                    List {
                        ForEach(settings.orderedMenuBarMetrics) { m in
                            MenuBarMetricRow(
                                metric: m,
                                isOn: menuBarBinding(m),
                                accent: settings.accent,
                                disabled: m == .battery && !batteryIsAvailable,
                                note: m == .battery && !batteryIsAvailable ? "No battery detected on this Mac." : nil
                            )
                        }
                        .onMove { source, dest in
                            var order = settings.orderedMenuBarMetrics.map(\.rawValue)
                            order.move(fromOffsets: source, toOffset: dest)
                            settings.menuBarOrder = order
                        }
                    }
                    .listStyle(.plain)
                    .hiddenScrollContentBackground()
                    .frame(minHeight: 150)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc: "Live Preview")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                    SettingGroup(title: nil) {
                        MenuBarPreviewView(hub: hub, expanded: true)
                    }
                    .frame(width: Theme.popoverWidth)
                }
            }

            SettingGroup(title: "Appearance") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsChoiceGroup(
                        label: "Color Mode",
                        detail: MenuBarColorMode.normalized(settings.menuBarColorMode).detail,
                        options: MenuBarColorMode.allCases.map { ($0.rawValue, $0.title) },
                        selection: $settings.menuBarColorMode,
                        accent: settings.accent
                    )
                    SettingsChoiceGroup(
                        label: "Layout",
                        detail: MenuBarLayout.normalized(settings.menuBarLayout, legacyCompact: settings.menuCompact).title,
                        options: MenuBarLayout.allCases.map { ($0.rawValue, $0.title) },
                        selection: $settings.menuBarLayout,
                        accent: settings.accent,
                        columns: 2
                    )
                    SettingsChoiceGroup(
                        label: "Font Style",
                        options: MenuBarFontStyle.allCases.map { ($0.rawValue, $0.title) },
                        selection: $settings.menuBarFontStyle,
                        accent: settings.accent
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc: "Font Size")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text(loc: "Keep the preview within the recommended width.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: 10) {
                            Slider(value: $settings.menuBarFontSize,
                                   in: AppSettings.menuBarFontSizeRange,
                                   step: 0.5)
                                .tint(settings.accent)
                            Text(String(format: "%.1f", settings.menuBarFontSize))
                                .font(.metric(11))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                    HStack {
                        Spacer()
                        Button(action: resetMenuBarDefaults) {
                            Text(loc: "Reset Menu Bar")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear {
            if settings.menuBattery && !batteryIsAvailable {
                settings.menuBattery = false
            }
        }
    }

    private var popoverPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Popover",
                           subtitle: "Control the click-open panel separately from the always-on menu bar.")

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingGroup(title: "Display Options") {
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsChoiceGroup(
                                label: "Popover Style",
                                detail: settings.popoverStyle == "gauges"
                                    ? "Compact dashboard with ring gauges."
                                    : "Detailed cards with charts and process lists.",
                                options: [("cards", "Cards"), ("gauges", "Gauges")],
                                selection: $settings.popoverStyle,
                                accent: settings.accent
                            )
                            SettingsChoiceGroup(
                                label: "Chart Range",
                                options: HistoryStore.Range.allCases.map { ($0.rawValue, $0.rawValue.uppercased()) },
                                selection: $chartRange.range,
                                accent: settings.accent
                            )
                        }
                    }

                    SettingGroup(title: "Modules") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Search modules".loc, text: $moduleFilter)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                            List {
                                ForEach(filteredModules) { m in
                                    ModuleListRow(
                                        module: m,
                                        isOn: visibilityBinding(m),
                                        accent: settings.accent,
                                        disabled: m == .battery && !batteryIsAvailable,
                                        note: m == .battery && !batteryIsAvailable ? "No battery detected on this Mac." : nil
                                    )
                                }
                                .onMove { source, destination in
                                    guard moduleFilter.isEmpty else { return }
                                    var order = settings.orderedModules.map(\.rawValue)
                                    order.move(fromOffsets: source, toOffset: destination)
                                    settings.moduleOrder = order
                                }
                            }
                            .listStyle(.plain)
                            .hiddenScrollContentBackground()
                            .frame(minHeight: 220)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc: "Live Preview")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                    if let hub {
                        PopoverPreviewView(hub: hub)
                    } else {
                        SettingGroup(title: nil) {
                            Text(loc: "Open settings from the menu bar to see a live popover preview.")
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: Theme.popoverWidth, alignment: .leading)
                        }
                    }
                }
            }
        }
        .onAppear {
            if settings.showBattery && !batteryIsAvailable {
                settings.showBattery = false
            }
        }
    }

    private var samplingPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Sampling & Performance",
                           subtitle: "Tune how much work the app performs while it is hidden or visible.")
            SettingGroup(title: "Refresh Profile") {
                SettingsChoiceGroup(
                    label: "Refresh Interval",
                    detail: "Lower intervals feel more live but wake the app more often.",
                    options: [
                        (3.0, "Quiet"),
                        (2.0, "Low Impact"),
                        (1.0, "Balanced"),
                        (0.5, "Real Time")
                    ],
                    selection: $settings.refreshInterval,
                    accent: settings.accent,
                    columns: 2
                )
            }

            SettingGroup(title: "Cost Map") {
                VStack(spacing: 0) {
                    PerformanceCostRow(name: "CPU / Memory",
                                       detail: "Sampled for visible menu-bar metrics, alerts, and 30s history.",
                                       background: cpuMemoryBackgroundCost,
                                       visible: foregroundSamplingCadence)
                    SettingsDivider()
                    PerformanceCostRow(name: "Network",
                                       detail: "Rates update live only when the menu bar or popover needs them.",
                                       background: networkBackgroundCost,
                                       visible: foregroundSamplingCadence)
                    SettingsDivider()
                    PerformanceCostRow(name: "Processes",
                                       detail: "Top processes are only sampled while the popover needs CPU or memory detail.",
                                       background: "Stopped",
                                       visible: "5s")
                    SettingsDivider()
                    PerformanceCostRow(name: "Sensors / Fans",
                                       detail: "Thermal safety, manual fan mode, and fan curves keep this path active.",
                                       background: sensorsBackgroundCost,
                                       visible: "2s")
                    SettingsDivider()
                    PerformanceCostRow(name: "Disk Volumes",
                                       detail: "Mount changes are event-driven; free-space checks stay slow.",
                                       background: "Event driven",
                                       visible: "On open")
                }
            }
        }
    }

    private var sensorsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Sensors & Fans",
                           subtitle: "Keep temperature display and fan control together because they share the same safety boundary.")
            SettingGroup(title: "Display Options") {
                VStack(spacing: 2) {
                    ToggleRow(label: "Show temperatures in Fahrenheit",
                              isOn: $settings.useFahrenheit, accent: settings.accent)
                    ToggleRow(label: "Show individual sensors",
                              isOn: $settings.sensorsDetailed, accent: settings.accent)
                }
            }
            SettingGroup(title: "Fan Control") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(loc: "Helper status")
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(helperStatusLabel)
                            .font(.metric(11))
                            .foregroundColor(helperStatusColor)
                    }
                    HStack(spacing: 8) {
                        Button(action: { fans.warmAuthorization() }) {
                            Text(loc: "Install / Reinstall Helper")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accent)
                        .disabled(fans.helperState == .installing)

                        Button(action: { fans.uninstallHelper() }) {
                            Text(loc: "Uninstall Helper")
                        }
                        .buttonStyle(.bordered)
                        .disabled(fans.helperState == .installing)
                    }
                    if let err = fans.lastError, fans.helperState != .ready {
                        Text(err)
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(loc: "Use Auto/Manual in the Sensors card. Adjust the slider to set a target RPM; manual changes are applied automatically. Quitting the app restores automatic control.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if fans.supportsControl {
                SettingGroup(title: "Fan Curve") {
                    VStack(alignment: .leading, spacing: 10) {
                        ToggleRow(label: "Automatic fan curve",
                                  isOn: $settings.fanCurveEnabled, accent: settings.accent)
                        Text(loc: "Adjust fan speed from peak temperature. Manual control is disabled while the curve is active.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if settings.fanCurve.count >= 3 {
                            fanCurveRow(index: 0, label: "Low temp")
                            fanCurveRow(index: 1, label: "Mid temp")
                            fanCurveRow(index: 2, label: "High temp")
                        }
                    }
                }
            } else if fans.isAvailable {
                Text(loc: "This device does not support manual fan control.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .onAppear { fans.refreshHelperStatus() }
    }

    private var alertsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Alerts",
                           subtitle: "Get a notification when a metric crosses a limit.")

            SettingGroup(title: nil) {
                ToggleRow(label: "Enable alerts", isOn: $settings.alertsEnabled, accent: settings.accent)
            }

            SettingGroup(title: "Thresholds") {
                VStack(spacing: 10) {
                    AlertRow(label: "CPU usage",
                             enabled: $settings.cpuAlert,
                             value: $settings.cpuThreshold,
                             range: 0.5...1.0, step: 0.05,
                             format: { Formatters.percent($0) },
                             accent: settings.accent,
                             disabled: !settings.alertsEnabled)
                    Divider().overlay(Theme.stroke)
                    AlertRow(label: "Memory usage",
                             enabled: $settings.memAlert,
                             value: $settings.memThreshold,
                             range: 0.5...1.0, step: 0.05,
                             format: { Formatters.percent($0) },
                             accent: settings.accent,
                             disabled: !settings.alertsEnabled)
                    Divider().overlay(Theme.stroke)
                    AlertRow(label: "Temperature",
                             enabled: $settings.tempAlert,
                             value: $settings.tempThreshold,
                             range: 60...100, step: 1,
                             format: { Formatters.temperature($0) },
                             accent: settings.accent,
                             disabled: !settings.alertsEnabled)
                    Divider().overlay(Theme.stroke)
                    AlertRow(label: "Low disk space",
                             enabled: $settings.diskAlert,
                             value: $settings.diskFreeThreshold,
                             range: 0.05...0.40, step: 0.05,
                             format: { Formatters.percent($0) },
                             accent: settings.accent,
                             disabled: !settings.alertsEnabled)
                    Divider().overlay(Theme.stroke)
                    AlertRow(label: "Low battery",
                             enabled: $settings.batteryAlert,
                             value: $settings.batteryThreshold,
                             range: 0.05...0.50, step: 0.05,
                             format: { Formatters.percent($0) },
                             accent: settings.accent,
                             disabled: !settings.alertsEnabled)
                }
            }
            .opacity(settings.alertsEnabled ? 1 : 0.45)
        }
    }

    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Advanced",
                           subtitle: "Language, appearance, startup, diagnostics, and maintenance.")
            SettingGroup(title: "Basics") {
                VStack(spacing: 0) {
                    SettingsRow(label: "Language") {
                        Picker("", selection: $settings.language) {
                            ForEach(languages, id: \.code) { lang in
                                Text(lang.code == LocalizationManager.system ? "System".loc : lang.label)
                                    .tag(lang.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    SettingsDivider()
                    SettingsChoiceGroup(
                        label: "Appearance",
                        options: [
                            ("system", "System"),
                            ("light", "Light"),
                            ("dark", "Dark")
                        ],
                        selection: $settings.appTheme,
                        accent: settings.accent
                    )
                    SettingsDivider()
                    SettingsRow(label: "Accent Color") {
                        HStack(spacing: 10) {
                            ForEach(AppSettings.accentPalette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().strokeBorder(Theme.textPrimary.opacity(0.85),
                                                              lineWidth: settings.accentHex == hex ? 2 : 0)
                                    )
                                    .onTapGesture { settings.accentHex = hex }
                                    .help("#\(String(format: "%06X", hex))")
                            }
                            Divider().frame(height: 20).overlay(Theme.stroke)
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: settings.accentHex) },
                                set: { if let hex = $0.toHexInt() { settings.accentHex = hex } }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            Text(loc: "Custom")
                                .font(.system(size: 11)).foregroundColor(Theme.textSecondary)
                        }
                    }
                    if LoginItem.isAvailable {
                        SettingsDivider()
                        SettingsRow(label: "Launch at login") {
                            Toggle("", isOn: Binding(get: { launchAtLogin },
                                                     set: { launchAtLogin = $0; LoginItem.set($0) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(settings.accent)
                        }
                    }
                }
            }

            SettingGroup(title: "Maintenance") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: "N1KO-STATE \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.15")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(loc: "A modern macOS system monitor.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                    Text(loc: "Includes SMCKit (MIT, © 2014–2017 beltex).")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                    HStack(spacing: 8) {
                        Button(action: { UpdateController.shared.checkForUpdates(nil) }) {
                            Text(loc: "Check for Updates…")
                        }
                        .buttonStyle(.bordered)
                        Button(action: openLogFolder) {
                            Text(loc: "Open Log Folder")
                        }
                        .buttonStyle(.bordered)
                        Button(action: exportDiagnostic) {
                            Text(loc: "Export Diagnostic Report")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accent)
                        .disabled(hub == nil)
                    }
                    if let exportMessage {
                        Text(exportMessage)
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Bindings / derived state

    private var activeMenuMetricCount: Int {
        [settings.menuCPU, settings.menuGPU, settings.menuMemory, settings.menuNetwork, settings.menuBattery]
            .filter { $0 }.count
    }

    private var resourceModeTitle: String {
        switch settings.refreshInterval {
        case ..<0.75: return "Real Time"
        case ..<1.5: return "Balanced"
        case ..<2.5: return "Low Impact"
        default: return "Quiet"
        }
    }

    private var resourceModeBadge: String {
        switch settings.refreshInterval {
        case ..<0.75: return "Highest"
        case ..<1.5: return "Normal"
        default: return "Low"
        }
    }

    private var resourceModeDetail: String {
        switch settings.refreshInterval {
        case ..<0.75: return "Best for short diagnostic sessions."
        case ..<1.5: return "Good live feel with modest background work."
        default: return "Best for leaving the app running all day."
        }
    }

    private var resourceModeColor: Color {
        switch settings.refreshInterval {
        case ..<0.75: return Theme.warn
        case ..<1.5: return Theme.info
        default: return Theme.ok
        }
    }

    private var cpuMemoryBackgroundCost: String {
        settings.menuCPU || settings.menuMemory || settings.alertsEnabled ? "Visible" : "30s"
    }

    private var networkBackgroundCost: String {
        settings.menuNetwork ? "Visible" : "30s"
    }

    private var foregroundSamplingCadence: String {
        settings.refreshInterval < 0.75 ? "Every tick" : "Live popover / 2s menu"
    }

    private var sensorsBackgroundCost: String {
        settings.fanCurveEnabled || fans.mode == .manual || settings.tempAlert && settings.alertsEnabled ? "Safety" : "On demand"
    }

    private var attentionItems: [String] {
        var items: [String] = []
        if !settings.alertsEnabled { items.append("Alerts are off") }
        if settings.menuNetwork { items.append("Network is live in the menu bar") }
        if settings.refreshInterval < 0.75 { items.append("Real-time sampling is active") }
        if settings.resolvedMenuBarColorMode == .colorful { items.append("Colorful menu-bar mode is active") }
        return items
    }

    private var attentionSummary: String {
        guard !attentionItems.isEmpty else { return "Nothing needs attention." }
        return attentionItems.prefix(2).map { $0.loc }.joined(separator: " · ")
    }

    private var safetyStatusLabel: String {
        if fans.supportsControl { return "Protected" }
        if fans.isAvailable { return "Read-only" }
        return "Unavailable"
    }

    private var safetyStatusDetail: String {
        if fans.supportsControl { return "Thermal safety stays active during fan control." }
        if fans.isAvailable { return "Fan speed can be read, but this device does not expose control." }
        return "No fan sensors are exposed on this device."
    }

    private var safetyStatusBadge: String {
        if fans.supportsControl { return "Ready" }
        if fans.isAvailable { return "Read-only" }
        return "Limited"
    }

    private var safetyStatusColor: Color {
        if fans.supportsControl { return Theme.ok }
        if fans.isAvailable { return Theme.warn }
        return Theme.textTertiary
    }

    private var filteredModules: [Module] {
        let modules = settings.orderedModules
        let query = moduleFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return modules }
        return modules.filter { $0.localizedTitle.lowercased().contains(query) || $0.rawValue.contains(query) }
    }

    private func resetMenuBarDefaults() {
        settings.menuCPU = true
        settings.menuGPU = true
        settings.menuMemory = false
        settings.menuNetwork = false
        settings.menuBattery = false
        settings.menuBarLayout = MenuBarLayout.standard.rawValue
        settings.menuBarColorMode = MenuBarColorMode.colorful.rawValue
        settings.menuBarOrder = MenuBarMetric.allCases.map(\.rawValue)
        settings.menuBarFontStyle = MenuBarFontStyle.rounded.rawValue
        settings.menuBarFontSize = 11.0
    }

    private func menuBarBinding(_ m: MenuBarMetric) -> Binding<Bool> {
        switch m {
        case .cpu: return $settings.menuCPU
        case .gpu: return $settings.menuGPU
        case .memory: return $settings.menuMemory
        case .battery: return $settings.menuBattery
        case .network: return $settings.menuNetwork
        }
    }

    private func visibilityBinding(_ m: Module) -> Binding<Bool> {
        switch m {
        case .cpu:     return $settings.showCPU
        case .gpu:     return $settings.showGPU
        case .memory:  return $settings.showMemory
        case .battery: return $settings.showBattery
        case .disk:    return $settings.showDisk
        case .network: return $settings.showNetwork
        case .sensors: return $settings.showSensors
        }
    }

    private func fanCurveRow(index: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc: label)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(settings.fanCurve[index].tempC))° → \(Int(settings.fanCurve[index].rpmPercent))%")
                    .font(.metric(10))
                    .foregroundColor(Theme.textSecondary)
            }
            HStack {
                Text("°C").font(.system(size: 9)).foregroundColor(Theme.textTertiary)
                Slider(value: curveTempBinding(index), in: 40...95, step: 1)
                    .tint(settings.accent)
            }
            HStack {
                Text("%").font(.system(size: 9)).foregroundColor(Theme.textTertiary)
                Slider(value: curveRPMBinding(index), in: 0...100, step: 5)
                    .tint(settings.accent)
            }
        }
    }

    private func curveTempBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { settings.fanCurve[i].tempC },
            set: { v in
                var c = settings.fanCurve
                guard c.indices.contains(i) else { return }
                c[i].tempC = v
                settings.fanCurve = c
            }
        )
    }

    private func curveRPMBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { settings.fanCurve[i].rpmPercent },
            set: { v in
                var c = settings.fanCurve
                guard c.indices.contains(i) else { return }
                c[i].rpmPercent = v
                settings.fanCurve = c
            }
        )
    }

    private var helperStatusLabel: String {
        switch fans.helperState {
        case .ready:
            if let v = fans.installedHelperVersion {
                return "Installed (v%d) ✓".locf(v)
            }
            return "Installed ✓".loc
        case .installing: return "Installing…".loc
        case .notInstalled: return "Not installed".loc
        case .declined: return "Authorization skipped".loc
        case .failed: return "Error".loc
        case .unknown: return "Checking…".loc
        }
    }

    private var helperStatusColor: Color {
        switch fans.helperState {
        case .ready: return Theme.ok
        case .installing: return Theme.info
        case .failed, .declined: return Theme.danger
        default: return Theme.textTertiary
        }
    }

    private func openLogFolder() {
        NSWorkspace.shared.open(DiagLog.logDirectoryURL)
    }

    private func exportDiagnostic() {
        guard let hub else { return }
        switch DiagnosticExporter.export(hub: hub) {
        case .success(let url):
            exportMessage = "Saved to %@".locf(url.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failure(.message(let err)):
            exportMessage = err
        }
    }
}

// MARK: - Reusable settings controls

struct SettingsSidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20)
                Text(loc: tab.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? accent.opacity(0.14) : Color.clear)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(accent)
                            .frame(width: 3)
                            .padding(.vertical, 7)
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

struct SettingsHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc: title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            if let subtitle {
                Text(loc: subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingGroup<Content: View>: View {
    let title: String?
    var compact = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 8) {
            if let title {
                Text(title.loc.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            content
                .padding(compact ? 10 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc: label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                if let detail {
                    Text(loc: detail)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 20)
            accessory
        }
        .frame(minHeight: 30)
        .padding(.vertical, 4)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(Theme.stroke)
    }
}

struct SettingsChoiceGroup<T: Hashable>: View {
    let label: String
    var detail: String? = nil
    let options: [(T, String)]
    @Binding var selection: T
    let accent: Color
    var columns: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc: label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                if let detail, !detail.isEmpty {
                    Text(loc: detail)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsPillSelector(
                options: options,
                selection: $selection,
                accent: accent,
                columns: columns
            )
        }
    }
}

struct SettingsPillSelector<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    let accent: Color
    var columns: Int = 0

    private var gridColumns: [GridItem] {
        let count = max(columns, 1)
        return Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: count)
    }

    var body: some View {
        Group {
            if columns > 1 {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 6) {
                    pillButtons
                }
            } else {
                HStack(spacing: 6) {
                    pillButtons
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.track)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var pillButtons: some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let isSelected = selection == option.0
            Button {
                selection = option.0
            } label: {
                Text(loc: option.1)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? accent : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

struct MenuBarMetricRow: View {
    let metric: MenuBarMetric
    @Binding var isOn: Bool
    let accent: Color
    var disabled: Bool = false
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(disabled ? Theme.textTertiary : metric.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc: metric.title)
                        .font(.system(size: 12.5))
                        .foregroundColor(disabled ? Theme.textTertiary : Theme.textPrimary)
                    if let note {
                        Text(loc: note)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(accent)
                    .disabled(disabled)
            }
        }
        .listRowBackground(Color.clear)
        .opacity(disabled ? 0.72 : 1)
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var accent: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(loc: label)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(accent)
        .padding(.vertical, 4)
    }
}

struct CostBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(loc: text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color.opacity(0.13))
            )
            .overlay(
                Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1)
            )
    }
}

struct OverviewCard: View {
    let title: String
    let value: String
    let detail: String
    let badge: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                CostBadge(text: badge, color: color)
            }
            Text(loc: title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
            Text(loc: value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(loc: detail)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}

struct OverviewActionRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppSettings.shared.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc: title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                    Text(loc: detail)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Text(loc: status)
                    .font(.metric(11))
                    .foregroundColor(Theme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PerformanceCostRow: View {
    let name: String
    let detail: String
    let background: String
    let visible: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc: name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(loc: detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(loc: "Background")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                Text(loc: background)
                    .font(.metric(11))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(width: 82, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 3) {
                Text(loc: "Visible")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                Text(loc: visible)
                    .font(.metric(11))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

struct MenuBarPreviewView: View {
    @ObservedObject var settings = AppSettings.shared
    var hub: MonitorHub?
    var expanded = false
    @State private var previewTick = 0

    var body: some View {
        let image = previewImage
        let actualWidth = ceil(image.size.width + 4)
        let isTooWide = actualWidth > AppSettings.menuBarRecommendedMaxWidth
        let previewWidth = expanded
            ? min(max(image.size.width + 24, 120), Theme.popoverWidth - 28)
            : min(max(image.size.width + 18, 88), 280)
        let imageScale = min(1, max((previewWidth - 18) / max(image.size.width, 1), 0.1))
        VStack(alignment: .leading, spacing: 7) {
            if !expanded {
                HStack(spacing: 12) {
                    Text(loc: "Preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    Spacer(minLength: 10)
                    previewChrome(image: image, previewWidth: previewWidth, imageScale: imageScale, isTooWide: isTooWide)
                    Text("\(Int(actualWidth)) px")
                        .font(.metric(10))
                        .foregroundColor(isTooWide ? Theme.danger : Theme.textTertiary)
                        .frame(width: 48, alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    previewChrome(image: image, previewWidth: previewWidth, imageScale: imageScale, isTooWide: isTooWide)
                    HStack {
                        Text(loc: "Width")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                        Text("\(Int(actualWidth)) px")
                            .font(.metric(10))
                            .foregroundColor(isTooWide ? Theme.danger : Theme.textSecondary)
                    }
                }
            }
            if settings.resolvedMenuBarColorMode == .adaptive {
                Label {
                    Text(loc: "Adaptive color uses the menu bar's automatic inverted color.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 10))
                        .foregroundColor(settings.accent)
                }
            }
            if isTooWide {
                Label {
                    Text("Menu bar preview is wider than %@ px. Reduce metrics, font size, or use Stacked/Minimal.".locf("\(Int(AppSettings.menuBarRecommendedMaxWidth))"))
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.danger)
                }
            }
            if settings.menuBattery && !(hub?.battery.isPresent ?? false) {
                Label {
                    Text(loc: "No battery detected on this Mac. Battery will not appear in the menu bar.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "battery.slash")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .id(previewTick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            previewTick &+= 1
        }
    }

    private var previewImage: NSImage {
        let memFraction: Double
        if let hub, hub.memory.total > 0 {
            memFraction = hub.memory.used / hub.memory.total
        } else {
            memFraction = 0.58
        }

        var showCPU = settings.menuCPU
        var showGPU = settings.menuGPU
        let showMem = settings.menuMemory
        let showBat = settings.menuBattery && (hub?.battery.isPresent ?? true)
        let showNet = settings.menuNetwork
        if !showCPU && !showGPU && !showMem && !showBat && !showNet {
            showCPU = true
            showGPU = true
        }

        let input = MenuBarImageRenderer.Input(
            cpu: hub?.cpu.totalUsage ?? 0.42,
            gpu: hub?.gpu.utilization ?? 0.18,
            mem: memFraction,
            battery: (hub?.battery.isPresent ?? true) ? (hub?.battery.percentage ?? 0.86) : nil,
            batteryCharging: hub?.battery.isCharging ?? false,
            down: hub?.network.downloadRate ?? 1_250_000,
            up: hub?.network.uploadRate ?? 280_000,
            showCPU: showCPU,
            showGPU: showGPU,
            showMem: showMem,
            showBattery: showBat,
            showNet: showNet,
            metricOrder: settings.orderedMenuBarMetrics,
            height: 22,
            layout: settings.resolvedMenuBarLayout,
            compact: settings.menuCompact,
            fontStyle: settings.resolvedMenuBarFontStyle,
            colorMode: settings.resolvedMenuBarColorMode,
            fontSize: CGFloat(settings.menuBarFontSize)
        )
        return MenuBarImageRenderer.render(input)
    }

    private func previewChrome(image: NSImage, previewWidth: CGFloat, imageScale: CGFloat, isTooWide: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isTooWide ? Theme.danger.opacity(0.75) : Theme.stroke, lineWidth: 1)
                )
            Image(nsImage: image)
                .interpolation(.high)
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(imageScale)
        }
        .frame(width: previewWidth, height: expanded ? 42 : 36)
        .frame(maxWidth: .infinity)
    }
}

struct PopoverPreviewView: View {
    @ObservedObject var hub: MonitorHub
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        PopoverRootView(hub: hub)
            .frame(width: Theme.popoverWidth)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

struct AlertRow: View {
    let label: String
    @Binding var enabled: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let accent: Color
    var disabled: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle(isOn: $enabled) {
                    Text(loc: label).font(.system(size: 12.5)).foregroundColor(Theme.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(accent)
                Spacer()
                Text(format(value))
                    .font(.metric(12))
                    .foregroundColor(enabled ? accent : Theme.textTertiary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            Slider(value: $value, in: range, step: step)
                .tint(accent)
                .disabled(!enabled || disabled)
                .opacity(enabled ? 1 : 0.4)
        }
    }
}

struct ModuleListRow: View {
    let module: Module
    @Binding var isOn: Bool
    let accent: Color
    var disabled: Bool = false
    var note: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(disabled ? Theme.textTertiary : accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.localizedTitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(disabled ? Theme.textTertiary : Theme.textPrimary)
                if let note {
                    Text(loc: note)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .disabled(disabled)
        }
        .listRowBackground(Color.clear)
        .opacity(disabled ? 0.72 : 1)
    }
}

// MARK: - Back-deployment helpers

extension View {
    @ViewBuilder
    func hiddenScrollContentBackground() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
