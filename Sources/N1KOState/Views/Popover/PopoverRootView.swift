import SwiftUI
import AppKit

/// Reports the intrinsic height of the popover's card stack.
private struct PopoverHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The dropdown panel shown from the menu-bar item.
struct PopoverRootView: View {
    @ObservedObject var hub: MonitorHub
    @ObservedObject var settings = AppSettings.shared
    @State private var contentHeight: CGFloat = 0

    /// Keep the panel compact (typical menu-bar popover height); scroll beyond
    /// that, and shrink further on small screens so it never overruns.
    private var maxBodyHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(320, min(560, screen - 140))
    }

    private var visibleModules: [Module] {
        settings.orderedModules.filter { module in
            guard settings.isVisible(module) else { return false }
            if module == .battery { return hub.battery.isPresent }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if visibleModules.isEmpty {
                    emptyState
                } else if settings.popoverStyle == "gauges" {
                    ScrollView(.vertical, showsIndicators: true) {
                        GaugeGridView(hub: hub)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: PopoverHeightKey.self, value: g.size.height)
                            })
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 10) {
                            ForEach(visibleModules) { module in
                                card(for: module)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, Theme.padding)
                        .padding(.vertical, Theme.padding)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: PopoverHeightKey.self, value: g.size.height)
                        })
                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: settings.popoverStyle)
            .frame(height: min(max(contentHeight, 80), maxBodyHeight))
            .onPreferenceChange(PopoverHeightKey.self) { contentHeight = $0 }
        }
        .frame(width: Theme.popoverWidth)
        .background(Theme.popoverSurface)
        .id(settings.language)
        .id(settings.appTheme)
    }

    @ViewBuilder
    private func card(for module: Module) -> some View {
        switch module {
        case .cpu:     CPUCard(cpu: hub.cpu, memory: hub.memory, processes: hub.processes)
        case .gpu:     GPUCard(gpu: hub.gpu)
        case .memory:  MemoryCard(memory: hub.memory, processes: hub.processes)
        case .battery:
            if hub.battery.isPresent { BatteryCard(battery: hub.battery) }
        case .disk:    DiskCard(disk: hub.disk)
        case .network: NetworkCard(network: hub.network)
        case .sensors: SensorCard(sensors: hub.sensors, fans: hub.fans)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
            Text(loc: "No modules enabled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(loc: "Open Settings to choose what appears in the popover.")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: { SettingsWindowController.shared.show(fans: hub.fans, hub: hub, tab: .popover) }) {
                Text(loc: "Open Settings")
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 28)
        .background(GeometryReader { g in
            Color.clear.preference(key: PopoverHeightKey.self, value: g.size.height)
        })
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("N1KO")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text("STATE")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(settings.accent)
                Spacer(minLength: 4)
                headerIconButton(
                    systemName: "gearshape",
                    help: "Settings".loc,
                    label: "Settings".loc,
                    hint: "Opens N1KO-STATE settings.".loc
                ) {
                    SettingsWindowController.shared.show(fans: hub.fans, hub: hub)
                }

                headerIconButton(
                    systemName: "power",
                    help: "Quit N1KO-STATE".loc,
                    label: "Quit N1KO-STATE".loc,
                    hint: "Closes the app and restores automatic fan control.".loc
                ) {
                    NSApp.terminate(nil)
                }
            }

            if settings.popoverStyle == "gauges" {
                DashboardHeaderSummary(hub: hub)
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, settings.popoverStyle == "gauges" ? 10 : 11)
        .background(
            Rectangle().fill(Theme.popoverHeader).overlay(
                Rectangle().fill(Theme.stroke).frame(height: 1),
                alignment: .bottom
            )
        )
    }

    /// Icon-only control with a fixed 28×28 hit target — header background is not clickable.
    private func headerIconButton(
        systemName: String,
        help: String,
        label: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}
