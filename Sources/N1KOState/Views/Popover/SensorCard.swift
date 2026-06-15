import SwiftUI

struct SensorCard: View {
    @ObservedObject var sensors: SensorMonitor
    @ObservedObject var fans: FanController
    @ObservedObject var settings = AppSettings.shared

    /// Detailed view lists every sensor; otherwise the grouped buckets.
    private var temps: [TemperatureReading] {
        let source = settings.sensorsDetailed ? sensors.detailedTemperatures : sensors.temperatures
        return Array(source.prefix(settings.sensorsDetailed ? 14 : 6))
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: "thermometer",
                           title: "Sensors",
                           accent: Theme.warn,
                           trailing: sensors.peakCelsius.map { Formatters.temperature($0) })

                if !sensors.isAvailable {
                    Text(loc: "Sensors unavailable")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                } else if temps.isEmpty && fans.fans.isEmpty {
                    Text(loc: "No temperature sensors available.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if !temps.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(temps, id: \.id) { t in
                                HStack(spacing: 8) {
                                    HStack(spacing: 3) {
                                        Text(loc: t.label)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(1)
                                        if let o = t.ordinal {
                                            Text("\(o)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Theme.textTertiary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Text(Formatters.temperature(t.celsius))
                                        .font(.metric(11))
                                        .foregroundColor(Theme.semantic(for: min(t.celsius / 100, 1)))
                                        .help(sensorHelp(for: t))
                                }
                            }
                        }
                    }
                    if !fans.supportsControl && fans.isAvailable {
                        Text(loc: "This device does not support manual fan control.")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textTertiary)
                    } else if fans.fans.isEmpty && fans.isAvailable {
                        Text(loc: "No fan sensors on this device.")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textTertiary)
                    }
                    if !fans.fans.isEmpty {
                        if !temps.isEmpty { Divider().overlay(Theme.stroke) }
                        SectionLabel(text: "Fans")
                        if fans.supportsControl && fans.helperState != .ready {
                            FanHelperBanner(controller: fans)
                        }
                        if fans.usesGlobalFanModeSwitch && fans.fans.count > 1 {
                            Text(loc: "This Mac exposes a shared fan-control switch; only one fan can be forced manually at a time.")
                                .font(.system(size: 9.5))
                                .foregroundColor(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 11) {
                            ForEach(fans.fans, id: \.id) { fan in
                                FanRow(fan: fan, controller: fans)
                            }
                        }
                        if let err = fans.lastError {
                            Text(err)
                                .font(.system(size: 9.5))
                                .foregroundColor(Theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func sensorHelp(for t: TemperatureReading) -> String {
        "Temperature at %@.".locf(Formatters.temperature(t.celsius))
    }
}

private struct FanHelperBanner: View {
    @ObservedObject var controller: FanController

    private var retryLabel: String {
        if case .failed = controller.helperState { return "Retry" }
        return "Authorize"
    }

    var body: some View {
        HStack(spacing: 8) {
            switch controller.helperState {
            case .declined:
                Text(loc: "Fan control needs authorization.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
            case .failed(let msg):
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.danger)
                    .lineLimit(2)
            default:
                Text(loc: "Fan control needs authorization.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Button(action: { controller.warmAuthorization() }) {
                Text(loc: retryLabel)
            }
            .font(.system(size: 10, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(controller.helperState == .installing)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.track))
    }
}

private enum FanControlMode {
    case auto, manual
}

/// One fan row: Auto/Manual picker and live RPM slider.
private struct FanRow: View {
    let fan: FanInfo
    @ObservedObject var controller: FanController

    @State private var userMode: FanControlMode?
    @State private var target: Double = 0
    @State private var didInit = false

    private var canControl: Bool {
        controller.supportsControl && fan.maxRPM > fan.minRPM
    }
    private var isApplied: Bool { controller.appliedFanIDs.contains(fan.id) }
    private var isCurveActive: Bool { controller.mode == .curve }
    private var isPending: Bool { controller.pendingFanIDs.contains(fan.id) }
    private var helperFailed: Bool {
        if case .failed = controller.helperState { return true }
        return false
    }

    private var effectiveMode: FanControlMode {
        if let um = userMode { return um }
        if controller.mode == .manual && (controller.isManual(fan.id) || fan.forced) { return .manual }
        return .auto
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "fanblades")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.info)
                Text(fan.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("\(fan.rpm) RPM")
                    .font(.metric(11))
                    .foregroundColor(Theme.textPrimary)
            }

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(effectiveMode == .manual ? Theme.accent : Theme.semantic(for: fan.fraction))
                        .frame(width: max(3, g.size.width * CGFloat(fan.fraction)))
                        .animation(.easeOut(duration: 0.35), value: fan.fraction)
                }
            }
            .frame(height: 4)

            if canControl {
                if helperFailed {
                    HStack(spacing: 6) {
                        Text(controller.lastError ?? "Fan helper could not start. Tap Retry or reinstall.".loc)
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.danger)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Button(action: { controller.warmAuthorization() }) {
                            Text(loc: "Retry")
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(controller.helperState == .installing)
                    }
                }

                if isPending {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(loc: "Taking over fan control…")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Theme.info)
                    }
                }

                if isCurveActive, let pct = controller.curvePercent(for: fan) {
                    Text("Curve active · target %@".locf(Formatters.percent(pct)))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Theme.info)
                }

                Picker("", selection: Binding(
                    get: { effectiveMode },
                    set: { newMode in
                        userMode = newMode
                        if newMode == .auto {
                            controller.disableManual(fanId: fan.id)
                        } else {
                            controller.enableManual(fanId: fan.id, rpm: Int(target))
                        }
                    }
                )) {
                    Text(loc: "Auto").tag(FanControlMode.auto)
                    Text(loc: "Manual").tag(FanControlMode.manual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(isCurveActive || isPending || controller.helperState == .installing)

                if effectiveMode == .manual || isCurveActive {
                    HStack(spacing: 6) {
                        Text(loc: "Target")
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.textTertiary)
                        Text("\(Int(target)) RPM")
                            .font(.metric(10))
                            .foregroundColor(Theme.accent)
                        Spacer()
                        if isApplied {
                            Text(loc: "Active")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.ok)
                        }
                    }
                    Slider(value: $target,
                           in: Double(fan.minRPM)...Double(fan.maxRPM),
                           step: 50)
                        .tint(Theme.accent)
                        .onChange(of: target) { v in
                            if isCurveActive {
                                userMode = .manual
                                controller.enableManual(fanId: fan.id, rpm: Int(v))
                            } else {
                                controller.updateManualRPM(fanId: fan.id, rpm: Int(v))
                            }
                        }
                    HStack {
                        Text("\(fan.minRPM)").font(.system(size: 8.5)).foregroundColor(Theme.textTertiary)
                        Spacer()
                        Text("\(fan.maxRPM)").font(.system(size: 8.5)).foregroundColor(Theme.textTertiary)
                    }
                } else {
                    Text(loc: "System automatic fan control")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .onAppear { initTarget() }
        .onChange(of: fan.forced) { forced in
            // The SMC FS! value is the source of truth: once the hardware leaves
            // forced mode (e.g. reconciled after wake, or reset by the daemon),
            // clear any local override so the row follows reality instead of
            // staying stuck on "Manual".
            if !forced { userMode = nil }
        }
        .onReceive(controller.$manualFanIDs) { ids in
            if controller.mode == .auto || (controller.usesGlobalFanModeSwitch && !ids.contains(fan.id)) {
                userMode = nil
            }
        }
    }

    private func initTarget() {
        guard !didInit else { return }
        didInit = true
        let start = controller.manualTargets[fan.id]
            ?? (fan.targetRPM > 0 ? fan.targetRPM : fan.rpm)
        target = Double(min(max(start, fan.minRPM), max(fan.maxRPM, fan.minRPM + 1)))
    }
}
