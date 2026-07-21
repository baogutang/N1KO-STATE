import AppKit
import SwiftUI

/// The dropdown panel shown from the menu-bar item. Its host persists across
/// closes; the first frame has deterministic geometry and no entrance cascade.
struct PopoverRootView: View {
    @ObservedObject var hub: MonitorHub
    @ObservedObject var settings = AppSettings.shared
    var onOpenSettings: ((SettingsTab?) -> Void)?
    var onQuit: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var disclosure = QuickPanelDisclosureState()

    private var maximumBodyHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(320, min(QuickPanelLayoutMetrics.expandedBodyHeight, screen - 140))
    }

    private var bodyHeight: CGFloat {
        if disclosure.expandedModule != nil { return maximumBodyHeight }
        return QuickPanelLayoutMetrics.collapsedBodyHeight(
            moduleCount: visibleModules.count,
            maximum: maximumBodyHeight
        )
    }

    private var visibleModules: [Module] {
        settings.orderedModules.filter { module in
            guard settings.isVisible(module) else { return false }
            return module != .battery || hub.snapshot.batteryIsPresent
        }
    }

    var body: some View {
        PerformanceDiagnostics.event(.quickPanelUpdate)
        return VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: Theme.Spacing.xs) {
                    QuickPanelHealthSummary(
                        items: QuickPanelProjectionFactory.health(from: hub.snapshot),
                        differentiateWithoutColor: differentiateWithoutColor
                    )

                    if visibleModules.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: QuickPanelLayoutMetrics.rowSpacing) {
                            ForEach(visibleModules) { module in
                                moduleSection(module)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .frame(height: bodyHeight)
        }
        .frame(width: Theme.popoverWidth)
        .background(Theme.popoverSurface)
        .id(settings.language)
        .id(settings.appTheme)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                Text("N1KO ")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text("STATE")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(settings.accent)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Menu {
                Button("Settings".loc) { onOpenSettings?(nil) }
                    .keyboardShortcut(",", modifiers: .command)
                Button("About N1KO-STATE".loc) { onOpenSettings?(.advanced) }
                Divider()
                Button("Quit N1KO-STATE".loc) { onQuit?() }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: Theme.HitTarget.icon, height: Theme.HitTarget.icon)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Quick Panel menu".loc)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Rectangle().fill(Theme.popoverHeader).overlay(
                Rectangle().fill(Theme.stroke).frame(height: 1),
                alignment: .bottom
            )
        )
    }

    @ViewBuilder
    private func moduleSection(_ module: Module) -> some View {
        let projection = QuickPanelProjectionFactory.module(module, hub: hub)
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                withAnimation(Theme.Motion.disclosureAnimation(reduceMotion: reduceMotion)) {
                    disclosure.toggle(module)
                }
            } label: {
                QuickPanelModuleRow(
                    projection: projection,
                    isExpanded: disclosure.expandedModule == module
                )
            }
            .buttonStyle(N1KOButtonStyle())
            .accessibilityHint(disclosure.expandedModule == module
                ? "Collapses module details.".loc
                : "Expands module details.".loc)

            if disclosure.expandedModule == module {
                detailCard(for: module)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func detailCard(for module: Module) -> some View {
        let snapshot = hub.snapshot
        switch module {
        case .cpu: CPUCard(cpu: hub.cpu, memory: hub.memory, processes: hub.processes, snapshot: snapshot)
        case .gpu: GPUCard(gpu: hub.gpu, snapshot: snapshot)
        case .memory: MemoryCard(memory: hub.memory, processes: hub.processes, snapshot: snapshot)
        case .battery:
            if snapshot.batteryIsPresent { BatteryCard(battery: hub.battery, snapshot: snapshot) }
        case .disk: DiskCard(disk: hub.disk, snapshot: snapshot)
        case .network: NetworkCard(network: hub.network, snapshot: snapshot)
        case .sensors: SensorCard(sensors: hub.sensors, fans: hub.fans, snapshot: snapshot)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text(loc: "No modules enabled")
                .font(Theme.TypeScale.section)
                .foregroundColor(Theme.textPrimary)
            Text(loc: "Open Settings to choose what appears in the Quick Panel.")
                .font(Theme.TypeScale.secondary)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Open Settings".loc) { onOpenSettings?(.popover) }
                .buttonStyle(.borderedProminent)
                .tint(settings.accent)
                .disabled(onOpenSettings == nil)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .accessibilityElement(children: .combine)
    }
}

private struct QuickPanelHealthSummary: View {
    let items: [QuickPanelHealthItem]
    let differentiateWithoutColor: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: item.severity.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(item.severity.color)
                        Text(loc: item.label)
                            .font(Theme.TypeScale.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    Text(item.value)
                        .font(Theme.TypeScale.metric)
                        .foregroundColor(Theme.textPrimary)
                    if differentiateWithoutColor || item.severity != .normal {
                        Text(loc: item.severity.title)
                            .font(Theme.TypeScale.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("%@, %@, %@".locf(item.label.loc, item.value, item.severity.title.loc))
            }
        }
        .frame(minHeight: QuickPanelLayoutMetrics.healthHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous)
                .fill(Theme.popoverCard)
        )
    }
}

private struct QuickPanelModuleRow: View {
    let projection: QuickPanelModuleProjection
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: projection.module.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(projection.accent)
                .frame(width: Theme.HitTarget.icon, height: Theme.HitTarget.icon)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(projection.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(projection.module.localizedTitle)
                    .font(Theme.TypeScale.bodyMedium)
                    .foregroundColor(Theme.textPrimary)
                Text(projection.detail)
                    .font(Theme.TypeScale.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.xxs)

            Sparkline(values: projection.trend,
                      maxValue: projection.trendMaximum,
                      color: projection.accent)
                .frame(width: 48, height: 20)
                .accessibilityHidden(true)

            Text(projection.value)
                .font(Theme.TypeScale.metric)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 58, alignment: .trailing)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 12)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: QuickPanelLayoutMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isExpanded ? Theme.popoverCard : Theme.popoverCard.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Theme.increaseContrast ? Theme.stroke : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("%@, %@, %@, %@".locf(
            projection.module.localizedTitle,
            projection.value,
            projection.detail,
            projection.accessibilityTrendSummary
        ))
        .accessibilityValue(isExpanded ? "Expanded".loc : "Collapsed".loc)
    }
}

struct QuickPanelPreviewView: View {
    let model: QuickPanelPreviewModel

    var body: some View {
        PerformanceDiagnostics.event(.settingsPreviewRender)
        return VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(model.health) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc: item.label)
                            .font(Theme.TypeScale.caption)
                            .foregroundColor(Theme.textSecondary)
                        Text(item.value)
                            .font(Theme.TypeScale.metric)
                            .foregroundColor(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(model.modules.prefix(5)) { item in
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: item.module.icon)
                        .foregroundColor(Theme.accent)
                        .frame(width: Theme.HitTarget.icon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.module.localizedTitle).font(Theme.TypeScale.bodyMedium)
                        Text(item.detail).font(Theme.TypeScale.caption).foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Text(item.value).font(Theme.TypeScale.metric)
                }
                .frame(height: 40)
            }
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous)
                .fill(Theme.popoverSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick Panel preview".loc)
    }
}
