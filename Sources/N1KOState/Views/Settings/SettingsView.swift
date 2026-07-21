import AppKit
import Combine
import N1KOAgentCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var chartRange = ChartRangeStore.shared
    @ObservedObject var fans: FanControlService
    @ObservedObject private var navigation: SettingsNavigationModel
    @ObservedObject var hub: MonitorHub
    @ObservedObject private var agentModel: AgentSurfaceModel
    @ObservedObject private var agentIntegrations = AgentIntegrationController.shared
    @State private var tab: SettingsTab
    @State private var exportMessage: String?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var moduleFilter = ""
    @State private var settingsSearch = ""
    @State private var showingHelperUninstallConfirmation = false

    init(fans: FanControlService,
         hub: MonitorHub,
         initialTab: SettingsTab? = nil,
         navigation: SettingsNavigationModel = SettingsNavigationModel(),
         agentModel: AgentSurfaceModel? = nil,
         preferences: AppPreferences = .shared) {
        self.fans = fans
        self.hub = hub
        self.navigation = navigation
        self.settings = preferences.root
        self.agentModel = agentModel ?? AgentSurfaceModel()
        _tab = State(initialValue: initialTab ?? navigation.selectedTab)
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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    page
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 780, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: navigation.pendingControlID) { control in
                    guard let control else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(control, anchor: .top)
                        navigation.pendingControlID = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
        }
        .frame(minWidth: 900, idealWidth: 980, maxWidth: .infinity,
               minHeight: 600, idealHeight: 720, maxHeight: .infinity)
        .controlSize(.regular)
        .background(Theme.surfaceMaterial)
        .onChange(of: navigation.selectedTab) { selected in
            if tab != selected { tab = selected }
        }
        .onChange(of: tab) { selected in
            if navigation.selectedTab != selected { navigation.selectedTab = selected }
        }
        .id(settings.language)
        .id(settings.appTheme)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("N1KO ")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Text("STATE")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(settings.accent)
                }
                Text(loc: "Settings")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 7)
            .padding(.top, 12)

            TextField("Search settings".loc, text: $settingsSearch)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .keyboardShortcut("f", modifiers: .command)
                .padding(.horizontal, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if normalizedSearch.isEmpty {
                        ForEach(SettingsTab.grouped, id: \.group) { section in
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
                    } else if searchResults.isEmpty {
                        Text(loc: "No settings found")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc: "Controls")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.textTertiary)
                                .padding(.horizontal, 10)
                            ForEach(searchResults) { result in
                                Button {
                                    navigation.navigate(to: result)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(loc: result.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Theme.textPrimary)
                                        Text(loc: result.detail)
                                            .font(.system(size: 10))
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens the matching control.".loc)
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
        .frame(width: 224)
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
    }

    private var normalizedSearch: String {
        settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchIndex.search(normalizedSearch)
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
        case .agentCenter: agentCenterPage
        case .advanced: advancedPage
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Overview",
                           subtitle: "Menu bar, popover, sampling, and thermal safety at a glance.")

            SettingGroup(title: "Live Preview") {
                MenuBarPreviewView(hub: hub, expanded: true)
            }
            .id(SettingsControlID.overviewPreview)

            HStack(alignment: .top, spacing: 9) {
                OverviewCard(title: "Sampling",
                             value: resourceModeTitle,
                             detail: resourceModeDetail,
                             badge: resourceModeBadge,
                             color: resourceModeColor,
                             icon: "speedometer")
                OverviewCard(title: "Active Metrics",
                             value: "\(activeMenuMetricCount)",
                             detail: "Currently shown in the menu bar.",
                             badge: "\(activeMenuMetricCount)",
                             color: settings.accent,
                             icon: "menubar.rectangle")
                OverviewCard(title: "Popover Modules",
                             value: "\(activePopoverModuleCount)",
                             detail: "Enabled in the Quick Panel.",
                             badge: "\(activePopoverModuleCount)",
                             color: Theme.info,
                             icon: "rectangle.on.rectangle")
            }

            SettingGroup(title: "Quick Links", flush: true) {
                VStack(spacing: 0) {
                    OverviewActionRow(icon: "menubar.rectangle",
                                      title: "Menu bar display",
                                      detail: "",
                                      status: "%d items".locf(activeMenuMetricCount)) {
                        tab = .menuBar
                    }
                    SettingsDivider()
                    OverviewActionRow(icon: "rectangle.on.rectangle",
                                      title: "Popover modules",
                                      detail: "",
                                      status: "%d items".locf(activePopoverModuleCount)) {
                        tab = .popover
                    }
                }
            }
        }
    }

    private var batteryIsAvailable: Bool {
        hub.battery.isPresent
    }

    private var menuBarPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Menu Bar",
                           subtitle: "Choose the always-visible readout and keep it legible in every menu-bar state.")

            HStack(alignment: .top, spacing: 18) {
                SettingGroup(title: "Metrics",
                             subtitle: "Choose which metrics appear in the menu bar widget.",
                             flush: true) {
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
                .id(SettingsControlID.menuBarMetrics)

                VStack(alignment: .leading, spacing: 7) {
                    LivePreviewLabel()
                    MenuBarPreviewView(hub: hub, expanded: true)
                }
                .frame(width: Theme.popoverWidth)
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
            .id(SettingsControlID.menuBarAppearance)
        }
        .onAppear {
            if settings.menuBattery && !batteryIsAvailable {
                settings.menuBattery = false
            }
        }
    }

    private var popoverPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Popover",
                           subtitle: "Control the click-open panel separately from the always-on menu bar.")

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingGroup(title: "Quick Panel Layout") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(loc: "The Quick Panel uses a health summary and stable module rows. Open one row at a time for charts and controls.")
                                .font(Theme.TypeScale.body)
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            SettingsChoiceGroup(
                                label: "Chart Range",
                                options: HistoryStore.Range.allCases.map { ($0.rawValue, $0.rawValue.uppercased()) },
                                selection: $chartRange.range,
                                accent: settings.accent,
                                columns: 4
                            )
                        }
                    }
                    .id(SettingsControlID.quickPanelLayout)

                    SettingGroup(title: "Modules", flush: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            TextField("Search modules".loc, text: $moduleFilter)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal, 14)
                                .padding(.top, 7)
                                .padding(.bottom, 5)
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
                    .id(SettingsControlID.quickPanelModules)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text(loc: "Static preview")
                        .font(Theme.TypeScale.caption)
                        .foregroundColor(Theme.textSecondary)
                    QuickPanelPreviewView(
                        model: .make(
                            snapshot: hub.snapshot,
                            modules: settings.orderedModules.filter {
                                settings.isVisible($0) && ($0 != .battery || hub.snapshot.batteryIsPresent)
                            }
                        )
                    )
                    .frame(width: Theme.popoverWidth)
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
            .id(SettingsControlID.refreshProfile)

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
            .id(SettingsControlID.monitoringCost)
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
            .id(SettingsControlID.temperatureDisplay)
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

                        Button(action: { showingHelperUninstallConfirmation = true }) {
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
            .id(SettingsControlID.fanHelper)
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
                .id(SettingsControlID.fanCurve)
            } else if fans.isAvailable {
                Text(loc: "This device does not support manual fan control.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .onAppear { fans.refreshHelperStatus() }
        .alert("Uninstall N1KO-STATE Fan Helper?".loc,
               isPresented: $showingHelperUninstallConfirmation) {
            Button("Cancel".loc, role: .cancel) {}
            Button("Uninstall Helper".loc, role: .destructive) {
                fans.uninstallHelper()
            }
        } message: {
            Text("This removes the N1KO-STATE fan helper and restores system automatic fan control."
                .loc)
        }
    }

    private var alertsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Alerts",
                           subtitle: "Get a notification when a metric crosses a limit.")

            SettingGroup(title: nil) {
                ToggleRow(label: "Enable alerts", isOn: Binding(
                    get: { settings.alertsEnabled },
                    set: { enabled in
                        settings.alertsEnabled = enabled
                        if enabled { hub.alerts.requestAuthorization() }
                    }
                ), accent: settings.accent)
            }
            .id(SettingsControlID.alertMaster)

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
            .id(SettingsControlID.alertThresholds)
            .opacity(settings.alertsEnabled ? 1 : 0.45)
        }
    }

    private var agentCenterPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(
                title: "Agent Center",
                subtitle: "Follow supported coding-agent sessions through one N1KO-owned event, migration, and presentation path."
            )

            HStack(alignment: .top, spacing: 9) {
                OverviewCard(title: "Active Sessions",
                             value: "\(agentModel.projection.activeCount)",
                             detail: "Sessions currently working or waiting.",
                             badge: "\(agentModel.projection.activeCount)",
                             color: Theme.info,
                             icon: "terminal")
                OverviewCard(title: "Needs Attention",
                             value: "\(agentModel.projection.attentionCount)",
                             detail: "Approvals, questions, and failures.",
                             badge: "\(agentModel.projection.attentionCount)",
                             color: agentModel.projection.attentionCount > 0 ? Theme.warn : Theme.ok,
                             icon: "exclamationmark.bubble")
                OverviewCard(title: "Token Usage",
                             value: compactAgentUsage(agentModel.projection.usage.totalTokens),
                             detail: "Cumulative input and output tokens.",
                             badge: compactAgentUsage(agentModel.projection.usage.totalTokens),
                             color: settings.accent,
                             icon: "number")
            }

            SettingGroup(title: "Session Behavior") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ToggleRow(label: "Enable Agent session awareness",
                              isOn: $settings.agentBehaviorEnabled,
                              accent: settings.accent)
                    Text("Turning this off hides Agent surfaces immediately. Agent Core starts or stays disabled after the next launch so an in-flight authenticated response is never orphaned.".loc)
                        .font(Theme.TypeScale.secondary)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(SettingsControlID.agentBehavior)

            SettingGroup(title: "Agent Island") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ToggleRow(label: "Show Agent Island",
                              isOn: $settings.agentPresentationEnabled,
                              accent: settings.accent)
                    ToggleRow(label: "Allow deliberate top-edge reveal in fullscreen",
                              isOn: $settings.agentFullscreenRevealEnabled,
                              accent: settings.accent)
                    Text("The desktop Island never joins a native fullscreen Space. A separate hidden panel appears only after a top-edge dwell and closes on Escape, pointer exit, Space change, or sleep.".loc)
                        .font(Theme.TypeScale.secondary)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(SettingsControlID.agentPresentation)

            SettingGroup(title: "Island Feedback") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ToggleRow(label: "Animate provider mascots",
                              isOn: $settings.agentMascotAnimationsEnabled,
                              accent: settings.accent)
                    if settings.agentNotificationsTemporarilyMuted {
                        Button("Resume Agent notifications".loc) {
                            settings.agentNotificationMuteUntil = nil
                        }
                        .buttonStyle(.plain)
                        .font(Theme.TypeScale.secondary)
                        .foregroundColor(settings.accent)
                    }
                }
            }

            SettingsHeader(
                title: "Island Behavior & Display",
                subtitle: "The pinned behavior, compact presentation, floating mode, usage, and panel sizing controls."
            )
            IslandSettingsContent()
                .id(SettingsControlID.agentIslandSettings)

            SettingsHeader(
                title: "Sound & Theme Packs",
                subtitle: "Five event mappings, system sounds, the pinned 8-bit scheme, and OpenPeon / CESP packs."
            )
            SoundSettingsContent()
                .id(SettingsControlID.agentSounds)

            SettingsHeader(
                title: "Provider Mascots",
                subtitle: "The pinned per-client mascot mapping and live status preview."
            )
            MascotSettingsView()
                .frame(minHeight: 780)
                .id(SettingsControlID.agentMascots)

            SettingGroup(title: "Target Display") {
                SettingsCardRow(label: "Display") {
                    Picker("Display".loc, selection: $settings.agentTargetDisplayUUID) {
                        Text("Automatic".loc).tag(AppSettings.automaticDisplaySelection)
                        ForEach(agentModel.displayOptions) { display in
                            Text(display.isNotched
                                 ? "%@ — camera housing".locf(display.title)
                                 : display.title)
                                .tag(display.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .accessibilityLabel("Agent target display".loc)
                }
            }
            .id(SettingsControlID.agentTargetDisplay)

            SettingGroup(title: "Provider Integrations", flush: true) {
                VStack(spacing: 0) {
                    ForEach(Array(AgentIntegrationRegistry.profiles.enumerated()), id: \.element.id) {
                        index, profile in
                        if index > 0 { SettingsDivider() }
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: settings.agentSymbolicCompanionEnabled
                                  ? AgentSymbolicCompanionDescriptor(
                                      provider: profile.provider
                                  ).systemSymbolName
                                  : "terminal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(settings.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(Theme.TypeScale.bodyMedium)
                                    .foregroundColor(Theme.textPrimary)
                                Text(profile.managedHookAvailable
                                     ? profile.configurationRelativePath
                                     : "Runtime detection and focus only".loc)
                                    .font(Theme.TypeScale.caption)
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if profile.managedHookAvailable {
                                let installed = agentIntegrations.installedProfileIDs.contains(profile.id)
                                Text(installed ? "Installed".loc : "Not installed".loc)
                                    .font(Theme.TypeScale.caption)
                                    .foregroundColor(installed ? Theme.ok : Theme.textTertiary)
                                Button(installed ? "Remove".loc : "Install".loc) {
                                    if installed {
                                        agentIntegrations.removeWithConfirmation(profile: profile)
                                    } else {
                                        agentIntegrations.installWithConfirmation(profile: profile)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(agentIntegrations.isBusy)
                            } else {
                                Text("Runtime only".loc)
                                    .font(Theme.TypeScale.caption)
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                    }
                }
            }
            .id(SettingsControlID.agentIntegrations)

            SettingGroup(title: "Capabilities") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ToggleRow(label: "Enable terminal and IDE focus",
                              isOn: $settings.agentFocusEnabled,
                              accent: settings.accent)
                    ToggleRow(label: "Enable tmux pane focus",
                              isOn: $settings.agentTMUXEnabled,
                              accent: settings.accent)
                    ToggleRow(label: "Enable verified remote SSH plans",
                              isOn: $settings.agentRemoteSSHEnabled,
                              accent: settings.accent)
                    ToggleRow(label: "Show symbolic provider companions",
                              isOn: $settings.agentSymbolicCompanionEnabled,
                              accent: settings.accent)
                    Text("Capabilities are off by default. N1KO-STATE performs focus, tmux, or SSH work only after the matching option is enabled and the user invokes an action. No third-party mascot assets are bundled.".loc)
                        .font(Theme.TypeScale.secondary)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(SettingsControlID.agentCapabilities)

            if agentIntegrations.legacyDiscovery.hasImportableData {
                SettingGroup(title: "Legacy Agent Import") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Compatible provider selections, associations, and aggregate usage are available. Import is read-only and excludes credentials and transient window state.".loc)
                            .font(Theme.TypeScale.secondary)
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Review and Import".loc) {
                            agentIntegrations.importLegacyWithConfirmation()
                        }
                        .buttonStyle(.bordered)
                        .disabled(agentIntegrations.isBusy)
                    }
                }
                .id(SettingsControlID.agentLegacyImport)
            }

            if let message = agentIntegrations.operationMessage {
                Text(message)
                    .font(Theme.TypeScale.secondary)
                    .foregroundColor(Theme.textSecondary)
                    .accessibilityLabel(message)
            }

            SettingGroup(title: "Sessions", flush: true) {
                VStack(spacing: 0) {
                    if agentModel.projection.sessions.isEmpty {
                        Text("No Agent sessions yet.".loc)
                            .font(Theme.TypeScale.secondary)
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.m)
                    } else {
                        ForEach(Array(agentModel.projection.sessions.prefix(8).enumerated()), id: \.element.id) {
                            index, session in
                            if index > 0 { SettingsDivider() }
                            HStack(spacing: Theme.Spacing.s) {
                                Image(systemName: agentSettingsPhaseIcon(session.phase))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(agentSettingsPhaseColor(session.phase))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(Theme.TypeScale.bodyMedium)
                                        .foregroundColor(Theme.textPrimary)
                                        .lineLimit(1)
                                    Text("%@ · %@".locf(
                                        session.provider.displayName,
                                        agentSettingsPhaseTitle(session.phase)
                                    ))
                                    .font(Theme.TypeScale.caption)
                                    .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                                Text(compactAgentUsage(session.usage.totalTokens))
                                    .font(Theme.TypeScale.metric)
                                    .foregroundColor(Theme.textSecondary)
                                Button("Focus".loc) {
                                    agentIntegrations.focus(session: session)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!settings.agentFocusEnabled)
                            }
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.s)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .id(SettingsControlID.agentSessions)
        }
    }

    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Advanced",
                           subtitle: "Language, appearance, startup, diagnostics, and maintenance.")
            SettingGroup(title: "Basics", flush: true) {
                VStack(spacing: 0) {
                    SettingsCardRow(label: "Language") {
                        Picker("Language".loc, selection: $settings.language) {
                            ForEach(languages, id: \.code) { lang in
                                Text(lang.code == LocalizationManager.system ? "System".loc : lang.label)
                                    .tag(lang.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .id(SettingsControlID.language)
                    SettingsDivider()
                    SettingsCardRow(label: "Appearance") {
                        SettingsPillSelector(
                            options: [
                                ("system", "System"),
                                ("light", "Light"),
                                ("dark", "Dark")
                            ],
                            selection: $settings.appTheme,
                            accent: settings.accent,
                            inline: true
                        )
                    }
                    .id(SettingsControlID.appAppearance)
                    SettingsDivider()
                    SettingsCardRow(label: "Accent Color") {
                        HStack(spacing: 8) {
                            ForEach(AppSettings.accentPalette, id: \.self) { hex in
                                Button(action: { settings.accentHex = hex }) {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle().strokeBorder(Theme.textPrimary.opacity(0.85),
                                                                  lineWidth: settings.accentHex == hex ? 2 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Accent color %@".locf(String(format: "#%06X", hex)))
                                .accessibilityAddTraits(settings.accentHex == hex ? .isSelected : [])
                            }
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: settings.accentHex) },
                                set: { if let hex = $0.toHexInt() { settings.accentHex = hex } }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 22, height: 22)
                        }
                    }
                    .id(SettingsControlID.accentColor)
                    if LoginItem.isAvailable {
                        SettingsDivider()
                        SettingsCardRow(label: "Launch at login") {
                            Toggle("Launch at login".loc, isOn: Binding(get: { launchAtLogin },
                                                     set: { launchAtLogin = $0; LoginItem.set($0) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(settings.accent)
                        }
                        .id(SettingsControlID.launchAtLogin)
                    }
                }
            }

            SettingGroup(title: "Maintenance") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: "N1KO-STATE \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.18")")
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
                        .id(SettingsControlID.updates)
                        Button(action: openLogFolder) {
                            Text(loc: "Open Log Folder")
                        }
                        .buttonStyle(.bordered)
                        Button(action: exportDiagnostic) {
                            Text(loc: "Export Diagnostic Report")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accent)
                        .id(SettingsControlID.diagnostics)
                    }
                    if let exportMessage {
                        Text(exportMessage)
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Text(loc: "Diagnostic reports are created locally, redact secrets and home paths, and are never uploaded automatically. Review before sharing.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Bindings / derived state

    private var activeMenuMetricCount: Int {
        [settings.menuCPU, settings.menuGPU, settings.menuMemory, settings.menuNetwork, settings.menuBattery]
            .filter { $0 }.count
    }

    private var activePopoverModuleCount: Int {
        settings.orderedModules.filter { settings.isVisible($0) }.count
    }

    private func compactAgentUsage(_ value: Int) -> String {
        switch Double(value) {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }

    private func agentSettingsPhaseTitle(_ phase: AgentPhase) -> String {
        switch phase {
        case .starting: return "Starting".loc
        case .processing: return "Working".loc
        case .waitingForApproval: return "Waiting for approval".loc
        case .waitingForAnswer: return "Waiting for answer".loc
        case .completed: return "Completed".loc
        case .interrupted: return "Interrupted".loc
        case .failed: return "Failed".loc
        case .ended: return "Ended".loc
        case .archived: return "Archived".loc
        }
    }

    private func agentSettingsPhaseIcon(_ phase: AgentPhase) -> String {
        switch phase {
        case .starting: return "clock"
        case .processing: return "terminal"
        case .waitingForApproval: return "checkmark.shield"
        case .waitingForAnswer: return "questionmark.bubble"
        case .completed: return "checkmark.circle"
        case .interrupted: return "pause.circle"
        case .failed: return "exclamationmark.triangle"
        case .ended: return "stop.circle"
        case .archived: return "archivebox"
        }
    }

    private func agentSettingsPhaseColor(_ phase: AgentPhase) -> Color {
        switch phase {
        case .waitingForApproval, .waitingForAnswer: return Theme.warn
        case .completed: return Theme.ok
        case .failed: return Theme.danger
        case .starting, .processing: return Theme.info
        case .interrupted, .ended, .archived: return Theme.textTertiary
        }
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
                Text("°C").font(Theme.TypeScale.caption).foregroundColor(Theme.textTertiary)
                Slider(value: curveTempBinding(index), in: 40...95, step: 1)
                    .tint(settings.accent)
            }
            HStack {
                Text("%").font(Theme.TypeScale.caption).foregroundColor(Theme.textTertiary)
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
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? accent : Theme.textSecondary)
                    .frame(width: 16)
                Text(loc: tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
    }
}

struct LivePreviewLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.ok)
            Text(loc: "Live Preview")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
    }
}

struct SettingsCardRow<Accessory: View>: View {
    let label: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(loc: label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            Spacer(minLength: 16)
            accessory
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }
}

struct SettingsHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(loc: title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            if let subtitle {
                Text(loc: subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }
}

struct SettingGroup<Content: View>: View {
    let title: String?
    var subtitle: String? = nil
    var compact = false
    var flush = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.loc)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle.loc)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)
                .padding(.bottom, flush ? 0 : 2)
            }
            content
                .padding(flush ? EdgeInsets() : EdgeInsets(top: compact ? 8 : 10, leading: 15, bottom: 13, trailing: 15))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.settingsCardRadius, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.settingsCardRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
        )
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
    var inline: Bool = false

    private var gridColumns: [GridItem] {
        let count = max(columns, 1)
        return Array(repeating: GridItem(.flexible(), spacing: 2, alignment: .leading), count: count)
    }

    var body: some View {
        Group {
            if columns > 1 && !inline {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 2) {
                    pillButtons
                }
            } else {
                HStack(spacing: 2) {
                    pillButtons
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.track)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: inline ? nil : .infinity)
                    .padding(.horizontal, inline ? 8 : 10)
                    .padding(.vertical, inline ? 6 : 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Theme.card : Color.clear)
                            .shadow(color: isSelected ? Color.black.opacity(0.07) : .clear, radius: 1, y: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.1.loc)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            RoundedRectangle(cornerRadius: Theme.settingsCardRadius, style: .continuous).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.settingsCardRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
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
                    if !detail.isEmpty {
                        Text(loc: detail)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                Spacer()
                Text(loc: status)
                    .font(.metric(11))
                    .foregroundColor(Theme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
                    .font(Theme.TypeScale.caption.weight(.semibold))
                    .foregroundColor(Theme.textTertiary)
                Text(loc: background)
                    .font(.metric(11))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(width: 82, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 3) {
                Text(loc: "Visible")
                    .font(Theme.TypeScale.caption.weight(.semibold))
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
    @ObservedObject var hub: MonitorHub
    var expanded = false

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
            if settings.menuBattery && !hub.snapshot.batteryIsPresent {
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
    }

    private var previewImage: NSImage {
        let snapshot = hub.snapshot
        let memFraction = snapshot.memoryTotal > 0 ? snapshot.memoryFraction : 0.58

        var showCPU = settings.menuCPU
        var showGPU = settings.menuGPU
        let showMem = settings.menuMemory
        let showBat = settings.menuBattery && snapshot.batteryIsPresent
        let showNet = settings.menuNetwork
        if !showCPU && !showGPU && !showMem && !showBat && !showNet {
            showCPU = true
            showGPU = true
        }

        let input = MenuBarImageRenderer.Input(
            cpu: snapshot.generationID > 0 ? snapshot.cpuUsage : 0.42,
            gpu: snapshot.generationID > 0 ? snapshot.gpuUtilization : 0.18,
            mem: memFraction,
            battery: snapshot.batteryIsPresent ? snapshot.batteryPercentage : nil,
            batteryCharging: snapshot.batteryIsCharging,
            down: snapshot.generationID > 0 ? snapshot.networkDownloadRate : 1_250_000,
            up: snapshot.generationID > 0 ? snapshot.networkUploadRate : 280_000,
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
        return PerformanceDiagnostics.measure(.settingsPreviewRender) {
            MenuBarImageRenderer.render(input)
        }
    }

    private func previewChrome(image: NSImage, previewWidth: CGFloat, imageScale: CGFloat, isTooWide: Bool) -> some View {
        HStack {
            if expanded { Spacer(minLength: 0) }
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
            if !expanded { Spacer(minLength: 0) }
        }
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
                .accessibilityLabel("%@ threshold".locf(label.loc))
                .accessibilityValue(format(value))
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
            Toggle(module.localizedTitle, isOn: $isOn)
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
