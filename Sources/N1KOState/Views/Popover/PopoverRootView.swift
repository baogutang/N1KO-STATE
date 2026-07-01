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

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if settings.popoverStyle == "gauges" {
                    ScrollView(.vertical, showsIndicators: true) {
                        GaugeGridView(hub: hub)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: PopoverHeightKey.self, value: g.size.height)
                            })
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 10) {
                            ForEach(settings.orderedModules) { module in
                                if settings.isVisible(module) {
                                    card(for: module)
                                        .transition(.opacity)
                                }
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

    private var header: some View {
        HStack(spacing: 8) {
            Text("N1KO")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.textPrimary)
            Text("STATE")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(settings.accent)
            if settings.popoverStyle == "gauges" {
                DashboardHeaderSummary(hub: hub)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 4)
            Button(action: { SettingsWindowController.shared.show(fans: hub.fans, hub: hub) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Settings".loc)

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Quit N1KO-STATE".loc)
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 11)
        .background(
            Rectangle().fill(Theme.popoverHeader).overlay(
                Rectangle().fill(Theme.stroke).frame(height: 1),
                alignment: .bottom
            )
        )
    }
}
