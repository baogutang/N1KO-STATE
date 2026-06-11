import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case menuBar = "Menu Bar"
    case modules = "Modules"
    case sensors = "Sensors"
    case alerts = "Alerts"
    case about = "About"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "macwindow"
        case .modules: return "square.grid.2x2"
        case .sensors: return "thermometer"
        case .alerts: return "bell.badge"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var fans: FanControlService
    var hub: MonitorHub?
    @State private var tab: SettingsTab
    @State private var exportMessage: String?
    @State private var launchAtLogin = LoginItem.isEnabled

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
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.ultraThinMaterial)
        }
        .frame(width: 640, height: 460)
        .background(.ultraThinMaterial)
        .id(settings.language)
        .id(settings.appTheme)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text("N1KO").font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text("STATE").font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(settings.accent)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
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
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == t ? settings.accent.opacity(0.18) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 176)
        .background(.thinMaterial)
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch tab {
        case .general: generalPage
        case .menuBar: menuBarPage
        case .modules: modulesPage
        case .sensors: sensorsPage
        case .alerts: alertsPage
        case .about: aboutPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "General")

            SettingGroup(title: "Language") {
                HStack(spacing: 8) {
                    ForEach(languages, id: \.code) { lang in
                        SegmentChip(label: lang.code == LocalizationManager.system ? "System".loc : lang.label,
                                    selected: settings.language == lang.code,
                                    accent: settings.accent) {
                            settings.language = lang.code
                        }
                    }
                }
            }

            SettingGroup(title: "Appearance") {
                HStack(spacing: 8) {
                    SegmentChip(label: "System".loc, selected: settings.appTheme == "system",
                                accent: settings.accent) { settings.appTheme = "system" }
                    SegmentChip(label: "Light".loc, selected: settings.appTheme == "light",
                                accent: settings.accent) { settings.appTheme = "light" }
                    SegmentChip(label: "Dark".loc, selected: settings.appTheme == "dark",
                                accent: settings.accent) { settings.appTheme = "dark" }
                }
            }

            SettingGroup(title: "Popover Style") {
                HStack(spacing: 8) {
                    SegmentChip(label: "Cards".loc, selected: settings.popoverStyle == "cards",
                                accent: settings.accent) { settings.popoverStyle = "cards" }
                    SegmentChip(label: "Gauges".loc, selected: settings.popoverStyle == "gauges",
                                accent: settings.accent) { settings.popoverStyle = "gauges" }
                }
            }

            SettingGroup(title: "Refresh Interval") {
                HStack(spacing: 8) {
                    ForEach([0.5, 1.0, 2.0, 3.0], id: \.self) { v in
                        SegmentChip(label: v < 1 ? "0.5s" : "\(Int(v))s",
                                    selected: abs(settings.refreshInterval - v) < 0.01,
                                    accent: settings.accent) {
                            settings.refreshInterval = v
                        }
                    }
                }
            }

            SettingGroup(title: "Accent Color") {
                HStack(spacing: 10) {
                    ForEach(AppSettings.accentPalette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().strokeBorder(Color.white,
                                                      lineWidth: settings.accentHex == hex ? 2.5 : 0)
                            )
                            .onTapGesture { settings.accentHex = hex }
                    }
                    Divider().frame(height: 22).overlay(Theme.stroke)
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
                SettingGroup(title: "Startup") {
                    ToggleRow(label: "Launch at login",
                              isOn: Binding(get: { launchAtLogin },
                                            set: { launchAtLogin = $0; LoginItem.set($0) }),
                              accent: settings.accent)
                }
            }
        }
    }

    private var menuBarPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Menu Bar", subtitle: "Choose which metrics appear in the menu bar widget.")
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
                ToggleRow(label: "Compact (combine into one readout)",
                          isOn: $settings.menuCompact, accent: settings.accent)
            }
        }
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

    private var modulesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Modules",
                           subtitle: "Drag rows to reorder, and toggle each card on or off.")
            List {
                ForEach(settings.orderedModules) { m in
                    ModuleListRow(module: m, isOn: visibilityBinding(m), accent: settings.accent)
                }
                .onMove { source, destination in
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
                    Text(loc: "Use Auto/Manual in the Sensors card. Adjust the slider to set a target RPM, then tap Apply to confirm. Quitting the app restores automatic control.")
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
            Text(verbatim: "N1KO-STATE \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.2")")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(loc: "A modern macOS system monitor.")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.textSecondary)
            Text(loc: "Includes SMCKit (MIT, © 2014–2017 beltex).")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
            HStack(spacing: 8) {
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
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
