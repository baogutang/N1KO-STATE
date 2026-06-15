import AppKit
import Combine
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case menuBar = "Menu Bar"
    case popover = "Popover"
    case modules = "Modules"
    case sensors = "Sensors"
    case alerts = "Alerts"
    case about = "About"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "macwindow"
        case .popover: return "rectangle.on.rectangle"
        case .modules: return "square.grid.2x2"
        case .sensors: return "thermometer"
        case .alerts: return "bell.badge"
        case .about: return "info.circle"
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

    init(fans: FanControlService, hub: MonitorHub? = nil, initialTab: SettingsTab? = nil) {
        self.fans = fans
        self.hub = hub
        _tab = State(initialValue: initialTab ?? .general)
    }

    /// Selectable UI languages. "System" follows the OS; the rest are shown in
    /// their own script so they're recognizable regardless of current language.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    page
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.surface)
        }
        .frame(width: 760, height: 540)
        .controlSize(.small)
        .background(Theme.surfaceMaterial)
        .id(settings.language)
        .id(settings.appTheme)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("N1KO-STATE")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(loc: "Settings")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ForEach(SettingsTab.allCases) { t in
                Button(action: { tab = t }) {
                    HStack(spacing: 9) {
                        Image(systemName: t.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18)
                        Text(loc: t.rawValue)
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(tab == t ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tab == t ? settings.accent.opacity(0.16) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 188)
        .background(.thinMaterial)
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch tab {
        case .general: generalPage
        case .menuBar: menuBarPage
        case .popover: popoverPage
        case .modules: modulesPage
        case .sensors: sensorsPage
        case .alerts: alertsPage
        case .about: aboutPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "General",
                           subtitle: "Set the app language, appearance, refresh rate, and startup behavior.")

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
                    SettingsRow(label: "Appearance") {
                        Picker("", selection: $settings.appTheme) {
                            Text(loc: "System").tag("system")
                            Text(loc: "Light").tag("light")
                            Text(loc: "Dark").tag("dark")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }
                    SettingsDivider()
                    SettingsRow(label: "Refresh Interval") {
                        Picker("", selection: $settings.refreshInterval) {
                            Text("0.5s").tag(0.5)
                            Text("1s").tag(1.0)
                            Text("2s").tag(2.0)
                            Text("3s").tag(3.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }
            }

            SettingGroup(title: "Accent Color") {
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
            }

            if LoginItem.isAvailable {
                SettingGroup(title: "Startup") {
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
    }

    private var menuBarPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Menu Bar", subtitle: "Choose what appears in the menu bar and preview its real width.")
            SettingGroup(title: nil) {
                MenuBarPreviewView(hub: hub)
            }
            SettingGroup(title: "Metrics") {
                List {
                    ForEach(settings.orderedMenuBarMetrics) { m in
                        HStack(spacing: 10) {
                            Text(loc: m.title)
                                .font(.system(size: 12.5))
                            Spacer()
                            Toggle("", isOn: menuBarBinding(m))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(settings.accent)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, dest in
                        var order = settings.orderedMenuBarMetrics.map(\.rawValue)
                        order.move(fromOffsets: source, toOffset: dest)
                        settings.menuBarOrder = order
                    }
                }
                .listStyle(.plain)
                .hiddenScrollContentBackground()
                .frame(minHeight: 180)
            }
            SettingGroup(title: "Layout") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(label: "Layout") {
                        Picker("", selection: $settings.menuBarLayout) {
                            ForEach(MenuBarLayout.allCases) { layout in
                                Text(loc: layout.title).tag(layout.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }
                    SettingsDivider()
                    SettingsRow(label: "Font Style") {
                        Picker("", selection: $settings.menuBarFontStyle) {
                            ForEach(MenuBarFontStyle.allCases) { style in
                                Text(loc: style.title).tag(style.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    SettingsDivider()
                    SettingsRow(label: "Font Size",
                                detail: "Keep the preview within the recommended width.") {
                        HStack(spacing: 10) {
                            Slider(value: $settings.menuBarFontSize,
                                   in: AppSettings.menuBarFontSizeRange,
                                   step: 0.5)
                                .frame(width: 150)
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
    }

    private func resetMenuBarDefaults() {
        settings.menuCPU = true
        settings.menuGPU = true
        settings.menuMemory = false
        settings.menuNetwork = false
        settings.menuBattery = false
        settings.menuBarLayout = MenuBarLayout.standard.rawValue
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

    private var popoverPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Popover",
                           subtitle: "Tune the click-open monitoring panel without changing the menu-bar readout.")
            SettingGroup(title: "Display") {
                VStack(spacing: 0) {
                    SettingsRow(label: "Popover Style") {
                        Picker("", selection: $settings.popoverStyle) {
                            Text(loc: "Cards").tag("cards")
                            Text(loc: "Gauges").tag("gauges")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    SettingsDivider()
                    SettingsRow(label: "Chart Range") {
                        Picker("", selection: $chartRange.range) {
                            ForEach(HistoryStore.Range.allCases) { range in
                                Text(range.rawValue.uppercased()).tag(range.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                }
            }
            SettingGroup(title: "Behavior") {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(loc: "The popover opens only when you click the menu-bar item.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    } icon: {
                        Image(systemName: "cursorarrow.click")
                            .foregroundColor(settings.accent)
                    }
                    Label {
                        Text(loc: "Clicking outside the panel closes it automatically.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    } icon: {
                        Image(systemName: "rectangle.and.hand.point.up.left")
                            .foregroundColor(settings.accent)
                    }
                }
            }
        }
    }

    private var modulesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Modules",
                           subtitle: "Drag rows to reorder, and toggle each card on or off.")
            TextField("Search modules".loc, text: $moduleFilter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            List {
                ForEach(filteredModules) { m in
                    ModuleListRow(module: m, isOn: visibilityBinding(m), accent: settings.accent)
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
            .frame(minHeight: 260)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
            )
        }
    }

    private var filteredModules: [Module] {
        let modules = settings.orderedModules
        let query = moduleFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return modules }
        return modules.filter { $0.localizedTitle.lowercased().contains(query) || $0.rawValue.contains(query) }
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

    private var sensorsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Sensors")
            SettingGroup(title: "Display") {
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

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeader(title: "About")
            Text(verbatim: "N1KO-STATE \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.5")")
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
            Spacer()
        }
    }
}

// MARK: - Reusable settings controls

struct SettingsHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc: title).font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            if let subtitle {
                Text(loc: subtitle).font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

struct SettingGroup<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.loc.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
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
                    .font(.system(size: 12.5))
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
        Divider()
            .overlay(Theme.stroke)
            .padding(.leading, 0)
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var accent: Color
    var body: some View {
        Toggle(isOn: $isOn) {
            Text(loc: label).font(.system(size: 12.5)).foregroundColor(Theme.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(accent)
        .padding(.vertical, 4)
    }
}

struct MenuBarPreviewView: View {
    @ObservedObject var settings = AppSettings.shared
    var hub: MonitorHub?
    @State private var previewTick = 0

    var body: some View {
        let image = previewImage
        let actualWidth = ceil(image.size.width + 4)
        let isTooWide = actualWidth > AppSettings.menuBarRecommendedMaxWidth
        let previewWidth = min(max(image.size.width + 18, 88), 260)
        let imageScale = min(1, max((previewWidth - 18) / max(image.size.width, 1), 0.1))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(loc: "Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer(minLength: 10)
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isTooWide ? Theme.danger.opacity(0.75) : Theme.stroke, lineWidth: 1)
                        )
                    Image(nsImage: image)
                        .interpolation(.high)
                        .frame(width: image.size.width, height: image.size.height)
                        .scaleEffect(imageScale)
                }
                .frame(width: previewWidth, height: 34)
                Text("\(Int(actualWidth)) px")
                    .font(.metric(10))
                    .foregroundColor(isTooWide ? Theme.danger : Theme.textTertiary)
                    .frame(width: 48, alignment: .trailing)
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
        let showBat = settings.menuBattery
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
            fontSize: CGFloat(settings.menuBarFontSize)
        )
        return MenuBarImageRenderer.render(input)
    }
}

/// A single alert rule: an on/off toggle plus a threshold slider with a live
/// value badge. The slider disables when the rule (or the global switch) is off.
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

/// Module row inside the reorderable List.
struct ModuleListRow: View {
    let module: Module
    @Binding var isOn: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 18)
            Text(module.localizedTitle)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
        }
        .listRowBackground(Color.clear)
    }
}

struct SegmentChip: View {
    let label: String
    let selected: Bool
    let accent: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.metric(12))
                .foregroundColor(selected ? .white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? accent : Theme.track)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Back-deployment helpers

extension View {
    /// `.scrollContentBackground(.hidden)` is macOS 13+. On macOS 12 the List's
    /// background is left as-is (the rounded card behind it still shows through
    /// the plain list style), so we simply skip the modifier.
    @ViewBuilder
    func hiddenScrollContentBackground() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
